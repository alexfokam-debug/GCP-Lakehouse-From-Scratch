# ============================================================
# Service Account - Dataform
# ============================================================
resource "google_service_account" "dataform" {
  project      = var.project_id
  account_id   = "sa-dataform-${var.environment}"
  display_name = "Dataform Service Account (${var.environment})"
}
resource "google_project_iam_member" "dataform_bq_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.dataform.email}"
}
# ============================================================
# IAM projet
# ============================================================
resource "google_project_iam_member" "dataform_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataform.email}"
}

# ============================================================
# IAM datasets
# ============================================================

# Lecture CURATED
resource "google_bigquery_dataset_iam_member" "curated_reader" {
  project    = var.project_id
  dataset_id = var.curated_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# Écriture ANALYTICS
resource "google_bigquery_dataset_iam_member" "analytics_editor" {
  project    = var.project_id
  dataset_id = var.analytics_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# (Optionnel) Lecture RAW external
resource "google_bigquery_dataset_iam_member" "rawext_reader" {
  project    = var.project_id
  dataset_id = var.raw_external_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform.email}"
}

# =============================================================================
# Dataform SA -> écriture dataset Iceberg
# =============================================================================
# Permet à Dataform de créer / modifier des tables Iceberg
# =============================================================================

resource "google_bigquery_dataset_iam_member" "curated_iceberg_editor" {

  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id

  # Dataform doit pouvoir créer tables / vues
  role = "roles/bigquery.dataEditor"

  member = google_service_account.dataform.member
}

# -----------------------------------------------------------------------------
# Service Account dédié Dataproc Serverless (runtime)
# -----------------------------------------------------------------------------
resource "google_service_account" "dataproc_runtime" {
  account_id   = "sa-dataproc-${var.environment}"
  display_name = "Dataproc Serverless runtime SA (${var.environment})"
  project      = var.project_id
}

# -----------------------------------------------------------------------------
# Autorisations minimales (ajuste si besoin)
# - Dataproc Worker : exécuter les jobs serverless
# - BigQuery : écrire dans curated_iceberg (si tu écris vers BQ) OU requêter (si tu lis)
# - Storage : lire/écrire sur bucket iceberg
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "dataproc_worker" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

resource "google_project_iam_member" "bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

resource "google_bigquery_dataset_iam_member" "iceberg_editor" {
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}

resource "google_storage_bucket_iam_member" "iceberg_object_admin" {
  bucket = var.iceberg_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}
# ============================================================================
# BigQuery IAM - Dataproc runtime SA
# Objectif :
# - Autoriser Dataproc Serverless (SA runtime) à LIRE le dataset RAW external
# - Nécessaire pour que le Spark BigQuery connector puisse faire:
#     - bigquery.tables.get
#     - bigquery.tables.getData
# ============================================================================
resource "google_bigquery_dataset_iam_member" "rawext_viewer_dataproc" {
  project = var.project_id

  # Dataset RAW external (ex: raw_ext_dev)
  dataset_id = var.raw_external_dataset_id

  # Rôle de lecture dataset BigQuery
  role = "roles/bigquery.dataViewer"

  # Service Account runtime Dataproc
  member = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}
# Autorise la création de read sessions (utilisé par le connector BigQuery)
resource "google_project_iam_member" "bq_read_session_user" {
  project = var.project_id
  role    = "roles/bigquery.readSessionUser"
  member  = "serviceAccount:${google_service_account.dataproc_runtime.email}"
}


resource "google_project_iam_member" "dataproc_sa_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.dataproc_sa_email}"
}
resource "google_storage_bucket_iam_member" "dataproc_temp_object_admin" {
  bucket = var.dataproc_temp_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.dataproc_sa_email}"
}
# =====================================================================
# IAM TMP dataset : Dataproc SA = BigQuery Data Editor (OPTIONNEL)
# =====================================================================
# Pourquoi ?
# - Dataproc (serverless ou cluster) peut avoir besoin d'écrire dans un
#   dataset temporaire pour matérialiser / staging / connecteurs BQ.
#
# Pourquoi piloté par un flag ?
# - Certains environnements n'en ont pas besoin.
# - En entreprise, on veut pouvoir désactiver sans casser le reste.
#
# Pourquoi on utilise var.tmp_dataset_id ?
# - Le module IAM ne doit pas dépendre directement d'une ressource BQ locale
#   (sinon tu crées des couplages et des bugs avec count/index).
# - Le dataset_id doit venir du module BigQuery (output) ou du root.
# =====================================================================
resource "google_bigquery_dataset_iam_member" "tmp_lakehouse_dev_editor" {
  count = var.enable_tmp_dataset ? 1 : 0

  project    = var.project_id
  dataset_id = var.tmp_dataset_id

  role   = "roles/bigquery.dataEditor"
  member = "serviceAccount:${var.dataproc_sa_email}"
}

# ==========================================================
# IAM - BigQuery RAW EXTERNAL dataset reader
# ==========================================================
# Objectif :
# Donner au service account Dataproc l'accès en lecture
# au dataset raw_ext_<environment>
#
# Convention entreprise :
#   raw_ext_dev
#   raw_ext_staging
#   raw_ext_prod
#
# On NE HARDCODE JAMAIS "dev"
# ==========================================================

resource "google_bigquery_dataset_iam_member" "raw_ext_reader" {

  # Dataset dynamique basé sur l'environnement
  dataset_id = "raw_ext_${var.environment}"

  project = var.project_id

  # Service Account Dataproc runtime
  member = "serviceAccount:sa-dataproc-${var.environment}@${var.project_id}.iam.gserviceaccount.com"

  role = "roles/bigquery.dataViewer"
}
###############################################################################
# Dataform Service Agent - BigQuery Permissions
###############################################################################

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_iam_member" "dataform_service_agent_jobuser" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "dataform_service_agent_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# Dataform service agent must impersonate runtime SA
resource "google_service_account_iam_member" "dataform_agent_actas_runtime_sa" {
  service_account_id = google_service_account.dataform.name

  role = "roles/iam.serviceAccountTokenCreator"

  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}
# Dataform service agent must be able to impersonate the runtime SA (actAs)
resource "google_service_account_iam_member" "dataform_service_agent_actas_runtime" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.dataform_sa_email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${var.project_number}@gcp-sa-dataform.iam.gserviceaccount.com"
}
# Dataform Service Agent (service-PROJECT_NUMBER) doit pouvoir "actAs" le runtime SA
resource "google_service_account_iam_member" "dataform_service_agent_actas_runtime_user" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.dataform_sa_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${var.project_number}@gcp-sa-dataform.iam.gserviceaccount.com"
}
resource "google_storage_bucket_iam_member" "dataform_raw_viewer" {
  bucket = var.raw_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.dataform_sa_email}"
}