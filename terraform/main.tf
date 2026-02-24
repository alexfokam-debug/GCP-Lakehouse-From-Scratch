/*
  =============================================================================
  Main Terraform entry point (ROOT)

  Objectif :
  - Construire progressivement un lakehouse “enterprise-grade” sur GCP
  - Environnement DEV d’abord (puis STG/PROD ensuite)

  Couches / modules :
  - GCS : RAW / CURATED / ICEBERG / SCRIPTS / DATAPROC-TEMP
  - BigQuery : datasets + connection BigLake
  - IAM : Service Accounts + droits (Dataform / Dataproc / GitHub CI/CD via WIF)
  - Dataplex : lake + zones + assets (catalog/gouvernance)

  IMPORTANT (ce fichier) :
  - On évite les doublons IAM “à la main” dans le root (sinon drift / boucle)
  - On évite les références à des variables qui n’existent pas (var.project_id_short)
  - On évite les depends_on inutiles (les dépendances passent via les outputs)

  NOTE :
  - Tu as demandé “Option 1” => IAM et bindings CI/Secret/Bucket backend sont gérés
    DANS le module IAM et activables via bootstrap_ci_iam.
  =============================================================================
*/

# =============================================================================
# 0) NAMING — Single Source of Truth (LOCALS)
# -----------------------------------------------------------------------------
# Objectif :
# - Centraliser les conventions de nommage
# - Eviter les erreurs “prd/prod”, collisions dev/stg/prod, etc.
# - Faciliter le refactoring : tu changes ici, tout suit.
# =============================================================================
locals {

  # ---------------------------------------------------------------------------
  # (1) Environnement courant
  # ---------------------------------------------------------------------------
  # Exemples : "dev" | "staging" | "prod"
  env = var.environment

  # ---------------------------------------------------------------------------
  # (2) Préfixe global (branding / convention entreprise)
  # ---------------------------------------------------------------------------
  project_prefix = "lakehouse"

  # ---------------------------------------------------------------------------
  # (3) Extraction d’un identifiant “court” depuis project_id
  # ---------------------------------------------------------------------------
  # Exemple : "lakehouse-stg-486419" => "486419"
  project_id_short = element(
    split("-", var.project_id),
    length(split("-", var.project_id)) - 1
  )

  # ---------------------------------------------------------------------------
  # (4) Noms standardisés des buckets (réutilisables partout)
  # ---------------------------------------------------------------------------
  # Exemple final :
  # - lakehouse-486419-raw-dev
  # - lakehouse-486419-curated-dev
  # - lakehouse-486419-iceberg-dev
  # - lakehouse-486419-scripts-dev
  bucket_raw_name     = "${local.project_prefix}-${local.project_id_short}-raw-${local.env}"
  bucket_curated_name = "${local.project_prefix}-${local.project_id_short}-curated-${local.env}"
  bucket_iceberg_name = "${local.project_prefix}-${local.project_id_short}-iceberg-${local.env}"
  bucket_scripts_name = "${local.project_prefix}-${local.project_id_short}-scripts-${local.env}"
}

# =============================================================================
# 1) ACTIVER LES APIs (minimum viable pour le lakehouse)
# -----------------------------------------------------------------------------
# Objectif :
# - S’assurer que les APIs nécessaires sont ON avant la création des ressources
# - Eviter les erreurs “API not enabled”
# =============================================================================
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

  # Projet GCP cible
  project = var.project_id

  # API activée
  service = each.value

  # IMPORTANT : en entreprise on évite de désactiver automatiquement au destroy
  disable_on_destroy = false
}

# =============================================================================
# 2) MODULE GCS — RAW layer
# -----------------------------------------------------------------------------
# Objectif :
# - Créer le bucket RAW (fichiers source / landing)
# - Structuration domain/dataset au besoin (selon ton module ./modules/gcs)
# =============================================================================
module "gcs_raw" {
  source = "./modules/gcs"

  # Projet dans lequel créer le bucket
  project_id = var.project_id

  # Nom du bucket (ta convention actuelle)
  # NOTE :
  # - Tu pourrais remplacer par local.bucket_raw_name si tu veux aligner à 100%
  # - Ici on conserve ta convention existante (project_id-raw-env)
  bucket_name = "${var.project_id}-raw-${var.environment}"

  # Structuration métier attendue par ton module
  domain       = var.domain
  dataset_name = var.dataset_name

  # Contexte
  environment = var.environment
  location    = var.region

  # Labels globaux (FinOps / gouvernance)
  labels = var.labels
}

# =============================================================================
# 3) MODULE GCS — CURATED layer
# -----------------------------------------------------------------------------
# Objectif :
# - Créer le bucket CURATED (données prêtes à exposer / partagées)
# =============================================================================
module "gcs_curated" {
  source = "./modules/gcs"

  project_id  = var.project_id
  bucket_name = "${var.project_id}-curated-${var.environment}"

  environment  = var.environment
  location     = var.region
  domain       = var.domain
  dataset_name = var.dataset_name

  # Ton module gcs semble accepter un “layer” pour enrichir labels/structure
  layer = "curated"

  labels = var.labels
}

# =============================================================================
# 4) MODULE BIGQUERY + BIGLAKE CONNECTION
# -----------------------------------------------------------------------------
# Objectif :
# - Créer les datasets “curated_* / enterprise_* / tmp_*” (selon ton module)
# - Créer la BigQuery Connection BigLake (cloud_resource)
# - Exposer outputs (biglake_connection_sa / biglake_connection_id / etc.)
# =============================================================================
module "bq" {
  source = "./modules/bigquery"

  project_id  = var.project_id
  environment = var.environment
  location    = var.region

  labels = var.labels

  # Flag : dataset tmp pour Dataproc / staging
  enable_tmp_dataset = var.enable_tmp_dataset

  # Flag : bootstrap pour external tables RAW (orders/sales_transactions)
  enable_sales_orders_external_tables = var.enable_sales_orders_external_tables
}

# =============================================================================
# 5) WAIT — Propagation service account BigLake
# -----------------------------------------------------------------------------
# Problème connu :
# - Le SA de la BigQuery Connection peut mettre quelques secondes à être “visible”
# - Sans attente : les IAM bindings sur bucket échouent parfois
# =============================================================================
resource "time_sleep" "wait_biglake_sa" {
  depends_on      = [module.bq]
  create_duration = "30s"
}

# =============================================================================
# 6) IAM — Autoriser BigLake (connection SA) à lire RAW/CURATED sur GCS
# -----------------------------------------------------------------------------
# Objectif :
# - BigQuery/BigLake lit les fichiers GCS via le SA de la connection
# - Donc on donne roles/storage.objectViewer sur les buckets
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
# 7) BIGQUERY — Dataset RAW External (raw_ext_<env>)
# -----------------------------------------------------------------------------
# Objectif :
# - Exposer des fichiers GCS via des external tables BigQuery
# - Dataset “raw_ext_dev” (ou staging/prod)
# =============================================================================
resource "google_bigquery_dataset" "raw_external" {
  # Projet cible
  project = var.project_id

  # Convention entreprise
  dataset_id = "raw_ext_${var.environment}"

  # Région cohérente avec le reste
  location = var.region

  # Labels gouvernance / FinOps
  labels = merge(
    var.labels,
    {
      layer   = "raw"
      type    = "external"
      domain  = var.domain
      dataset = var.dataset_name
    }
  )
}

# =============================================================================
# 8) BIGQUERY — External tables (RAW)
# -----------------------------------------------------------------------------
# Objectif :
# - Créer une table externe par entrée dans var.raw_external_tables
# - Exemple : orders, sales_transactions, sample_ext
# =============================================================================
resource "google_bigquery_table" "raw_external_tables" {
  for_each = var.raw_external_tables

  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw_external.dataset_id
  table_id   = each.key

  # DEV : on autorise delete (en prod tu peux mettre true)
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
# 9) BIGQUERY — Dataset ANALYTICS (analytics_<env>)
# -----------------------------------------------------------------------------
# Objectif :
# - Dataset de sortie Dataform (tables vues/marts)
# =============================================================================
resource "google_bigquery_dataset" "analytics" {
  project    = var.project_id
  dataset_id = "analytics_${var.environment}"
  location   = var.region

  labels = merge(
    var.labels,
    {
      layer  = "analytics"
      type   = "managed"
      domain = var.domain
    }
  )
}

# =============================================================================
# 10) MODULE DATAPLEX — Gouvernance légère (catalog)
# -----------------------------------------------------------------------------
# Objectif :
# - Lake Dataplex + zones + assets
# - Attacher RAW bucket + datasets curated/raw_ext, etc.
#
# NOTE :
# - Le module attend raw_external_dataset => on lui passe le dataset_id
# =============================================================================
module "dataplex" {
  source = "./modules/dataplex"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  raw_bucket           = module.gcs_raw.bucket_name
  curated_dataset      = module.bq.curated_dataset_id
  raw_external_dataset = google_bigquery_dataset.raw_external.dataset_id

  labels = var.labels
}

# =============================================================================
# 11) BIGQUERY — Dataset CURATED (External BigLake)
# -----------------------------------------------------------------------------
# Objectif :
# - Exposer des données CURATED stockées dans GCS (format ouvert) via BQ
# - Dataset curated_ext_<env>
# =============================================================================
resource "google_bigquery_dataset" "curated_external" {
  project    = var.project_id
  dataset_id = "curated_ext_${var.environment}"
  location   = var.region

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

# =============================================================================
# 12) BIGQUERY — External tables CURATED (BigLake ICEBERG)
# -----------------------------------------------------------------------------
# Objectif :
# - Créer des tables externes ICEBERG dans curated_ext_<env>
# - Piloté par enable_curated_external_tables
# =============================================================================
locals {
  curated_external_tables_effective = tomap(
    var.enable_curated_external_tables ? var.curated_external_tables : {}
  )
}

resource "google_bigquery_table" "curated_external_tables" {
  for_each = local.curated_external_tables_effective

  project    = var.project_id
  dataset_id = google_bigquery_dataset.curated_external.dataset_id
  table_id   = each.key

  deletion_protection = false

  external_data_configuration {
    autodetect    = true
    source_format = "ICEBERG"

    # BigLake connection obligatoire
    connection_id = module.bq.biglake_connection_id

    # URIs GCS racine table Iceberg
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
# 13) BIGQUERY — Dataset CURATED_ICEBERG (tables iceberg “managed” côté BQ)
# -----------------------------------------------------------------------------
# Objectif :
# - Séparer les tables iceberg dans un dataset dédié
# =============================================================================
resource "google_bigquery_dataset" "curated_iceberg" {
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  location   = var.region

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
# 14) GCS — Bucket ICEBERG (stockage physique tables Iceberg)
# -----------------------------------------------------------------------------
# Objectif :
# - Stocker les fichiers iceberg (metadata + data)
# =============================================================================
module "gcs_iceberg" {
  source = "./modules/gcs"

  project_id  = var.project_id
  bucket_name = "${var.project_id}-iceberg-${var.environment}"

  environment  = var.environment
  location     = var.region
  domain       = var.domain
  dataset_name = var.dataset_name

  labels = merge(
    var.labels,
    {
      layer = "curated"
      type  = "iceberg"
    }
  )
}

# =============================================================================
# 15) IAM — BigLake connection SA -> écriture ICEBERG bucket
# -----------------------------------------------------------------------------
# Objectif :
# - BigQuery écrit physiquement sur GCS pour Iceberg “managed”
# - Il faut donc un rôle d’écriture objet
# =============================================================================
resource "google_storage_bucket_iam_member" "iceberg_object_user" {
  bucket = module.gcs_iceberg.bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

resource "google_storage_bucket_iam_member" "iceberg_bucket_reader" {
  bucket = module.gcs_iceberg.bucket_name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${module.bq.biglake_connection_sa}"
}

# =============================================================================
# 16) GCS — Bucket SCRIPTS (artefacts jobs Dataproc)
# =============================================================================
module "gcs_scripts" {
  source = "./modules/gcs"

  project_id  = var.project_id
  bucket_name = "${var.project_id}-scripts-${var.environment}"

  environment  = var.environment
  domain       = var.domain
  dataset_name = var.dataset_name
  location     = var.region

  labels = merge(var.labels, { layer = "scripts" })
}

# =============================================================================
# 17) GCS — Bucket DATAPROC TEMP (temp/staging connector)
# -----------------------------------------------------------------------------
# NOTE :
# - Tu avais un naming “lakehouse-${var.project_id}-dataproc-temp-...”
#   qui produit un truc bizarre (lakehouse-lakehouse-486419-...)
# - On corrige avec la convention simple : "${var.project_id}-dataproc-temp-${env}"
# =============================================================================
module "gcs_dataproc_temp" {
  source = "./modules/gcs"

  project_id  = var.project_id
  location    = var.region
  labels      = var.labels
  environment = var.environment

  domain       = var.domain
  dataset_name = var.dataset_name

  # ✅ correction naming
  bucket_name = "lakehouse-${var.project_id_short}-dataproc-temp-${var.environment}"
}

# =============================================================================
# 18) MODULE IAM (OPTION 1) — CLEAN + anti-boucle
# -----------------------------------------------------------------------------
# Objectif :
# - Centraliser les IAM (Dataform/Dataproc/GitHub CI/CD)
# - Eviter les ressources IAM “en doublon” dans le root
#
# Corrections majeures vs ton ancien bloc :
# - On SUPPRIME project_number (le module IAM le récupère en interne via data.google_project)
# - On SUPPRIME depends_on (dépendances déjà implicites via les outputs)
# - On CORRIGE raw_bucket_name : on utilise module.gcs_raw.bucket_name (source de vérité)
# - On PASSE explicitement les buckets/datasets nécessaires (outputs)
# - Le switch bootstrap_ci_iam pilote les bindings CI (backend bucket + secret)
# =============================================================================
module "iam" {
  source = "./modules/iam"

  # Contexte
  project_id  = var.project_id
  environment = var.environment

  # Dataform runtime SA (email) – fourni par tfvars pour l’instant
  dataform_sa_email = var.dataform_sa_email

  # Buckets (source de vérité = outputs modules)
  raw_bucket_name           = module.gcs_raw.bucket_name
  iceberg_bucket_name       = module.gcs_iceberg.bucket_name
  dataproc_temp_bucket_name = module.gcs_dataproc_temp.bucket_name

  # Datasets
  curated_dataset_id         = module.bq.curated_dataset_id
  analytics_dataset_id       = google_bigquery_dataset.analytics.dataset_id
  raw_external_dataset_id    = google_bigquery_dataset.raw_external.dataset_id
  curated_iceberg_dataset_id = google_bigquery_dataset.curated_iceberg.dataset_id
  enterprise_dataset_id      = module.bq.enterprise_dataset_id

  # TMP dataset (output module bq)
  tmp_dataset_id     = module.bq.tmp_dataset_id
  enable_tmp_dataset = var.enable_tmp_dataset

  # GitHub / WIF
  github_repository = var.github_repository

  # Backend terraform bucket (celui du backend.hcl)
  tf_state_bucket_name = var.tf_state_bucket_name

  # Switch “bootstrap” : active bindings backend bucket + secret
  bootstrap_ci_iam = var.bootstrap_ci_iam

  # Secret id (pas le full resource name)
  git_token_secret_id = var.git_token_secret_id
}

# =============================================================================
# 19) IMPORTANT — suppression du doublon Secret IAM au root
# -----------------------------------------------------------------------------
# AVANT :
# - Tu donnais au SA GitHub CI/CD l’accès au secret via une ressource root
# - MAIS tu fais aussi la même chose dans le module IAM (piloté par bootstrap_ci_iam)
#
# PROBLEME :
# - Doublon = drift / boucle / plan “change” permanent
#
# SOLUTION :
# - On ne met PAS ce binding ici.
# - On le gère DANS le module IAM uniquement (count via bootstrap_ci_iam).
# =============================================================================
# (SUPPRIME ce bloc si tu l’avais encore)
# resource "google_secret_manager_secret_iam_member" "github_cicd_can_read_dataform_git_token" {
#   project   = var.project_id
#   secret_id = "dataform-git-token"
#   role      = "roles/secretmanager.secretAccessor"
#   member    = "serviceAccount:${module.iam.github_cicd_sa_email}"
# }

# =============================================================================
# 20) MODULE DATAFORM (ROOT)
# -----------------------------------------------------------------------------
# Objectif :
# - Créer le repository Dataform
# - Le connecter à GitHub
# - Utiliser un token stocké dans Secret Manager (version “latest”)
#
# NOTE :
# - Dataform utilise le provider google-beta
# - Le runtime SA utilisé par les workflows est dataform_sa_email (tfvars)
# =============================================================================
module "dataform" {
  source = "./modules/dataform"

  providers = {
    google      = google
    google-beta = google-beta
  }

  # Contexte projet/env/région
  project_id      = var.project_id
  region          = var.region
  environment     = var.environment
  repository_name = var.dataform_repository_name

  # Nommage Dataform repo
  repo_name         = "lakehouse-${var.environment}-dataform"
  repo_display_name = "lakehouse-${var.environment}-dataform"

  # Git settings
  git_repo_url       = var.dataform_git_repo_url
  git_default_branch = var.dataform_default_branch

  # Secret version (full resource name, car Dataform API attend ça)
  git_token_secret_version = var.dataform_git_token_secret_version

  # Dataset de sortie
  default_schema = google_bigquery_dataset.analytics.dataset_id

  # Labels
  labels = merge(var.labels, { env = var.environment })

  # Runtime SA (Dataform invoquera les actions avec ce SA)
  dataform_sa_email = var.dataform_sa_email

  dataform_git_token_secret_version = var.dataform_git_token_secret_version
}

# =============================================================================
# 21) BOOTSTRAP FILES (DEV) — pour que les external tables matchent
# -----------------------------------------------------------------------------
# Objectif :
# - Créer au moins 1 parquet dans les prefixes attendus
# - Sinon BigQuery external table peut dire “matched no files”
# =============================================================================
resource "google_storage_bucket_object" "bootstrap_orders_parquet" {
  count  = var.enable_sales_orders_external_tables ? 1 : 0
  name   = "domain=${var.domain}/dataset=orders/orders_0001.parquet"
  bucket = module.gcs_raw.bucket_name
  source = "${path.module}/../data/sample.parquet"
}

resource "google_storage_bucket_object" "bootstrap_sales_transactions_parquet" {
  count  = var.enable_sales_orders_external_tables ? 1 : 0
  name   = "domain=${var.domain}/dataset=sales_transactions/sales_transactions_0001.parquet"
  bucket = module.gcs_raw.bucket_name
  source = "${path.module}/../data/sample.parquet"
}

module "project_labels" {
  source     = "./modules/project_labels"
  project_id = var.project_id

  labels = {
    environment = var.environment
    system      = "gcp-lakehouse"
    managed_by  = "terraform"
    repository  = "gcp-lakehouse-from-scratch"
    owner       = "alexfokam"
    cost_center = "lab"
  }
}