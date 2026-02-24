###############################################################################
# main.tf – Module Dataform (Enterprise-ready)
#
# Objectif :
# 1) Créer le repository Dataform
# 2) Créer une Release Config
# 3) Créer un Workflow Config PROD (planifié)
# 4) Créer un Workflow DEV (on-demand)
#
# Architecture Sécurité :
# - Le token Git est stocké dans un projet centralisé (Security Project)
# - On ne lit PAS le secret
# - On référence uniquement la VERSION fournie en variable
# - Terraform ne voit jamais le token
###############################################################################

###############################################################################
# 1️⃣ Repository Dataform
###############################################################################
resource "google_dataform_repository" "this" {
  provider = google-beta

  # ---------------------------------------------------------------------------
  # Contexte projet / région
  # ---------------------------------------------------------------------------
  project = var.project_id
  region  = var.region

  # ---------------------------------------------------------------------------
  # Nom du repository (ex: lakehouse-staging-dataform)
  # ---------------------------------------------------------------------------
  name         = var.repo_name
  display_name = var.repo_display_name

  # ---------------------------------------------------------------------------
  # Connexion Git distante (GitHub)
  #
  # IMPORTANT:
  # - On passe directement une version complète du secret
  # - Exemple:
  #   projects/518653594867/secrets/dataform-git-token/versions/latest
  # ---------------------------------------------------------------------------
  git_remote_settings {
    url                                 = var.git_repo_url
    default_branch                      = var.git_default_branch
    authentication_token_secret_version = var.dataform_git_token_secret_version
  }

  # Labels de gouvernance
  labels = var.labels
}

###############################################################################
# 2️⃣ Dataform Release Config
#
# Définit comment le repo est compilé (branche + variables)
###############################################################################
resource "google_dataform_repository_release_config" "prod_release" {
  provider = google-beta

  project = var.project_id
  region  = var.region

  repository = google_dataform_repository.this.name
  name       = "release-prod"

  # Branche utilisée pour compiler
  git_commitish = var.git_default_branch

  # Configuration de compilation
  code_compilation_config {

    # Base par défaut (projet GCP)
    default_database = var.project_id

    # Dataset cible analytics_{env}
    default_schema = "analytics_${var.environment}"

    # Variables injectées dans Dataform (ex: includes/constants.js)
    vars = {
      env = var.environment
    }
  }
}

###############################################################################
# 3️⃣ Workflow PROD (planifié)
#
# - Exécution automatique
# - Lun → Ven à 06:00
# - Exécute uniquement les tags "prod"
###############################################################################
resource "google_dataform_repository_workflow_config" "prod_weekdays" {
  provider = google-beta

  project    = var.project_id
  region     = var.region
  repository = google_dataform_repository.this.name

  name = "wf-prod-weekdays"

  release_config = google_dataform_repository_release_config.prod_release.id

  # CRON : 06:00 du lundi au vendredi
  cron_schedule = "0 6 * * 1-5"

  # Timezone Europe/Paris
  time_zone = "Europe/Paris"

  invocation_config {
    included_tags = ["prod"]

    # ⚠️ DOIT être un email complet
    # Exemple:
    # sa-dataform-staging@lakehouse-stg-486419.iam.gserviceaccount.com
    service_account = var.dataform_sa_email
  }
}

###############################################################################
# 4️⃣ Workflow DEV (On-demand)
#
# - Pas de cron
# - Utilisé pour déclenchement manuel
# - Exécute uniquement les tags "dev"
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