################################################################################
# IAM - CLOUD BUILD RUNTIME SERVICE ACCOUNT
# ------------------------------------------------------------------------------
# OBJECTIF
# Donner au service account utilisé par Cloud Build les droits minimums pour :
# - lire l'archive source stockée dans le bucket Cloud Build
# - pousser l'image Docker dans Artifact Registry
#
# NOTE
# Le compte de service exact est celui vu dans l'erreur :
#   518653594867-compute@developer.gserviceaccount.com
################################################################################

locals {
  enable_cloud_build_runtime_access_effective = (
    var.enable_cloud_build_runtime_access &&
    var.cloud_build_service_account_email != null &&
    trimspace(var.cloud_build_service_account_email) != ""
  )

  cloud_build_runtime_member = local.enable_cloud_build_runtime_access_effective ? "serviceAccount:${trimspace(var.cloud_build_service_account_email)}" : null
}

resource "google_project_iam_member" "cloud_build_artifactregistry_writer" {
  count   = local.enable_cloud_build_runtime_access_effective ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = local.cloud_build_runtime_member
}

resource "google_storage_bucket_iam_member" "cloud_build_source_bucket_viewer" {
  count  = local.enable_cloud_build_runtime_access_effective ? 1 : 0
  bucket = "${var.project_id}_cloudbuild"
  role   = "roles/storage.objectViewer"
  member = local.cloud_build_runtime_member
}