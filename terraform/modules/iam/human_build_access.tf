################################################################################
# IAM - HUMAN BUILD ACCESS
# ------------------------------------------------------------------------------
# OBJECTIF
# Donner à l'utilisateur humain certains droits de build local :
# - Cloud Build
# - Artifact Registry
#
# NOTE
# On sécurise les variables optionnelles avec try(..., "")
################################################################################

locals {
  # Email humain normalisé
  # - null -> ""
  # - espaces supprimés
  human_user_email_effective = try(trimspace(var.human_user_email), "")

  # Activation réelle seulement si :
  # - le flag est activé
  # - ET un email utilisateur est bien fourni
  enable_human_build_access_effective = (
    var.enable_human_build_access &&
    local.human_user_email_effective != ""
  )

  # Member IAM utilisateur
  human_user_member = local.enable_human_build_access_effective ? "user:${local.human_user_email_effective}" : null
}

resource "google_project_iam_member" "human_cloudbuild_editor" {
  count   = local.enable_human_build_access_effective ? 1 : 0
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = local.human_user_member
}

resource "google_project_iam_member" "human_serviceusage_consumer" {
  count   = local.enable_human_build_access_effective ? 1 : 0
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = local.human_user_member
}

resource "google_project_iam_member" "human_artifactregistry_writer" {
  count   = local.enable_human_build_access_effective ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = local.human_user_member
}
