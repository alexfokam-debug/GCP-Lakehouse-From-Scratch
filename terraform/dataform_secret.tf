############################################################
# Dataform Git Token (ENTERPRISE)
#
# Pourquoi ?
# - Dataform doit pouvoir "pull" ton repo Git (GitHub/GitLab)
# - Le token Git est une donnée SENSIBLE -> Secret Manager
# - En entreprise :
#   ✅ Le secret est stocké dans Secret Manager
#   ✅ Terraform gère UNIQUEMENT les droits IAM sur ce secret
#   ❌ Terraform NE DOIT PAS stocker le token dans son state
#
# Bonus:
# - On utilise un "iam_binding" AUTHORITATIVE pour ÉCRASER
#   les membres existants (et donc enlever les "deleted:...")
############################################################

#############################
# 1) Récupère le project number (utile pour le service agent Dataform)
#############################
data "google_project" "current" {
  project_id = var.project_id
}

#############################
# 2) Référence le secret existant
#
# IMPORTANT :
# - Le secret existe déjà chez toi: "dataform-git-token"
# - Donc on le lit en data source (pas besoin d'import)
#############################
data "google_secret_manager_secret" "dataform_git_token" {
  project   = var.project_id
  secret_id = var.dataform_git_token_secret_id
}

#############################
# 3) IAM "authoritative" sur le secret
#
# On force la liste EXACTE des membres autorisés.
# Résultat :
# - Les entrées "deleted:serviceAccount:..." disparaissent
# - Dataform peut lire le token sans erreur "Unable to fetch Git token secret"
#
# Qui doit lire le secret ?
# A) Dataform SERVICE AGENT (OBLIGATOIRE)
#    service-${PROJECT_NUMBER}@gcp-sa-dataform.iam.gserviceaccount.com
#
# B) (Optionnel mais OK) ton SA Dataform runtime (celui que tu as créé)
#    sa-dataform-dev@... (ou staging/prod)
#############################
resource "google_secret_manager_secret_iam_binding" "dataform_git_token_access" {
  project   = var.project_id
  secret_id = data.google_secret_manager_secret.dataform_git_token.secret_id

  role = "roles/secretmanager.secretAccessor"

  members = [
    # (A) Dataform service agent - le principal attendu par l'API Dataform
    "serviceAccount:service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com",

    # (B) Ton service account Dataform (pratique pour debug/tests/outillage)
    "serviceAccount:${var.dataform_sa_email}",
  ]
}

