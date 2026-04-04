################################################################################
# IAM - CLOUD BUILD RUNTIME SERVICE ACCOUNT
# ------------------------------------------------------------------------------
# OBJECTIF
# Donner au service account utilisé par Cloud Build les droits minimums pour :
# - lire l'archive source stockée dans le bucket Cloud Build
# - pousser l'image Docker dans Artifact Registry
#
# POURQUOI try() ET PAS coalesce() ?
# ------------------------------------------------------------------------------
# - coalesce(null, "") échoue en Terraform car "" est aussi rejeté
# - try(trimspace(...), "") est plus robuste :
#   si la variable est null, Terraform retourne simplement ""
################################################################################

locals {
  # Email normalisé du service account Cloud Build
  # - si null -> ""
  # - si rempli avec espaces -> trim propre
  cloud_build_service_account_email_effective = try(trimspace(var.cloud_build_service_account_email), "")

  # Active réellement la gestion Cloud Build seulement si :
  # - le flag est à true
  # - ET un email exploitable est fourni
  enable_cloud_build_runtime_access_effective = (
    var.enable_cloud_build_runtime_access &&
    local.cloud_build_service_account_email_effective != ""
  )

  # Member IAM calculé dynamiquement
  cloud_build_runtime_member = local.enable_cloud_build_runtime_access_effective ? "serviceAccount:${local.cloud_build_service_account_email_effective}" : null
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