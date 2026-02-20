###############################################################################
# main.tf – Module Dataform
# Objectif :
# 1) Créer le repository Dataform (déjà fait)
# 2) Créer une Release Config (paramètres de compilation standard)
# 3) Créer un Workflow Config (schedule prod-like lun-ven 06:00)
###############################################################################

# -----------------------------------------------------------------------------
# 1) Repository Dataform (déjà OK chez toi)
# -----------------------------------------------------------------------------
resource "google_dataform_repository" "this" {
  provider = google-beta

  project = var.project_id
  region  = var.region

  name         = var.repo_name
  display_name = var.repo_display_name

  git_remote_settings {
    url                                 = var.git_repo_url
    default_branch                      = var.git_default_branch
    authentication_token_secret_version = var.git_token_secret_version
  }

  labels = var.labels
}

# =============================================================================
# Dataform Release Config
# =============================================================================
# Objectif :
# - Définir comment Dataform compile le repo (branche, variables, etc.)
# - Sert de base aux workflows planifiés
# =============================================================================

resource "google_dataform_repository_release_config" "prod_release" {

  # ---------------------------------------------------------------------------
  # Dataform resources => souvent via provider google-beta
  # ---------------------------------------------------------------------------
  provider = google-beta

  # ---------------------------------------------------------------------------
  # Contexte projet / région
  # ---------------------------------------------------------------------------
  project = var.project_id
  region  = var.region

  # ---------------------------------------------------------------------------
  # Repository Dataform cible
  # ---------------------------------------------------------------------------
  repository = google_dataform_repository.this.name

  # ---------------------------------------------------------------------------
  # Nom technique du release config
  # ---------------------------------------------------------------------------
  name = "release-prod"

  # ---------------------------------------------------------------------------
  # Git commit-ish : la branche ou tag utilisé pour compiler
  # (main en prod)
  # ---------------------------------------------------------------------------
  git_commitish = var.git_default_branch

  # ---------------------------------------------------------------------------
  # Variables de compilation (Dataform)
  # Ici on passe l'env, utile dans dataform.json / includes
  # ---------------------------------------------------------------------------
  code_compilation_config {
    default_database = var.project_id
    default_schema   = "analytics_${var.environment}"

    # Variables custom utilisables dans Dataform (ex: includes/constants.js)
    vars = {
      env = var.environment
    }
  }
}
# =============================================================================
# Dataform Workflow Config (schedule)
# =============================================================================
# Objectif :
# - Planifier l'exécution automatique
# - Lun → Ven en prod (pas le week-end)
# - Exécuter seulement certains tags (ex: "prod")
# =============================================================================

resource "google_dataform_repository_workflow_config" "prod_weekdays" {
  provider = google-beta

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.this.name

  # Nom technique
  name = "wf-prod-weekdays"

  # On attache le release config
  release_config = google_dataform_repository_release_config.prod_release.id

  # CRON : tous les jours ouvrés (lun=1 ... ven=5)
  # Exemple : 06:00 Europe/Paris
  cron_schedule = "0 6 * * 1-5"

  # Timezone (si supportée par le provider / API)
  # Si ton provider ne supporte pas ce champ, on le retire.
  time_zone = "Europe/Paris"

  # Exécuter uniquement des tags (mode entreprise)
  invocation_config {
    included_tags   = ["prod"]
    service_account = var.dataform_sa_email
  }
}

##############################################
# Dataform Repository (Enterprise)
#
# Objectif:
# - Créer un repo Dataform dans GCP
# - Optionnel: connecter ce repo à un repo Git (GitHub/GitLab)
# - Le token Git est stocké dans Secret Manager:
#   ✅ TF référence la version "latest"
#   ❌ TF ne stocke jamais le token dans le state
##############################################

# On référence la version "latest" du secret, sans lire le contenu.
# => Cette data source ne sort pas le token, elle renvoie un "resource name".
data "google_secret_manager_secret_version" "git_token_latest" {
  project = var.project_id
  secret  = var.git_token_secret_id
  version = "latest"
}

