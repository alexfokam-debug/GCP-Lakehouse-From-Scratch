###############################################################################
# main.tf — Module IAM (OPTION 1 = SA Dataproc unique géré par Terraform)
# -----------------------------------------------------------------------------
# Objectif :
# - Créer les SA runtime (Dataform / Dataproc)
# - Appliquer IAM projet, IAM dataset, IAM bucket
# - Laisser GitHub WIF séparé dans github_wif.tf (propre)
#
# Principe Option 1 (IMPORTANT) :
# - On ne dépend PAS d'un SA Dataproc passé en variable.
# - On utilise UNE SEULE identité Dataproc : google_service_account.dataproc_runtime
###############################################################################

# =============================================================================
# 0) Infos projet : pour récupérer le PROJECT NUMBER
# -----------------------------------------------------------------------------
# Utilité :
# - Construire l’email du Dataform Service Agent :
#   service-${PROJECT_NUMBER}@gcp-sa-dataform.iam.gserviceaccount.com
# =============================================================================
data "google_project" "current" {
  project_id = var.project_id
}

# =============================================================================
# 1) Service Account — Dataform runtime
# -----------------------------------------------------------------------------
# Ce SA exécute les jobs Dataform (workflow invocation_config.service_account).
# On lui donne :
# - roles/bigquery.user + roles/bigquery.jobUser (niveau projet)
# - droits dataset-level (curated read, analytics write, etc.)
# - droits GCS (lecture raw)
# =============================================================================
resource "google_service_account" "dataform" {
  project      = var.project_id
  account_id   = "sa-dataform-${var.environment}"
  display_name = "Dataform Service Account (${var.environment})"
}

# -- BigQuery user : requis pour exécuter certains appels BQ / jobs
resource "google_project_iam_member" "dataform_bq_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.dataform.email}"
}

# -- BigQuery jobUser : requis pour lancer des jobs de requêtes
resource "google_project_iam_member" "dataform_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataform.email}"
}

# -----------------------------------------------------------------------------
# Dataset Curated : lecture
# -----------------------------------------------------------------------------
resource "google_bigquery_dataset_iam_member" "curated_reader" {
  project    = var.project_id
  dataset_id = var.curated_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# -----------------------------------------------------------------------------
# Dataset Analytics : écriture
# -----------------------------------------------------------------------------
resource "google_bigquery_dataset_iam_member" "analytics_editor" {
  project    = var.project_id
  dataset_id = var.analytics_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# -----------------------------------------------------------------------------
# Dataset RAW external : lecture (souvent nécessaire)
# -----------------------------------------------------------------------------
resource "google_bigquery_dataset_iam_member" "rawext_reader" {
  project    = var.project_id
  dataset_id = var.raw_external_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# -----------------------------------------------------------------------------
# Dataset Curated Iceberg : écriture (tables/vues)
# -----------------------------------------------------------------------------
resource "google_bigquery_dataset_iam_member" "curated_iceberg_editor" {
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# -----------------------------------------------------------------------------
# Bucket RAW : lecture objets (external tables / fichiers sources)
# -----------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "dataform_raw_viewer" {
  bucket = var.raw_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataform.email}"
}

# =============================================================================
# 2) Dataform Service Agent (Google-managed) : permissions projet + actAs
# -----------------------------------------------------------------------------
# Dataform a un “service agent” géré par Google :
#   service-${PROJECT_NUMBER}@gcp-sa-dataform.iam.gserviceaccount.com
#
# Il doit pouvoir :
# - lancer des jobs BQ (jobUser)
# - être bigquery.user
# - impersonate TON SA runtime (sa-dataform-*) via actAs :
#     - roles/iam.serviceAccountTokenCreator
#     - roles/iam.serviceAccountUser
# =============================================================================

# -- BigQuery jobUser (service agent Dataform)
resource "google_project_iam_member" "dataform_service_agent_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# -- BigQuery user (service agent Dataform)
resource "google_project_iam_member" "dataform_service_agent_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# -- TokenCreator ON Dataform runtime SA (impersonation)
resource "google_service_account_iam_member" "dataform_service_agent_token_creator_on_dataform_sa" {
  service_account_id = google_service_account.dataform.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# -- ServiceAccountUser ON Dataform runtime SA (actAs)
resource "google_service_account_iam_member" "dataform_service_agent_user_on_dataform_sa" {
  service_account_id = google_service_account.dataform.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# =============================================================================
# 3) Service Account — Dataproc runtime (OPTION 1 = unique + géré ici)
# -----------------------------------------------------------------------------
# Ce SA exécute Dataproc Serverless (Spark).
# On lui donne :
# - roles/dataproc.worker (exécution)
# - roles/bigquery.jobUser + readSessionUser (connector BQ)
# - accès datasets + buckets nécessaires
# =============================================================================
resource "google_service_account" "dataproc_runtime" {
  project      = var.project_id
  account_id   = "sa-dataproc-${var.environment}"
  display_name = "Dataproc Serverless runtime SA (${var.environment})"
}

# -- Autorise l’exécution Dataproc
resource "google_project_iam_member" "dataproc_worker" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

# -- Autorise jobs BigQuery (Spark BigQuery connector)
resource "google_project_iam_member" "dataproc_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

# -- Autorise BigQuery Storage API (Read sessions)
resource "google_project_iam_binding" "dataproc_bq_read_session_user" {
  project = var.project_id
  role    = "roles/bigquery.readSessionUser"

  members = [
    "serviceAccount:${google_service_account.dataproc_runtime.email}",
  ]
}

# -- Lecture RAW external dataset (si Spark lit depuis raw_ext_*)
resource "google_bigquery_dataset_iam_member" "dataproc_rawext_viewer" {
  project    = var.project_id
  dataset_id = var.raw_external_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

# -- Écriture dans curated_iceberg dataset (si Spark écrit dans BQ)
resource "google_bigquery_dataset_iam_member" "dataproc_iceberg_editor" {
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

# -- Droits sur bucket ICEBERG (si Spark écrit des fichiers sur GCS)
resource "google_storage_bucket_iam_member" "dataproc_iceberg_object_admin" {
  bucket = var.iceberg_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

# -- Droits sur bucket TEMP Dataproc (staging / connector)
resource "google_storage_bucket_iam_member" "dataproc_temp_object_admin" {
  bucket = var.dataproc_temp_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

# -- Dataset TMP (optionnel, piloté par flag)
resource "google_bigquery_dataset_iam_member" "dataproc_tmp_dataset_editor" {
  count      = var.enable_tmp_dataset ? 1 : 0
  project    = var.project_id
  dataset_id = var.tmp_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

# =============================================================================
# 4) Dataset ENTERPRISE : écriture Dataform (si nécessaire)
# -----------------------------------------------------------------------------
# Si Dataform doit écrire dans enterprise_${env}.
# =============================================================================
resource "google_bigquery_dataset_iam_member" "enterprise_editor_dataform" {
  project    = var.project_id
  dataset_id = "enterprise_${var.environment}"
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# -----------------------------------------------------------------------------
# (Optionnel) Petit sleep si propagation IAM/dataset te fait des misères
# -----------------------------------------------------------------------------
resource "time_sleep" "wait_enterprise_dataset" {
  depends_on      = [google_bigquery_dataset_iam_member.analytics_editor]
  create_duration = "10s"
}

# =============================================================================
# 5) GitHub CI/CD (WIF) : backend state + secret manager (si bootstrap_ci_iam = true)
# -----------------------------------------------------------------------------
# IMPORTANT :
# - Le SA GitHub CI/CD est créé dans github_wif.tf :
#     google_service_account.github_cicd
# - Donc ici on ne le recrée pas ; on applique juste des IAM sur bucket/secret.
# =============================================================================

# -- (A) Accès R/W aux objets du bucket backend Terraform
resource "google_storage_bucket_iam_member" "github_tf_backend_object_admin" {
  count  = var.bootstrap_ci_iam ? 1 : 0
  bucket = var.tf_state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_cicd.email}"
}

# -- (B) Lecture metadata bucket (souvent utile pour init)
resource "google_storage_bucket_iam_member" "github_tf_backend_bucket_reader" {
  count  = var.bootstrap_ci_iam ? 1 : 0
  bucket = var.tf_state_bucket_name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.github_cicd.email}"
}

# -- (C) Lecture Secret Manager (Dataform Git token) par GitHub CI/CD
resource "google_secret_manager_secret_iam_member" "github_cicd_can_read_dataform_git_token" {
  count     = var.bootstrap_ci_iam ? 1 : 0
  project   = var.project_id
  secret_id = var.git_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.github_cicd.email}"
}

###############################################################################
# GitHub CI/CD Service Account – Project Level Roles (Least Privilege)
# Objectif :
# - Permettre à Terraform exécuté depuis GitHub Actions
#   de gérer uniquement les services nécessaires
# - Sans donner roles/editor global
###############################################################################

# BigQuery administration (datasets, tables, connections)
resource "google_project_iam_member" "github_cicd_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# GCS administration (buckets managed by Terraform)
resource "google_project_iam_member" "github_cicd_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# IAM administration (required because Terraform manages IAM bindings)
resource "google_project_iam_member" "github_cicd_iam_admin" {
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# Service Account User (required for binding IAM on SAs)
resource "google_project_iam_member" "github_cicd_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# Dataform admin (repository + workflow configs)
resource "google_project_iam_member" "github_cicd_dataform_admin" {
  project = var.project_id
  role    = "roles/dataform.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# Dataplex admin (lakes/zones/assets)
resource "google_project_iam_member" "github_cicd_dataplex_admin" {
  project = var.project_id
  role    = "roles/dataplex.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# Secret Manager admin (Terraform gère IAM sur secrets)
resource "google_project_iam_member" "github_cicd_secret_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}
resource "google_project_iam_member" "github_cicd_wif_pool_admin" {
  count   = var.enable_github_cicd_wif_pool_admin ? 1 : 0
  project = var.project_id
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}