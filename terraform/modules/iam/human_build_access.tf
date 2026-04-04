################################################################################
# IAM - ACCÈS UTILISATEUR HUMAIN POUR BUILD LOCAL
# ------------------------------------------------------------------------------
# OBJECTIF
# Accorder explicitement à un utilisateur humain les rôles minimums nécessaires
# pour :
# - lancer gcloud builds submit
# - utiliser les services du projet pendant le build
# - pousser une image dans Artifact Registry
#
# POURQUOI LE FAIRE ?
# - rendre l'accès reproductible
# - éviter les ambiguïtés liées aux héritages IAM d'organisation
# - permettre le debug local proprement
#
# ACTIVATION
# Ce bloc n'est créé que si :
# - enable_human_build_access = true
# - human_user_email != null
################################################################################

################################################################################
# LOCALS - HUMAN BUILD ACCESS
# ------------------------------------------------------------------------------
# trimspace() enlève les espaces en début/fin de chaîne.
# On l'utilise pour éviter les cas où l'email serait renseigné avec des espaces.
################################################################################

locals {
  enable_human_build_access_effective = (
    var.enable_human_build_access &&
    var.human_user_email != null &&
    trimspace(var.human_user_email) != ""
  )

  human_user_member = local.enable_human_build_access_effective ? "user:${trimspace(var.human_user_email)}" : null
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
