locals {
  enable_dp = var.enable_lakehouse_runtimes
}

resource "google_service_account" "dataproc_runtime" {
  count        = local.enable_dp ? 1 : 0
  project      = var.project_id
  account_id   = "sa-dataproc-${var.environment}"
  display_name = "Dataproc Runtime SA (${var.environment})"
}

# Project-level roles
resource "google_project_iam_member" "dataproc_worker" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}

resource "google_project_iam_member" "dataproc_bq_job_user" {
  count   = local.enable_dp ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}

# Dataset IAM (seulement si enable_dp)
resource "google_bigquery_dataset_iam_member" "dataproc_rawext_viewer" {
  count      = local.enable_dp ? 1 : 0
  project    = var.project_id
  dataset_id = var.raw_external_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataproc_iceberg_editor" {
  count      = local.enable_dp ? 1 : 0
  project    = var.project_id
  dataset_id = var.curated_iceberg_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}

resource "google_bigquery_dataset_iam_member" "dataproc_tmp_dataset_editor" {
  count      = (local.enable_dp && var.enable_tmp_dataset) ? 1 : 0
  project    = var.project_id
  dataset_id = var.tmp_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}

# Bucket IAM
resource "google_storage_bucket_iam_member" "dataproc_iceberg_object_admin" {
  count  = local.enable_dp ? 1 : 0
  bucket = var.iceberg_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}

resource "google_storage_bucket_iam_member" "dataproc_temp_object_admin" {
  count  = local.enable_dp ? 1 : 0
  bucket = var.dataproc_temp_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc_runtime[0].email}"
}