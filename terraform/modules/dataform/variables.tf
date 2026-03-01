###############################################################################
# modules/dataform/variables.tf — Interface unique & stable (Enterprise-ready)
#
# Design principles:
# - Un seul set de variables (pas de doublons)
# - Git remote settings piloté par enable_git + 2 inputs (url + secret_version)
# - Terraform NE LIT JAMAIS le secret -> on référence uniquement la version
###############################################################################

# ---------------------------------------------------------------------------
# Contexte projet / région / environnement
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project id où créer les ressources Dataform"
  type        = string
}

variable "region" {
  description = "Région GCP pour Dataform (ex: europe-west1)"
  type        = string
}

variable "environment" {
  description = "Environnement de déploiement (dev, prod, ...)"
  type        = string
}

# ---------------------------------------------------------------------------
# Repository Dataform
# ---------------------------------------------------------------------------
# IMPORTANT :
# - repository_name = repository_id (stable, utilisé par l'API)
# - évite repo_name/repo_display_name si tu ne les utilises pas dans main.tf
#   (sinon drift / confusion).
# ---------------------------------------------------------------------------

variable "repository_name" {
  description = "Repository Dataform ID (ex: lakehouse-dev-dataform)"
  type        = string
}

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

variable "labels" {
  description = "Labels à appliquer aux ressources Dataform"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Dataform compilation defaults
# ---------------------------------------------------------------------------

variable "default_schema" {
  description = "Dataset BigQuery par défaut où Dataform écrit les objets (ex: analytics_dev)"
  type        = string
}

variable "git_commitish" {
  description = "Référence Git à compiler (branche/tag/sha). Souvent 'main'."
  type        = string
  default     = "main"
}

# ---------------------------------------------------------------------------
# Workflows scheduling
# ---------------------------------------------------------------------------

variable "time_zone" {
  description = "Timezone utilisée par Dataform pour interpréter cron_schedule."
  type        = string
  default     = "Europe/Paris"
}

variable "workflow_cron" {
  description = "Cron Dataform. Ex: '0 6 * * 1-5' = lun-ven 06:00."
  type        = string
  default     = "0 6 * * 1-5"
}

# ---------------------------------------------------------------------------
# Git remote settings (Enterprise)
#
# - enable_git : active ou non le bloc git_remote_settings
# - dataform_git_repo_url : URL HTTPS du repo
# - dataform_git_token_secret_version : version du secret SM (projects/.../versions/...)
# ---------------------------------------------------------------------------

variable "enable_git" {
  description = "Active la configuration Git Remote Settings sur le repo Dataform."
  type        = bool
  default     = true
}

variable "dataform_git_repo_url" {
  description = "URL HTTPS du repo Git (ex: https://github.com/org/repo.git)"
  type        = string
  default     = ""
}

variable "dataform_default_branch" {
  description = "Branche par défaut du repo Git (ex: main)."
  type        = string
  default     = "main"
}

variable "dataform_git_token_secret_version" {
  description = "Secret Manager VERSION resource: projects/.../secrets/.../versions/<ver|latest>"
  type        = string
  default     = ""

  validation {
    condition = (
      var.dataform_git_token_secret_version == ""
      || can(regex("^projects/.+/secrets/.+/versions/.+$", var.dataform_git_token_secret_version))
    )
    error_message = "dataform_git_token_secret_version must be empty or in the form: projects/<id>/secrets/<name>/versions/<ver|latest>."
  }
}

# ---------------------------------------------------------------------------
# Runtime service account (Dataform execution)
# ---------------------------------------------------------------------------

variable "dataform_sa_email" {
  description = "Email du service account Dataform runtime (ex: sa-dataform-dev@PROJECT.iam.gserviceaccount.com)."
  type        = string
}

variable "repo_display_name" {
  description = "Nom d'affichage du repository Dataform (UI Console). Laisse vide pour utiliser repository_name."
  type        = string
  default     = ""
}
variable "dataform_git_token_secret_id" {
  description = "Secret ID (ex: dataform-git-token) stored in Secret Manager for Dataform Git authentication"
  type        = string
  default     = ""
}
