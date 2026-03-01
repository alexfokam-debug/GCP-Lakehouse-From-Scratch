###############################################################################
# terraform/foundation/variables.tf — ROOT (FOUNDATION uniquement)
# -----------------------------------------------------------------------------
# Objectif :
# - Variables MINIMALES nécessaires pour déployer le socle (foundation)
# - Le socle = WIF GitHub + SA GitHub CI/CD + droits backend terraform
#
# Règle d'or :
# - Ce dossier DOIT pouvoir tourner sans BigQuery/Dataform/Dataplex.
# - Donc AUCUNE variable lakehouse n'apparaît ici.
###############################################################################

# -----------------------------------------------------------------------------
# (1) Projet GCP cible
# -----------------------------------------------------------------------------
variable "project_id" {
  description = "GCP project ID where resources will be created (ex: lakehouse-486419)."
  type        = string
}

# -----------------------------------------------------------------------------
# (2) Région par défaut
# -----------------------------------------------------------------------------
variable "region" {
  description = "Default region for GCP resources (ex: europe-west1)."
  type        = string
  default     = "europe-west1"
}

# -----------------------------------------------------------------------------
# (3) Environnement : contrôle strict
# -----------------------------------------------------------------------------
variable "environment" {
  description = "Deployment environment. Must be one of: dev, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Invalid environment. Allowed: dev, staging, prod. (Do NOT use prd)."
  }
}

# -----------------------------------------------------------------------------
# (4) Labels globaux
# -----------------------------------------------------------------------------
variable "labels" {
  description = "Common labels applied to all resources."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# (5) GitHub repository autorisé (WIF)
# -----------------------------------------------------------------------------
# Format attendu : "owner/repo"
# Exemple : "alexfokam-debug/GCP-Lakehouse-From-Scratch"
variable "github_repository" {
  description = "GitHub repository allowed to use Workload Identity Federation (owner/repo)."
  type        = string
}

# -----------------------------------------------------------------------------
# (6) Backend bucket (remote state Terraform)
# -----------------------------------------------------------------------------
# IMPORTANT :
# - C’est le bucket référencé dans backend.hcl (terraform init -backend-config=...)
variable "tf_state_bucket_name" {
  description = "Name of the Terraform remote state bucket (GCS backend)."
  type        = string
}

# -----------------------------------------------------------------------------
# (7) Bootstrapping CI/CD IAM
# -----------------------------------------------------------------------------
# true  -> on donne au SA GitHub CI/CD les droits nécessaires sur backend + secrets
# false -> sécurité : aucun droit auto sur backend/secrets
variable "bootstrap_ci_iam" {
  description = "If true, grants GitHub CI/CD SA rights on TF backend bucket + secrets."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# (8) Activer/désactiver la gestion WIF par Terraform
# -----------------------------------------------------------------------------
# true  -> Terraform crée le pool + provider + binding impersonation
# false -> WIF géré ailleurs (équipe platform / org policies)
variable "manage_wif" {
  description = "Whether Terraform should manage GitHub Workload Identity Federation resources."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# (9) OPTIONNEL : rôle admin WIF pool
# -----------------------------------------------------------------------------
# En entreprise : souvent INTERDIT / à éviter.
# Laisse false sauf si tu sais exactement pourquoi tu en as besoin.
variable "enable_github_cicd_wif_pool_admin" {
  description = "If true, grants WorkloadIdentityPoolAdmin to GitHub CI/CD SA (avoid unless required)."
  type        = bool
  default     = false
}