# ============================================================
# Service Account - Dataform
# ============================================================
resource "google_service_account" "dataform" {
  project      = var.project_id
  account_id   = "sa-dataform-${var.environment}"
  display_name = "Dataform Service Account (${var.environment})"
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