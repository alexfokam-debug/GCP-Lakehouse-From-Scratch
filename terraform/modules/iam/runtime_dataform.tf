###############################################################################
# runtime_dataform.tf — IAM runtimes Dataform (uniquement si lakehouse activé)
# -----------------------------------------------------------------------------
# Objectif :
# - Créer le Service Account runtime Dataform
# - Donner les permissions BigQuery/GCS nécessaires
# - Donner au Dataform Service Agent la capacité d'impersonate le SA runtime
#
# IMPORTANT :
# - Le data.google_project.current EXISTE DÉJÀ dans modules/iam/main.tf
#   => on le réutilise ici (PAS de doublon).
###############################################################################

# =============================================================================
# 1) Service Account — Dataform runtime
# =============================================================================
resource "google_service_account" "dataform" {
  # OFF en foundation / ON en lakehouse
  count = var.enable_lakehouse_runtimes ? 1 : 0

  project      = var.project_id
  account_id   = "sa-dataform-${var.environment}"
  display_name = "Dataform Service Account (${var.environment})"
}

# =============================================================================
# 2) IAM projet — BigQuery user / jobUser pour le SA runtime Dataform
# =============================================================================
resource "google_project_iam_member" "dataform_bq_user" {
  count   = var.enable_lakehouse_runtimes ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.dataform[0].email}"
}

resource "google_project_iam_member" "dataform_jobuser" {
  count   = var.enable_lakehouse_runtimes ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataform[0].email}"
}

# =============================================================================
# 3) IAM datasets — Dataform runtime
# =============================================================================
resource "google_bigquery_dataset_iam_member" "curated_reader" {
  count      = var.enable_lakehouse_runtimes ? 1 : 0
  project    = var.project_id
  dataset_id = var.curated_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform[0].email}"
}

resource "google_bigquery_dataset_iam_member" "analytics_editor" {
  count      = var.enable_lakehouse_runtimes ? 1 : 0
  project    = var.project_id
  dataset_id = var.analytics_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform[0].email}"
}

resource "google_bigquery_dataset_iam_member" "rawext_reader" {
  count      = var.enable_lakehouse_runtimes ? 1 : 0
  project    = var.project_id
  dataset_id = var.raw_external_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataform[0].email}"
}

resource "google_bigquery_dataset_iam_member" "curated_iceberg_editor" {
  count      = var.enable_lakehouse_runtimes ? 1 : 0
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform[0].email}"
}

# Enterprise dataset : optionnel => ON seulement si ID non vide
resource "google_bigquery_dataset_iam_member" "enterprise_editor_dataform" {
  count = (var.enable_lakehouse_runtimes && var.enterprise_dataset_id != "") ? 1 : 0

  project    = var.project_id
  dataset_id = var.enterprise_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataform[0].email}"
}

# =============================================================================
# 4) IAM bucket RAW — Dataform runtime doit lire les objets
# =============================================================================
resource "google_storage_bucket_iam_member" "dataform_raw_viewer" {
  count  = var.enable_lakehouse_runtimes ? 1 : 0
  bucket = var.raw_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataform[0].email}"
}

# =============================================================================
# 5) Dataform Service Agent (Google-managed) : permissions + actAs
# -----------------------------------------------------------------------------
# Email :
#   service-${PROJECT_NUMBER}@gcp-sa-dataform.iam.gserviceaccount.com
#
# On réutilise data.google_project.current.number déclaré dans main.tf
# =============================================================================
resource "google_project_iam_member" "dataform_service_agent_jobuser" {
  count   = var.enable_lakehouse_runtimes ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "dataform_service_agent_user" {
  count   = var.enable_lakehouse_runtimes ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "dataform_service_agent_token_creator_on_dataform_sa" {
  count              = var.enable_lakehouse_runtimes ? 1 : 0
  service_account_id = google_service_account.dataform[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "dataform_service_agent_user_on_dataform_sa" {
  count              = var.enable_lakehouse_runtimes ? 1 : 0
  service_account_id = google_service_account.dataform[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

