###############################################################################
# modules/dataform/main.tf — Module Dataform (Enterprise-ready)
#
# Objectifs :
# 1) Créer le repository Dataform
# 2) Créer une Release Config (compilation / defaults / vars)
# 3) Créer un Workflow PROD planifié (cron)
# 4) Créer un Workflow DEV on-demand
#
# Sécurité / Git :
# - Le token Git est dans Secret Manager (central security project possible)
# - Terraform NE LIT JAMAIS le secret
# - On référence uniquement "projects/.../secrets/.../versions/..."
# - Donc : aucun token en clair dans state / logs / plan
###############################################################################

###############################################################################
# 0) LOCALS — Normalisation + garde-fou Git
#
# Pourquoi ?
# - éviter les null/"" qui font exploser les tests
# - éviter la suppression accidentelle du bloc git_remote_settings
#   quand une variable est vide / non passée
###############################################################################

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  git_repo_url_norm = trimspace(var.dataform_git_repo_url)

  # si tu fournis directement la version (projects/.../versions/latest), on l’utilise
  git_token_secret_version_norm = trimspace(var.dataform_git_token_secret_version)

  # fallback si tu donnes juste l'ID du secret
  git_token_secret_id_norm = trimspace(var.dataform_git_token_secret_id)

  git_token_secret_version_effective = (
    local.git_token_secret_version_norm != "" ? local.git_token_secret_version_norm :
    (local.git_token_secret_id_norm != "" ? "projects/${var.project_id}/secrets/${local.git_token_secret_id_norm}/versions/latest" : "")
  )

  git_enabled = alltrue([
    var.enable_git,
    local.git_repo_url_norm != "",
    local.git_token_secret_version_effective != "",
  ])
}
###############################################################################
# 1) Dataform Repository
###############################################################################
resource "google_dataform_repository" "this" {
  provider = google-beta

  # Projet + région Dataform
  project = var.project_id
  region  = var.region

  # name = ID technique du repo Dataform (immutable-ish)
  # Ex: lakehouse-dev-dataform
  name = var.repository_name

  # display_name = nom lisible dans la console
  # Si tu ne le mets pas, Terraform peut vouloir le “supprimer” (-> null)
  display_name = var.repo_display_name != "" ? var.repo_display_name : var.repository_name

  # Labels gouvernance / FinOps
  labels = var.labels

  # ---------------------------------------------------------------------------
  # Git remote settings (OPTIONNEL)
  # ---------------------------------------------------------------------------
  # BUT: ce bloc ne doit exister QUE si git_enabled == true
  # sinon => drift / suppression côté API
  dynamic "git_remote_settings" {
    for_each = local.git_enabled ? [1] : []
    content {
      # URL HTTPS du repo Git
      url = local.git_repo_url_norm

      # branche par défaut (utilise TON input enterprise)
      default_branch = var.dataform_default_branch

      # PAT Git via Secret Manager (version)
      authentication_token_secret_version = local.git_token_secret_version_effective
    }
  }
}
###############################################################################
# 2) Release Config
#
# Décrit comment Dataform compile le code :
# - git_commitish (branche/tag/sha)
# - default_database / default_schema
# - vars injectées
#
# NOTE :
# - repository = google_dataform_repository.this.name (ID "projects/.../repositories/...")
###############################################################################
resource "google_dataform_repository_release_config" "prod_release" {
  provider = google-beta

  project = var.project_id
  region  = var.region

  # Lien vers le repo Dataform
  repository = google_dataform_repository.this.name

  # ID de la release config (stable)
  name = "release-prod"

  # Référence Git utilisée pour compiler (souvent "main")
  # -> plutôt que var.git_default_branch en dur, on passe une variable dédiée
  git_commitish = var.git_commitish

  code_compilation_config {
    # Projet BigQuery par défaut
    default_database = var.project_id

    # Dataset par défaut où Dataform écrit tables/vues
    # ==> on prend la variable (évite les divergences env / rename)
    default_schema = var.default_schema

    # Variables Dataform (utilisable dans includes/constants.js / etc.)
    vars = {
      env = var.environment
    }
  }
}

###############################################################################
# 3) Workflow PROD (planifié)
#
# Objectif :
# - Exécution automatique (lun-ven 06:00)
# - Exécute uniquement les tags "prod"
#
# NOTE :
# - On pilote cron + timezone par variables (enterprise-ready)
###############################################################################
resource "google_dataform_repository_workflow_config" "prod_weekdays" {
  provider = google-beta

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.this.name

  name = "wf-prod-weekdays"

  # Très bien : on pointe sur la release config
  release_config = google_dataform_repository_release_config.prod_release.id

  # CRON & timezone pilotés
  cron_schedule = var.workflow_cron
  time_zone     = var.time_zone

  invocation_config {
    # Tag(s) à exécuter
    included_tags = ["prod"]

    # Service Account runtime Dataform (email complet)
    service_account = var.dataform_sa_email
  }
}

###############################################################################
# 4) Workflow DEV (On-demand)
#
# Objectif :
# - pas de cron (déclenchement manuel)
# - exécute uniquement les tags "dev"
###############################################################################
resource "google_dataform_repository_workflow_config" "dev_on_demand" {
  provider = google-beta

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.this.name

  name = "wf-dev-on-demand"

  release_config = google_dataform_repository_release_config.prod_release.id

  invocation_config {
    included_tags   = ["dev"]
    service_account = var.dataform_sa_email
  }
}