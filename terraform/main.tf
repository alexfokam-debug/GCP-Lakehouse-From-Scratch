/*
 Main Terraform entry point.

 On construit progressivement notre lakehouse avec des modules :
 - GCS (RAW + CURATED)
 - BigQuery + BigLake connection
 - IAM (autoriser BigLake à lire GCS)
*/

# =========================
# Naming - single source of truth
# =========================
# Objectif:
# - Centraliser TOUS les noms ici
# - Éviter les erreurs "prd" vs "prod"
# - Garder des patterns cohérents sur buckets / datasets / service accounts
locals {
  # =========================================================
  # Naming - single source of truth
  # =========================================================
  # Objectif :
  # - Centraliser TOUS les noms ici
  # - Eviter les erreurs "prd" vs "prod"
  # - Garder des patterns cohérents (buckets/datasets/SA)
  # =========================================================

  # (1) Environnement courant
  # -> On prend la variable "environment" venant de terraform.tfvars
  # Exemples attendus : "dev" | "staging" | "prod"
  env = var.environment

  # (2) Préfixe global
  # -> Simple préfixe "métier" pour tous les objets (buckets, etc.)
  # -> Tu peux aussi le mettre en variable si tu veux le changer facilement.
  project_prefix = "lakehouse"

  # (3) Objectif: extraire automatiquement "486419" depuis le project_id
  # Exemple: "lakehouse-stg-486419" -> ["lakehouse","stg","486419"] -> "486419"
  project_id_short = element(
    split("-", var.project_id),
    length(split("-", var.project_id)) - 1
  )

  # (4) Noms des buckets
  # Pattern final :
  # lakehouse-486419-raw-staging
  # lakehouse-486419-curated-staging
  # etc.
  bucket_raw_name     = "${local.project_prefix}-${local.project_id_short}-raw-${local.env}"
  bucket_curated_name = "${local.project_prefix}-${local.project_id_short}-curated-${local.env}"
  bucket_iceberg_name = "${local.project_prefix}-${local.project_id_short}-iceberg-${local.env}"
  bucket_scripts_name = "${local.project_prefix}-${local.project_id_short}-scripts-${local.env}"
}
# ============================================================
# APIs (minimum pour Dataform + BQ)
# ============================================================
resource "google_project_service" "services" {
  for_each = toset([
    "dataform.googleapis.com",
    "bigquery.googleapis.com",
    "dataplex.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "dataproc.googleapis.com",
    "compute.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# =========================
# Module GCS - RAW layer
# =========================
module "gcs_raw" {
  source = "./modules/gcs"

  # Projet GCP dans lequel créer le bucket
  project_id = var.project_id

  # Nom standardisé : <project>-<layer>-<env>
  bucket_name  = "${var.project_id}-raw-${var.environment}"
  domain       = var.domain
  dataset_name = var.dataset_name

  # Environnement (dev / prod)
  environment = var.environment

  # Multi-région / région storage (EU, US, etc.)
  location = var.region



  # Labels projet (le module ajoute aussi ses labels standards)
  labels = var.labels
}

# ============================
# Module GCS - CURATED layer
# ============================
module "gcs_curated" {
  source = "./modules/gcs"

  project_id   = var.project_id
  bucket_name  = "${var.project_id}-curated-${var.environment}"
  environment  = var.environment
  location     = var.region
  domain       = var.domain
  dataset_name = var.dataset_name

  layer  = "curated"
  labels = var.labels
}

# =========================
# Module BigQuery + BigLake
# =========================
module "bq" {
  source = "./modules/bigquery"

  project_id  = var.project_id
  environment = var.environment
  location    = var.region

  labels                              = var.labels
  enable_tmp_dataset                  = var.enable_tmp_dataset
  enable_sales_orders_external_tables = var.enable_sales_orders_external_tables

}

# ==========================================================
# Attendre la propagation du service account BigLake
# ==========================================================
# Le SA de BigLake est créé via google_bigquery_connection.
# Google met parfois quelques secondes à le rendre "visible",
# donc on attend avant d'appliquer les IAM sur les buckets.
resource "time_sleep" "wait_biglake_sa" {
  depends_on      = [module.bq]
  create_duration = "30s"
}

# ==========================================================
# IAM : autoriser BigLake (Connection SA) à lire GCS
# ==========================================================
# BigLake/BigQuery lit les fichiers dans GCS avec le service account
# associé à la BigQuery Connection => on donne storage.objectViewer.

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


# =========================
# Module Dataplex (catalog + gouvernance légère)
# =========================
module "dataplex" {
  source = "./modules/dataplex"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # ✅ noms EXACTS attendus par le module
  raw_bucket           = module.gcs_raw.bucket_name
  curated_dataset      = module.bq.curated_dataset_id
  raw_external_dataset = google_bigquery_dataset.raw_external.dataset_id

  labels = var.labels
}

# ============================================================
# BigQuery dataset RAW – External tables
# ============================================================
# Ce dataset est destiné à exposer des fichiers stockés dans GCS
# (Parquet, Avro, CSV…) via des tables externes BigQuery.
#
# ➜ Il correspond à la couche RAW du lakehouse
# ➜ Il ne stocke PAS de données BigQuery managées
# ➜ Il sert de point d’entrée analytique sur le data lake
# ============================================================

resource "google_bigquery_dataset" "raw_external" {

  # ----------------------------------------------------------
  # Projet GCP cible
  # ----------------------------------------------------------
  # Permet de déployer le même module sur plusieurs projets
  # (dev / prod / sandbox / client)
  project = var.project_id

  # ----------------------------------------------------------
  # Identifiant du dataset BigQuery
  # ----------------------------------------------------------
  # Convention entreprise :
  # raw_ext_<env>
  # ex: raw_ext_dev, raw_ext_prod
  dataset_id = "raw_ext_${var.environment}"

  # ----------------------------------------------------------
  # Localisation du dataset
  # ----------------------------------------------------------
  # Doit être COHÉRENTE avec :
  # - BigQuery connection BigLake
  # - Dataplex Lake
  # - GCS buckets
  #
  # Ici : europe-west1 (choix régional strict)
  location = var.region

  # ----------------------------------------------------------
  # Labels de gouvernance & FinOps
  # ----------------------------------------------------------
  # Labels communs + enrichissement spécifique BigQuery
  #
  # Objectifs :
  # - Cost tracking
  # - Ownership clair
  # - Data catalog / Dataplex
  # - Standards entreprise
  labels = merge(
    var.labels,
    {
      # Couche du lakehouse
      layer = "raw"

      # Type de dataset
      type = "external"

      # Domaine métier (sales, finance, hr…)
      domain = var.domain

      # Dataset logique métier
      dataset = var.dataset_name
    }
  )
}

# ============================================================
# BigQuery RAW external tables (managed by Terraform)
# ============================================================
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
# ============================================================
# BigQuery dataset ANALYTICS – sortie Dataform (tables vues / marts)
# ============================================================
resource "google_bigquery_dataset" "analytics" {
  # Projet cible
  project = var.project_id

  # Convention entreprise : analytics_<env>
  dataset_id = "analytics_${var.environment}"

  # Localisation cohérente avec le reste
  location = var.region

  # Labels (FinOps / ownership / gouvernance)
  labels = merge(
    var.labels,
    {
      layer  = "analytics"
      type   = "managed"
      domain = var.domain
    }
  )
}
# =========================
# Module IAM (Dataform SA + droits)
# =========================
module "iam" {
  source = "./modules/iam"

  project_id        = var.project_id
  environment       = var.environment
  dataproc_sa_email = var.dataproc_sa_email
  project_number    = data.google_project.current.number
  dataform_sa_email = var.dataform_sa_email
  raw_bucket_name   = "lakehouse-${var.project_id_short}-raw-${var.environment}"


  tmp_dataset_id = module.bq.tmp_dataset_id

  curated_dataset_id      = module.bq.curated_dataset_id
  analytics_dataset_id    = google_bigquery_dataset.analytics.dataset_id
  raw_external_dataset_id = google_bigquery_dataset.raw_external.dataset_id
  # dataset curated iceberg
  curated_iceberg_dataset_id = google_bigquery_dataset.curated_iceberg.dataset_id
  # bucket Iceberg (nom du bucket où vivent les tables Iceberg)
  iceberg_bucket_name = module.gcs_iceberg.bucket_name
  # ou si ton module gcs_iceberg expose "bucket_name" directement :
  # iceberg_bucket_name = module.gcs_iceberg.bucket_name
  dataproc_temp_bucket_name = module.gcs_dataproc_temp.bucket_name
  enable_tmp_dataset        = var.enable_tmp_dataset
}

###############################################################################
# Module DATAFORM (ROOT)
# Objectif :
# - Créer le repository Dataform dans GCP
# - Le connecter à ton repo GitHub
# - Utiliser un token stocké dans Secret Manager (version "latest")
#
# IMPORTANT :
# - La ressource Dataform est dans google-beta
# - On passe explicitement google-beta au module
###############################################################################
module "dataform" {
  # ---------------------------------------------------------------------------
  # Chemin du module
  # ---------------------------------------------------------------------------
  source = "./modules/dataform"

  # ---------------------------------------------------------------------------
  # IMPORTANT : Dataform = provider google-beta
  # On passe google + google-beta au module
  # ---------------------------------------------------------------------------
  providers = {
    google      = google
    google-beta = google-beta
  }

  # ---------------------------------------------------------------------------
  # Contexte projet / région / env
  # ---------------------------------------------------------------------------
  project_id      = var.project_id
  region          = var.region
  environment     = var.environment
  repository_name = var.dataform_repository_name


  # ---------------------------------------------------------------------------
  # Nommage repository Dataform
  # repo_name = ID technique (API)
  # repo_display_name = nom lisible dans la console
  # ---------------------------------------------------------------------------
  repo_name         = "lakehouse-${var.environment}-dataform"
  repo_display_name = "lakehouse-${var.environment}-dataform"

  # ---------------------------------------------------------------------------
  # Git settings (variables ROOT)
  # ---------------------------------------------------------------------------
  git_repo_url       = var.dataform_git_repo_url
  git_default_branch = var.dataform_default_branch


  # ---------------------------------------------------------------------------
  # Secret Manager : version du token (ROOT)
  # Exemple :
  # projects/518653594867/secrets/dataform-git-token/versions/latest
  # ---------------------------------------------------------------------------
  git_token_secret_version = var.dataform_git_token_secret_version

  # dataset de sortie
  default_schema = google_bigquery_dataset.analytics.dataset_id

  # ---------------------------------------------------------------------------
  # Labels : on réutilise tes labels + on force env
  # ---------------------------------------------------------------------------
  labels = merge(var.labels, {
    env = var.environment
  })
  dataform_sa_email = var.dataform_sa_email
}

# ============================================================
# BigQuery dataset CURATED – External (BigLake)
# ============================================================
# Objectif :
# - Exposer la couche CURATED stockée dans GCS (format ouvert)
# - Via BigQuery en "external tables" (BigLake)
# - Cette couche sert aux lectures SQL (BQ, Looker, etc.)
# ============================================================

resource "google_bigquery_dataset" "curated_external" {

  # ----------------------------------------------------------
  # Projet GCP cible
  # ----------------------------------------------------------
  project = var.project_id

  # ----------------------------------------------------------
  # Convention entreprise : curated_ext_<env>
  # ----------------------------------------------------------
  dataset_id = "curated_ext_${var.environment}"

  # ----------------------------------------------------------
  # Région cohérente (BQ / Dataplex / buckets)
  # ----------------------------------------------------------
  location = var.region

  # ----------------------------------------------------------
  # Labels de gouvernance / FinOps
  # ----------------------------------------------------------
  labels = merge(
    var.labels,
    {
      layer   = "curated"
      type    = "external"
      domain  = var.domain
      dataset = var.dataset_name
    }
  )
}

# ============================================================
# BigQuery CURATED external tables (BigLake)
# ============================================================
# Objectif :
# - Créer des tables externes pointant vers les données CURATED
# - Idéalement au format ICEBERG (ou PARQUET si phase 1)
# ============================================================

locals {
  curated_external_tables_effective = tomap(
    var.enable_curated_external_tables ? var.curated_external_tables : {}
  )
}

resource "google_bigquery_table" "curated_external_tables" {
  # ------------------------------------------------------------
  # Création dynamique de tables ICEBERG externes
  # (clé = nom table, valeur = config)
  # ------------------------------------------------------------
  for_each = local.curated_external_tables_effective

  project    = var.project_id
  dataset_id = google_bigquery_dataset.curated_external.dataset_id
  table_id   = each.key

  # ------------------------------------------------------------
  # On autorise suppression (en staging/dev)
  # En prod tu peux passer à true
  # ------------------------------------------------------------
  deletion_protection = false

  external_data_configuration {

    # ------------------------------------------------------------
    # IMPORTANT :
    # Terraform provider exige souvent autodetect,
    # même pour ICEBERG.
    #
    # Pour ICEBERG, BigQuery lit le schéma depuis
    # le metadata Iceberg → donc autodetect = true
    # est le choix le plus safe.
    # ------------------------------------------------------------
    autodetect = true

    # ------------------------------------------------------------
    # Format externe : ICEBERG
    # ------------------------------------------------------------
    source_format = "ICEBERG"

    # ------------------------------------------------------------
    # OBLIGATOIRE en BigLake :
    # connexion BigQuery (cloud_resource)
    #
    # Sans ça, BigQuery ne peut pas accéder
    # aux fichiers Iceberg sur GCS.
    #
    # ⚠️ Nécessite que ton module BigQuery expose
    # l'output biglake_connection_id
    # ------------------------------------------------------------
    connection_id = module.bq.biglake_connection_id

    # ------------------------------------------------------------
    # URI GCS de la racine de la table Iceberg
    #
    # Exemple attendu :
    # gs://bucket/iceberg/customers
    #
    # Attention :
    # - Le dossier doit contenir metadata Iceberg
    # - Sinon "matched no files"
    # ------------------------------------------------------------
    source_uris = try(each.value["source_uris"], [])
  }

  labels = merge(
    var.labels,
    {
      layer  = "curated"
      format = "iceberg"
    }
  )
}

# =============================================================================
# BigQuery dataset CURATED_ICEBERG
# =============================================================================
# Objectif :
# - Dataset dédié aux tables Iceberg
# - Séparation claire architecture entreprise
# - Meilleure gouvernance et FinOps
# =============================================================================

resource "google_bigquery_dataset" "curated_iceberg" {

  # ---------------------------------------------------------------------------
  # Projet GCP cible
  # ---------------------------------------------------------------------------
  project = var.project_id

  # ---------------------------------------------------------------------------
  # ID du dataset (ex: curated_iceberg_dev)
  # ---------------------------------------------------------------------------
  dataset_id = var.curated_iceberg_dataset_id

  # ---------------------------------------------------------------------------
  # Région (DOIT matcher BigQuery / Dataplex / Connection)
  # ---------------------------------------------------------------------------
  location = var.region

  # ---------------------------------------------------------------------------
  # Labels entreprise
  # ---------------------------------------------------------------------------
  labels = merge(
    var.labels,
    {
      layer  = "curated"
      type   = "iceberg"
      domain = var.domain
    }
  )
}
# =============================================================================
# Bucket GCS dédié Iceberg
# =============================================================================
# Objectif :
# - Stocker les fichiers physiques Iceberg
# - Isoler du curated "managed"
# - Permet évolution future Spark / Dataproc
# =============================================================================

module "gcs_iceberg" {
  source = "./modules/gcs"

  # Projet
  project_id = var.project_id

  # Nom standard entreprise
  bucket_name = "${var.project_id}-iceberg-${var.environment}"

  # Environnement & région
  environment = var.environment
  location    = var.region

  # Structuration métier
  domain       = var.domain
  dataset_name = var.dataset_name

  # Labels enrichis
  labels = merge(
    var.labels,
    {
      layer = "curated"
      type  = "iceberg"
    }
  )
}

# =============================================================================
# IAM : BigQuery Connection SA -> écriture Iceberg
# =============================================================================
# IMPORTANT :
# Iceberg "managed" par BigQuery écrit physiquement dans GCS
# => le service account BigQuery Connection doit avoir write
# =============================================================================

resource "google_storage_bucket_iam_member" "iceberg_object_user" {

  bucket = module.gcs_iceberg.bucket_name

  # Permet écriture / suppression objets
  role = "roles/storage.objectUser"

  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

resource "google_storage_bucket_iam_member" "iceberg_bucket_reader" {

  bucket = module.gcs_iceberg.bucket_name

  # Lecture metadata bucket
  role = "roles/storage.legacyBucketReader"

  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

###############################################################################
# Bucket "scripts" : artefacts (pyspark, jar, conf) pour Dataproc Serverless
# - Séparation claire : data buckets vs job artefacts
# - CI/CD friendly
###############################################################################
# =========================
# Module GCS - SCRIPTS layer (pour Dataproc / jobs / notebooks)
# =========================
module "gcs_scripts" {
  source = "./modules/gcs"

  project_id = var.project_id

  # Bucket dédié scripts (recommandé en entreprise)
  bucket_name = "${var.project_id}-scripts-${var.environment}"

  # Obligatoires car attendus par ton module ./modules/gcs
  environment  = var.environment
  domain       = var.domain
  dataset_name = var.dataset_name

  # Même région que le reste
  location = var.region

  # Labels standard
  labels = merge(var.labels, { layer = "scripts" })
}


module "gcs_dataproc_temp" {
  source = "./modules/gcs"

  project_id  = var.project_id
  location    = var.region
  labels      = var.labels
  environment = var.environment

  # ✅ requis par TON module
  domain       = var.domain
  dataset_name = var.dataset_name
  bucket_name  = "lakehouse-${var.project_id}-dataproc-temp-${var.environment}" # ⚠️ adapte selon ton naming réel
}

# -------------------------------------------------------------------
# BOOTSTRAP FILES (DEV) - pour que BigQuery external tables matchent
# -------------------------------------------------------------------
resource "google_storage_bucket_object" "bootstrap_orders_parquet" {
  count  = var.enable_sales_orders_external_tables ? 1 : 0
  name   = "domain=${var.domain}/dataset=orders/orders_0001.parquet"
  bucket = module.gcs_raw.bucket_name # ou le nom exact du bucket raw
  source = "${path.module}/../data/sample.parquet"
}

resource "google_storage_bucket_object" "bootstrap_sales_transactions_parquet" {
  count  = var.enable_sales_orders_external_tables ? 1 : 0
  name   = "domain=${var.domain}/dataset=sales_transactions/sales_transactions_0001.parquet"
  bucket = module.gcs_raw.bucket_name
  source = "${path.module}/../data/sample.parquet"
}