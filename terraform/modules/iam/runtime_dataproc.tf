################################################################################
# runtime_dataproc.tf
# ------------------------------------------------------------------------------
# OBJECTIF
# ------------------------------------------------------------------------------
# Ce fichier gère l'identité runtime utilisée par Dataproc Serverless / Spark
# pour exécuter les jobs data engineering du lakehouse.
#
# Dans notre architecture, Dataproc sert notamment à :
# - lire des fichiers bruts depuis GCS RAW (bronze)
# - transformer / standardiser les données avec Spark
# - écrire des fichiers Parquet propres dans GCS CURATED
# - écrire des tables Iceberg dans le bucket ICEBERG
# - éventuellement lire / écrire via BigQuery (dataset temporaire, curated, etc.)
#
# IMPORTANT
# ------------------------------------------------------------------------------
# Ce service account runtime n'est PAS le même que :
# - le service account GitHub CI/CD (WIF)
# - le futur service account Cloud Composer / Airflow
#
# Séparation des responsabilités :
# - GitHub CI/CD SA  -> déploie l'infrastructure
# - Dataproc Runtime SA -> exécute les jobs Spark
# - Composer SA      -> orchestre plus tard les pipelines
################################################################################

################################################################################
# LOCALS
################################################################################

locals {
  # Active ou non la création des runtimes "lakehouse" côté IAM.
  # Cela permet de désactiver facilement la couche runtime dans certains envs.
  enable_dp = var.enable_lakehouse_runtimes

  # Petit helper pour éviter de répéter la même interpolation partout.
  dataproc_member = local.enable_dp ? "serviceAccount:${google_service_account.dataproc_runtime[0].email}" : null

  dataproc_service_agent_email = "service-${data.google_project.current.number}@dataproc-accounts.iam.gserviceaccount.com"
}

################################################################################
# 1) SERVICE ACCOUNT RUNTIME DATAPROC
# ------------------------------------------------------------------------------
# Ce SA sera explicitement passé dans les commandes :
#
# gcloud dataproc batches submit pyspark ... \
#   --service-account=sa-dataproc-<env>@<project>.iam.gserviceaccount.com
#
# Il ne faut pas s'appuyer sur le Compute Engine default service account,
# car ce n'est pas propre, pas robuste, et pas "enterprise-grade".
################################################################################

resource "google_service_account" "dataproc_runtime" {
  count        = local.enable_dp ? 1 : 0
  project      = var.project_id
  account_id   = "sa-dataproc-${var.environment}"
  display_name = "Dataproc Runtime SA (${var.environment})"
}

################################################################################
# 2) PROJECT-LEVEL ROLES
# ------------------------------------------------------------------------------
# Rôles globaux nécessaires au runtime Dataproc.
################################################################################

# ------------------------------------------------------------------------------
# Rôle clé pour les workers Dataproc
# ------------------------------------------------------------------------------
# C'est ce rôle qui apporte notamment les permissions du type :
# - dataproc.agents.create
# - dataproc.tasks.lease
# - dataproc.tasks.reportStatus
#
# Sans ce rôle, les batches Dataproc Serverless échouent même si le job
# est correctement soumis.
resource "google_project_iam_member" "dataproc_worker" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = local.dataproc_member
}

# ------------------------------------------------------------------------------
# Permet au runtime Dataproc de créer / exécuter des jobs BigQuery
# ------------------------------------------------------------------------------
# Très utile si :
# - Spark lit/écrit BigQuery
# - le BigQuery connector est utilisé
# - des opérations SQL intermédiaires sont réalisées
resource "google_project_iam_member" "dataproc_bq_job_user" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = local.dataproc_member
}

# ------------------------------------------------------------------------------
# Permet d'écrire des logs applicatifs si nécessaire
# ------------------------------------------------------------------------------
# Ce n'est pas toujours strictement indispensable dans tous les contextes,
# mais c'est propre et utile pour les traitements managés.
resource "google_project_iam_member" "dataproc_log_writer" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.dataproc_member
}

# ------------------------------------------------------------------------------
# Permet de publier des métriques si besoin
# ------------------------------------------------------------------------------
# Utile dans les environnements "enterprise" pour observabilité / monitoring.
resource "google_project_iam_member" "dataproc_metric_writer" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = local.dataproc_member
}

################################################################################
# 3) BIGQUERY DATASET IAM
# ------------------------------------------------------------------------------
# Accès minimum aux datasets utilisés par Dataproc.
#
# Philosophie :
# - lecture sur les datasets de type source / raw external
# - écriture sur les datasets techniques / iceberg / tmp
################################################################################

# ------------------------------------------------------------------------------
# Lecture du dataset RAW EXTERNAL
# ------------------------------------------------------------------------------
# Permet à Dataproc de lire des tables externes si on s'appuie sur BigQuery
# comme point d'accès SQL à certaines données brutes.
resource "google_bigquery_dataset_iam_member" "dataproc_rawext_viewer" {
  count      = local.enable_dp ? 1 : 0
  project    = var.project_id
  dataset_id = var.raw_external_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = local.dataproc_member
}

# ------------------------------------------------------------------------------
# Écriture dans le dataset CURATED_ICEBERG
# ------------------------------------------------------------------------------
# Utile si Dataproc / Spark écrit des objets orientés BigQuery / Iceberg.
resource "google_bigquery_dataset_iam_member" "dataproc_iceberg_editor" {
  count      = local.enable_dp ? 1 : 0
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.dataproc_member
}

# ------------------------------------------------------------------------------
# Écriture dans le dataset TMP
# ------------------------------------------------------------------------------
# Très utile pour :
# - matérialisations intermédiaires
# - BigQuery connector
# - écritures techniques temporaires
#
# On ne le crée que si le tmp dataset est activé.
resource "google_bigquery_dataset_iam_member" "dataproc_tmp_dataset_editor" {
  count      = (local.enable_dp && var.enable_tmp_dataset) ? 1 : 0
  project    = var.project_id
  dataset_id = var.tmp_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.dataproc_member
}

################################################################################
# 4) GCS BUCKET IAM
# ------------------------------------------------------------------------------
# Accès GCS nécessaires au runtime Dataproc.
#
# Logique médallion rappel :
# - RAW      = lecture source / bronze
# - CURATED  = écriture des données préparées / standardisées
# - ICEBERG  = écriture des tables lakehouse ouvertes
# - TEMP     = staging technique Spark / Dataproc
# - SCRIPTS  = lecture des scripts de jobs
################################################################################

# ------------------------------------------------------------------------------
# RAW bucket : lecture des données brutes
# ------------------------------------------------------------------------------
# Dataproc doit pouvoir lire les fichiers source déposés dans la zone bronze.
resource "google_storage_bucket_iam_member" "dataproc_raw_object_viewer" {
  count  = local.enable_dp ? 1 : 0
  bucket = var.raw_bucket_name
  role   = "roles/storage.objectViewer"
  member = local.dataproc_member
}

# ------------------------------------------------------------------------------
# CURATED bucket : écriture des données préparées
# ------------------------------------------------------------------------------
# Ici Spark écrit généralement du Parquet propre, prêt à être exposé à BigQuery.
resource "google_storage_bucket_iam_member" "dataproc_curated_object_admin" {
  count  = local.enable_dp ? 1 : 0
  bucket = var.curated_bucket_name
  role   = "roles/storage.objectAdmin"
  member = local.dataproc_member
}

# ------------------------------------------------------------------------------
# ICEBERG bucket : écriture des tables Iceberg
# ------------------------------------------------------------------------------
# Rôle central pour les futurs pipelines Spark + Iceberg.
resource "google_storage_bucket_iam_member" "dataproc_iceberg_object_admin" {
  count  = local.enable_dp ? 1 : 0
  bucket = var.iceberg_bucket_name
  role   = "roles/storage.objectAdmin"
  member = local.dataproc_member
}

# ------------------------------------------------------------------------------
# DATAPROC TEMP bucket : staging technique Dataproc / Spark
# ------------------------------------------------------------------------------
# Utilisé pour :
# - dépendances
# - fichiers temporaires
# - étapes intermédiaires du runtime
resource "google_storage_bucket_iam_member" "dataproc_temp_object_admin" {
  count  = local.enable_dp ? 1 : 0
  bucket = var.dataproc_temp_bucket_name
  role   = "roles/storage.objectAdmin"
  member = local.dataproc_member
}

# ------------------------------------------------------------------------------
# SCRIPTS bucket : lecture des scripts Spark
# ------------------------------------------------------------------------------
# Le job pyspark est généralement stocké dans un bucket scripts.
# Dataproc n'a pas besoin d'écrire dedans, seulement de lire.
resource "google_storage_bucket_iam_member" "dataproc_scripts_object_viewer" {
  count  = local.enable_dp ? 1 : 0
  bucket = var.scripts_bucket_name
  role   = "roles/storage.objectViewer"
  member = local.dataproc_member
}
################################################################################
# DATAPROC -> ARTIFACT REGISTRY READER
# ------------------------------------------------------------------------------
# OBJECTIF
# Permettre :
# 1. au service account runtime Dataproc (sa-dataproc-<env>)
# 2. au Dataproc Service Agent Google-managed
# de tirer l'image custom depuis Artifact Registry.
#
# POURQUOI LES DEUX ?
# - le runtime SA couvre l'exécution workload
# - le Dataproc Service Agent couvre les opérations control plane
#   et c'est le candidat le plus probable pour le pull du conteneur custom
################################################################################



resource "google_project_iam_member" "dataproc_runtime_artifactregistry_reader" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}

resource "google_project_iam_member" "dataproc_service_agent_artifactregistry_reader" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.dataproc_service_agent_email}"
}

