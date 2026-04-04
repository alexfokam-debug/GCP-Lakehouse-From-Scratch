/*
================================================================================
LAKEHOUSE STACK — terraform/lakehouse/main.tf

Objectif (stack "data platform") :
- Ressources data qui évoluent souvent (datasets, tables, assets, repo Dataform, etc.)
- C’est la couche “produit data” (Raw/Silver/Curated/Analytics, Dataplex, Dataform...)

Contenu :
✅ GCS : raw / curated / iceberg / scripts / dataproc-temp
✅ BigQuery : datasets, external tables, BigLake connection
✅ Dataplex : lake + zones + assets
✅ Dataform : repository + workflows
✅ Bootstrap files : pour éviter “matched no files” sur external tables

Ce que LAKEHOUSE ne doit PAS gérer :
❌ WIF pool/provider GitHub (ça = security foundation)
❌ IAM global “entreprise”
=> Ces sujets restent dans FOUNDATION

Note IAM dans LAKEHOUSE :
- On fait uniquement les IAM “techniques” nécessaires au fonctionnement :
  - BigLake connection SA -> lire RAW/CURATED + accès ICEBERG bucket
  - (Optionnel) Dataform/Dataproc runtimes -> souvent gérés via module IAM côté lakehouse
================================================================================
*/

# =============================================================================
# 0) LOCALS — Naming & conventions (single source of truth)
# =============================================================================
locals {
  # Environnement : dev | staging | prod
  env = var.environment

  # Préfixe global (cohérent avec foundation)
  project_prefix = "lakehouse"

  # Suffixe court tiré du project_id :
  # ex lakehouse-486419 -> 486419
  project_id_short = element(
    split("-", var.project_id),
    length(split("-", var.project_id)) - 1
  )

  # ---------------------------------------------------------------------------
  # Naming standardisé des buckets (évite 2 conventions en parallèle)
  # ---------------------------------------------------------------------------
  bucket_raw_name           = "${local.project_prefix}-${local.project_id_short}-raw-${local.env}"
  bucket_curated_name       = "${local.project_prefix}-${local.project_id_short}-curated-${local.env}"
  bucket_iceberg_name       = "${local.project_prefix}-${local.project_id_short}-iceberg-${local.env}"
  bucket_scripts_name       = "${local.project_prefix}-${local.project_id_short}-scripts-${local.env}"
  bucket_dataproc_temp_name = "${local.project_prefix}-${local.project_id_short}-dataproc-temp-${local.env}"

  # ---------------------------------------------------------------------------
  # External tables CURATED (BigLake ICEBERG) :
  # - si enable=false => map vide => aucune table créée
  # ---------------------------------------------------------------------------
  curated_external_tables_effective = tomap(
    var.enable_curated_external_tables ? var.curated_external_tables : {}
  )
}

# =============================================================================
# 1) GCS — RAW bucket (landing / external tables source)
# =============================================================================
module "gcs_raw" {
  source = "../modules/gcs"

  project_id  = var.project_id
  bucket_name = local.bucket_raw_name
  environment = local.env
  location    = var.region

  # Optionnel : si ton module gcs structure les dossiers "domain/dataset"
  domain       = var.domain
  dataset_name = var.dataset_name

  labels = var.labels
}

# =============================================================================
# 2) GCS — CURATED bucket (pour datasets/exports si besoin)
# =============================================================================
module "gcs_curated" {
  source = "../modules/gcs"

  project_id  = var.project_id
  bucket_name = local.bucket_curated_name
  environment = local.env
  location    = var.region

  domain       = var.domain
  dataset_name = var.dataset_name
  layer        = "curated"

  labels = var.labels
}

# =============================================================================
# 3) BIGQUERY — datasets + BigLake connection (module bq)
# -----------------------------------------------------------------------------
# Ce module doit créer au minimum :
# - curated_<env> (dataset managed)
# - enterprise_<env> (si tu l’as)
# - tmp_lakehouse_<env> (si enable_tmp_dataset=true)
# - BigLake connection (cloud_resource) -> donne le SA "bqcx-....@gcp-sa-bigquery-condel"
# =============================================================================
module "bq" {
  source = "../modules/bigquery"

  project_id  = var.project_id
  environment = local.env
  location    = var.region
  labels      = var.labels

  enable_tmp_dataset                  = var.enable_tmp_dataset
  enable_sales_orders_external_tables = var.enable_sales_orders_external_tables
}

# =============================================================================
# 4) WAIT — propagation BigLake Connection SA
# -----------------------------------------------------------------------------
# Problème classique :
# - La BigLake connection SA (bqcx-xxx) est parfois "visible" côté Terraform
#   mais pas encore propagée côté IAM lors de l'apply immédiat.
# - time_sleep = "airbag" simple pour éviter les erreurs IAM sur le SA.
# =============================================================================
resource "time_sleep" "wait_biglake_sa" {
  # On attend que la connexion BigLake existe (et que son SA soit “résolu”)
  depends_on      = [module.bq]
  create_duration = "30s"
}

# =============================================================================
# 5) IAM minimal — BigLake connection SA : read RAW + CURATED buckets
# -----------------------------------------------------------------------------
# BigLake (external tables) lit des objets dans GCS.
# => roles/storage.objectViewer suffit pour lecture.
# =============================================================================
resource "google_storage_bucket_iam_member" "raw_biglake_reader" {
  depends_on = [time_sleep.wait_biglake_sa]

  bucket = module.gcs_raw.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

resource "google_storage_bucket_iam_member" "curated_biglake_reader" {
  depends_on = [time_sleep.wait_biglake_sa]

  bucket = module.gcs_curated.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

# =============================================================================
# 6) BIGQUERY — Dataset RAW External (raw_ext_<env>)
# -----------------------------------------------------------------------------
# Dataset dédié aux tables externes (GCS -> BigQuery)
# =============================================================================
resource "google_bigquery_dataset" "raw_external" {
  project    = var.project_id
  dataset_id = "raw_ext_${local.env}"
  location   = var.region

  labels = merge(var.labels, {
    layer   = "raw"
    type    = "external"
    domain  = var.domain
    dataset = var.dataset_name
  })
}

# =============================================================================
# 7) BIGQUERY — External tables RAW
# -----------------------------------------------------------------------------
# var.raw_external_tables = map(table_id -> { source_format, source_uris })
# Exemple:
# raw_external_tables = {
#   orders = { source_format="PARQUET", source_uris=["gs://.../*.parquet"] }
# }
# =============================================================================
resource "google_bigquery_table" "raw_external_tables" {
  for_each = var.raw_external_tables

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw_external.dataset_id
  table_id   = each.key

  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = each.value.source_format
    source_uris   = each.value.source_uris
  }

  labels = merge(var.labels, {
    layer = "raw"
    type  = "external_table"
  })
}

# =============================================================================
# 8) BIGQUERY — Dataset ANALYTICS (analytics_<env>) (sortie Dataform)
# -----------------------------------------------------------------------------
# Dataform écrira typiquement ici ses tables/vues matérialisées.
# =============================================================================
resource "google_bigquery_dataset" "analytics" {
  project    = var.project_id
  dataset_id = "analytics_${local.env}"
  location   = var.region

  labels = merge(var.labels, {
    layer  = "analytics"
    type   = "managed"
    domain = var.domain
  })
}

# =============================================================================
# 9) DATAPLEX — lake / zones / assets
# -----------------------------------------------------------------------------
# Dataplex référence :
# - un bucket raw (GCS asset)
# - des datasets curated/raw_ext (BQ asset)
# =============================================================================
module "dataplex" {
  count  = var.enable_dataplex ? 1 : 0
  source = "../modules/dataplex"

  project_id  = var.project_id
  region      = var.region
  environment = local.env

  raw_bucket           = module.gcs_raw.bucket_name
  curated_dataset      = module.bq.curated_dataset_id
  raw_external_dataset = google_bigquery_dataset.raw_external.dataset_id

  labels = var.labels
}

# =============================================================================
# 10) BIGQUERY — Dataset CURATED external (curated_ext_<env>)
# -----------------------------------------------------------------------------
# Dataset dédié aux external tables côté curated (ex : ICEBERG via BigLake)
# =============================================================================
resource "google_bigquery_dataset" "curated_external" {
  project    = var.project_id
  dataset_id = "curated_ext_${local.env}"
  location   = var.region

  labels = merge(var.labels, {
    layer   = "curated"
    type    = "external"
    domain  = var.domain
    dataset = var.dataset_name
  })
}

# =============================================================================
# 11) BIGQUERY — External tables CURATED (ICEBERG via BigLake)
# -----------------------------------------------------------------------------
# Important :
# - source_format = "ICEBERG"
# - connection_id = BigLake connection
# - source_uris   = URIs des tables iceberg (souvent racine du dataset/table)
# =============================================================================
resource "google_bigquery_table" "curated_external_tables" {
  for_each = local.curated_external_tables_effective

  project    = var.project_id
  dataset_id = google_bigquery_dataset.curated_external.dataset_id
  table_id   = each.key

  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "ICEBERG"

    # BigLake connection obligatoire pour ICEBERG externe
    connection_id = module.bq.biglake_connection_id

    # URIs racines Iceberg
    source_uris = try(each.value["source_uris"], [])
  }

  labels = merge(var.labels, {
    layer  = "curated"
    format = "iceberg"
    type   = "external_table"
  })
}

# =============================================================================
# 12) BIGQUERY — Dataset CURATED_ICEBERG (managed iceberg côté BQ)
# -----------------------------------------------------------------------------
# Dataset "managed" côté BigQuery (si tu y crées des objets iceberg gérés BQ)
# =============================================================================
resource "google_bigquery_dataset" "curated_iceberg" {
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  location   = var.region

  labels = merge(var.labels, {
    layer  = "curated"
    type   = "iceberg"
    domain = var.domain
  })
}

# =============================================================================
# 13) GCS — bucket ICEBERG (stockage physique iceberg)
# =============================================================================
module "gcs_iceberg" {
  source = "../modules/gcs"

  project_id  = var.project_id
  bucket_name = local.bucket_iceberg_name
  environment = local.env
  location    = var.region

  domain       = var.domain
  dataset_name = var.dataset_name

  labels = merge(var.labels, {
    layer = "curated"
    type  = "iceberg"
  })
}

# =============================================================================
# 14) IAM minimal — BigLake SA : accès au bucket ICEBERG
# -----------------------------------------------------------------------------
# Pour ICEBERG via BigLake :
# - legacyBucketReader : lecture metadata bucket (listing / perms bucket-level)
# - objectUser         : lecture + écriture objets (selon usage)
# =============================================================================
resource "google_storage_bucket_iam_member" "iceberg_bucket_reader" {
  depends_on = [time_sleep.wait_biglake_sa]

  bucket = module.gcs_iceberg.bucket_name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

resource "google_storage_bucket_iam_member" "iceberg_object_user" {
  depends_on = [time_sleep.wait_biglake_sa]

  bucket = module.gcs_iceberg.bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

# =============================================================================
# 15) GCS — bucket SCRIPTS (jobs, notebooks, artefacts, etc.)
# =============================================================================
module "gcs_scripts" {
  source = "../modules/gcs"

  project_id  = var.project_id
  bucket_name = local.bucket_scripts_name
  environment = local.env
  location    = var.region

  domain       = var.domain
  dataset_name = var.dataset_name

  labels = merge(var.labels, { layer = "scripts" })
}

# =============================================================================
# 16) GCS — bucket DATAPROC TEMP
# -----------------------------------------------------------------------------
# Bucket utilitaire : staging temporaire (Dataproc/Serverless, Spark, etc.)
# Naming aligné sur la convention globale.
# =============================================================================
module "gcs_dataproc_temp" {
  source = "../modules/gcs"

  project_id  = var.project_id
  bucket_name = local.bucket_dataproc_temp_name
  environment = local.env
  location    = var.region

  domain       = var.domain
  dataset_name = var.dataset_name

  labels = merge(var.labels, { layer = "tmp" })
}

# =============================================================================
# 17) DATAFORM — repository + workflows
# -----------------------------------------------------------------------------
# Notes :
# - Dataform se connecte à Git via Secret Manager (version "latest" ou numéro).
# - Le secret doit exister (terraform ou manuel).
# - default_schema = dataset analytics_<env>
# =============================================================================
module "dataform" {
  source = "../modules/dataform"

  providers = {
    google      = google
    google-beta = google-beta
  }

  project_id      = var.project_id
  region          = var.region
  environment     = local.env
  repository_name = var.dataform_repository_name
  # Git config
  dataform_git_repo_url             = var.dataform_git_repo_url
  dataform_default_branch           = var.dataform_default_branch
  dataform_git_token_secret_version = var.dataform_git_token_secret_version
  enable_git                        = var.dataform_enable_git

  # Compilation defaults
  default_schema = google_bigquery_dataset.analytics.dataset_id
  git_commitish  = var.dataform_default_branch

  # Workflows
  workflow_cron = var.dataform_workflow_cron
  time_zone     = var.dataform_time_zone

  # Runtime SA
  dataform_sa_email = var.dataform_sa_email

  labels = merge(var.labels, { env = local.env })
}
# =============================================================================
# 18) BOOTSTRAP FILES — pour que les external tables “matchent” un fichier
# -----------------------------------------------------------------------------
# Problème : external tables peuvent échouer si le wildcard ne match aucun fichier
# Solution : uploader un petit parquet sample pour garantir 1 match
#
# ⚠️ Important : source doit être stable. Si tu changes le chemin,
# Terraform remplace l’objet (c’est ce que tu as vu dans tes plans).
# =============================================================================
resource "google_storage_bucket_object" "bootstrap_orders_parquet" {
  count = var.enable_sales_orders_external_tables ? 1 : 0

  # Objet "sentinelle" : sert uniquement à garantir qu'au moins 1 fichier matche
  # les wildcards des external tables (évite les erreurs "matched no files").
  name   = "domain=${var.domain}/dataset=orders/orders_0001.parquet"
  bucket = module.gcs_raw.bucket_name

  # ✅ path.module => stable depuis ce fichier, même si tu changes le cwd
  source = "${path.module}/../../data/sample.parquet"

  # -----------------------------------------------------------------------
  # ENTREPRISE / CI-STABLE
  # -----------------------------------------------------------------------
  # Problème fréquent : Terraform détecte des "diffs" sur l'objet GCS (md5hash,
  # generation, crc32c, etc.) même si l'objectif métier n'est pas de recharger
  # ce fichier à chaque run.
  #
  # Ici, ce fichier est un bootstrap (placeholder). On veut donc :
  # - éviter un drift permanent dans `plan`
  # - éviter des updates inutiles en CI
  #
  # `detect_md5hash = false` : n'utilise pas le hash du fichier local pour
  # déclencher un update.
  detect_md5hash = false

  # Le fichier est un simple bootstrap (placeholder). On ne veut pas que des
  # changements de contenu local (sample.parquet) ou des métadonnées côté GCS
  # provoquent un "plan" en drift permanent.
  #
  # `source` est un argument Terraform (pas un attribut provider-only), donc
  # c'est le seul champ pertinent à ignorer ici.
  lifecycle {
    ignore_changes = [
      source,
    ]
  }
}

resource "google_storage_bucket_object" "bootstrap_sales_transactions_parquet" {
  count = var.enable_sales_orders_external_tables ? 1 : 0

  # Objet "sentinelle" : sert uniquement à garantir qu'au moins 1 fichier matche
  # les wildcards des external tables (évite les erreurs "matched no files").
  name   = "domain=${var.domain}/dataset=sales_transactions/sales_transactions_0001.parquet"
  bucket = module.gcs_raw.bucket_name

  source = "${path.module}/../../data/sample.parquet"

  # Même logique de stabilité CI que pour `bootstrap_orders_parquet`
  detect_md5hash = false

  # Même logique que pour `bootstrap_orders_parquet` : on ignore le `source`
  # pour éviter des updates inutiles en CI.
  lifecycle {
    ignore_changes = [
      source,
    ]
  }
}

# =============================================================================
# 17bis) IAM — RUNTIMES DATA (DATAFORM / DATAPROC)
# =============================================================================
module "iam_lakehouse_runtime" {
  source = "../modules/iam"

  # ---------------------------------------------------------------------------
  # Common
  # ---------------------------------------------------------------------------
  project_id  = var.project_id
  environment = local.env

  # ---------------------------------------------------------------------------
  # Désactivation explicite de tout ce qui appartient à foundation
  # ---------------------------------------------------------------------------
  manage_wif                        = false
  enable_github_cicd_wif_pool_admin = false
  bootstrap_ci_iam                  = false
  enable_human_build_access         = false
  enable_cloud_build_runtime_access = false

  # ---------------------------------------------------------------------------
  # Activation des runtimes data
  # ---------------------------------------------------------------------------
  enable_lakehouse_runtimes = true

  # ---------------------------------------------------------------------------
  # Datasets BigQuery
  # ---------------------------------------------------------------------------
  curated_dataset_id         = module.bq.curated_dataset_id
  analytics_dataset_id       = google_bigquery_dataset.analytics.dataset_id
  raw_external_dataset_id    = google_bigquery_dataset.raw_external.dataset_id
  curated_iceberg_dataset_id = google_bigquery_dataset.curated_iceberg.dataset_id
  tmp_dataset_id             = module.bq.tmp_dataset_id
  enable_tmp_dataset         = var.enable_tmp_dataset
  enterprise_dataset_id      = module.bq.enterprise_dataset_id

  # ---------------------------------------------------------------------------
  # Buckets GCS
  # ---------------------------------------------------------------------------
  raw_bucket_name           = module.gcs_raw.bucket_name
  curated_bucket_name       = module.gcs_curated.bucket_name
  iceberg_bucket_name       = module.gcs_iceberg.bucket_name
  dataproc_temp_bucket_name = module.gcs_dataproc_temp.bucket_name
  scripts_bucket_name       = module.gcs_scripts.bucket_name

  depends_on = [
    module.bq,
    module.gcs_raw,
    module.gcs_curated,
    module.gcs_iceberg,
    module.gcs_scripts,
    module.gcs_dataproc_temp,
    google_bigquery_dataset.raw_external,
    google_bigquery_dataset.analytics,
    google_bigquery_dataset.curated_external,
    google_bigquery_dataset.curated_iceberg
  ]
}

# =============================================================================
# 11bis) BIGQUERY — External tables CURATED PREPARED (PARQUET)
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Exposer dans BigQuery les fichiers Parquet produits par Dataproc
# dans la zone CURATED / PREPARED.
#
# Pourquoi ce bloc ?
# - Les fichiers existent déjà dans GCS
# - On veut les rendre requêtables immédiatement en SQL
# - C'est l'étape naturelle avant Dataform
#
# Exemple :
# gs://lakehouse-486419-curated-dev/domain=weather/dataset=arco_era5/prepared/daily_vertical_profile_vo/*.parquet
#
# Résultat :
# - dataset : curated_ext_dev
# - table   : arco_era5_vertical_profile_vo
#
# NOTE IMPORTANTE
# -----------------------------------------------------------------------------
# Ici on reste sur une external table "classique" PARQUET.
# Donc :
# - pas besoin de BigLake connection_id
# - pas besoin de format ICEBERG
# - BigQuery lit directement les fichiers Parquet
# =============================================================================
resource "google_bigquery_table" "curated_prepared_external_tables" {
  for_each = var.curated_prepared_external_tables

  project    = var.project_id
  dataset_id = google_bigquery_dataset.curated_external.dataset_id
  table_id   = each.key

  deletion_protection = false

  external_data_configuration {
    autodetect    = try(each.value.autodetect, true)
    source_format = each.value.source_format
    source_uris   = each.value.source_uris
  }

  labels = merge(var.labels, {
    layer  = "curated"
    zone   = "prepared"
    format = "parquet"
    type   = "external_table"
  })
}
