###############################################################################
# secret_dataform_git_token.tf
#
# But :
# - OPTIONNELLEMENT créer le secret Secret Manager "dataform-git-token"
#   dans le projet courant (var.project_id)
#
# Contexte :
# - En DEV tu as peut-être créé le secret dans le même projet
# - En STAGING/PROD tu veux réutiliser un secret centralisé :
#     projects/518653594867/secrets/dataform-git-token/versions/latest
#
# => Donc on met un flag : var.create_dataform_git_token_secret
#    - false : aucune création dans le projet courant
#    - true  : création du secret dans le projet courant
#
# IMPORTANT :
# - Ce fichier ne crée QUE le "container" secret (metadata).
# - Il ne crée PAS de version avec la valeur du token (c’est voulu).
###############################################################################

resource "google_secret_manager_secret" "dataform_git_token" {
  # ---------------------------------------------------------------------------
  # Activation conditionnelle
  # - count = 0 => ressource absente
  # - count = 1 => ressource créée
  # ---------------------------------------------------------------------------
  count = var.create_dataform_git_token_secret ? 1 : 0

  project   = var.project_id
  secret_id = var.git_token_secret_id # par défaut "dataform-git-token"

  # ---------------------------------------------------------------------------
  # Replication
  # - auto = gestion Google (simple, suffisant pour un lab)
  # ---------------------------------------------------------------------------
  replication {
    auto {}
  }

  # ---------------------------------------------------------------------------
  # Labels : gouvernance
  # ---------------------------------------------------------------------------
  labels = merge(
    var.labels,
    {
      managed_by  = "terraform"
      system      = "gcp-lakehouse"
      environment = var.environment
    }
  )
}