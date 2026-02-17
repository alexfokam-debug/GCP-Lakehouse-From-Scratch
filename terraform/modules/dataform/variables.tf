###############################################################################
# modules/dataform/variables.tf
# Objectif :
# - Déclarer toutes les variables nécessaires au module Dataform
# - Garder une interface claire entre ROOT et MODULE
###############################################################################

# ---------------------------------------------------------------------------
# Contexte projet / région / environnement
# ---------------------------------------------------------------------------

# ID du projet GCP (ex: lakehouse-486419)
variable "project_id" {
  description = "GCP project id où créer les ressources Dataform"
  type        = string
}

# Région GCP (ex: europe-west1)
# Attention : Dataform doit être créé dans une région supportée
# et cohérente avec BigQuery/Dataplex si tu veux une archi propre.
variable "region" {
  description = "Région GCP pour Dataform"
  type        = string
}

# Environnement (dev/prod)
variable "environment" {
  description = "Environnement de déploiement (dev, prod, ...)"
  type        = string
}

# ---------------------------------------------------------------------------
# Repository Dataform
# ---------------------------------------------------------------------------

# Nom technique du repository (ID dans l'API Dataform)
# Conseil : rester simple, lowercase, sans espaces.
variable "repo_name" {
  description = "Nom technique du repository Dataform (ID)"
  type        = string
}

# Nom lisible dans la console (display_name)
variable "repo_display_name" {
  description = "Nom d'affichage du repository Dataform"
  type        = string
}

# ---------------------------------------------------------------------------
# Git remote settings (connexion Git)
# ---------------------------------------------------------------------------

# URL du repo Git distant en HTTPS (recommandé) :
# ex: https://github.com/alexfokam-debug/GCP-Lakehouse-From-Scratch.git
variable "git_repo_url" {
  description = "URL HTTPS du dépôt Git à connecter à Dataform"
  type        = string
}

# Branche Git par défaut (obligatoire côté Dataform)
variable "git_default_branch" {
  description = "Branche Git par défaut (ex: main)"
  type        = string
  default     = "main"
}

# Secret Manager : version du secret contenant le token Git
# Format attendu :
# projects/<PROJECT_NUMBER>/secrets/<SECRET_NAME>/versions/latest
variable "git_token_secret_version" {
  description = "Secret Manager version contenant le token Git (PAT) pour Dataform"
  type        = string
}

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

# Labels communs (FinOps / gouvernance)
variable "labels" {
  description = "Labels à appliquer aux ressources Dataform"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Dataset cible pour les tables/vues Dataform (ex: analytics_dev)
# ---------------------------------------------------------------------------
variable "default_schema" {
  description = "Dataset BigQuery par défaut où Dataform écrit les objets (tables/vues)."
  type        = string
}

# ---------------------------------------------------------------------------
# Git commitish = branche/tag/sha que Dataform doit utiliser (souvent main)
# ---------------------------------------------------------------------------
variable "git_commitish" {
  description = "Référence Git à compiler/exécuter (branche, tag ou sha)."
  type        = string
  default     = "main"
}

# ---------------------------------------------------------------------------
# Timezone pour le scheduler Dataform (important pour du 'prod-like')
# ---------------------------------------------------------------------------
variable "time_zone" {
  description = "Timezone utilisée par Dataform pour interpréter le cron_schedule."
  type        = string
  default     = "Europe/Paris"
}

# ---------------------------------------------------------------------------
# CRON du workflow (prod-like : lun-ven à 06:00)
# ---------------------------------------------------------------------------
variable "workflow_cron" {
  description = "Cron Dataform. Ex: '0 6 * * 1-5' = lun-ven 06:00."
  type        = string
  default     = "0 6 * * 1-5"
}

##############################################
# Dataform - Git settings (Enterprise)
##############################################

variable "enable_git" {
  description = "Active la configuration Git Remote Settings du repo Dataform."
  type        = bool
  default     = false
}

variable "git_url" {
  description = "URL Git du repository Dataform (ex: https://github.com/org/repo)."
  type        = string
  default     = null
}


variable "git_token_secret_id" {
  description = <<EOT
ID du secret Secret Manager qui contient le token Git.
⚠️ Enterprise rule: Terraform NE DOIT PAS stocker le token, uniquement référencer 'latest'.
Ex: dataform-git-token
EOT
  type        = string
  default     = "dataform-git-token"
}


variable "repository_name" {
  description = "Nom du repository Dataform (ex: lakehouse-dev-dataform)"
  type        = string
}
##############################################################################
# Dataform module inputs (Enterprise)
##############################################################################

# ---- Git config (reprend tes noms tfvars) ----

variable "dataform_git_repo_url" {
  description = "URL HTTPS du repo Git."
  type        = string
  default     = null
}

variable "dataform_default_branch" {
  description = "Branche par défaut."
  type        = string
  default     = "main"
}

variable "dataform_git_token_secret_version" {
  description = "Resource name de la version secret (versions/latest)."
  type        = string
  default     = null
}