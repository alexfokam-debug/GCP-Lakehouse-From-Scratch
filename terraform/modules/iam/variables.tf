###############################################################################
# variables.tf — Module IAM (refactor propre)
###############################################################################

variable "project_id" {
  description = "ID du projet GCP."
  type        = string
}

variable "environment" {
  description = "Environnement (dev/staging/prod)."
  type        = string
}

# -----------------------------------------------------------------------------
# MODE SWITCH
# -----------------------------------------------------------------------------
variable "enable_lakehouse_runtimes" {
  description = "true: IAM runtimes Dataform/Dataproc + IAM datasets/buckets. false: foundation-only."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Lakehouse datasets
# -----------------------------------------------------------------------------
variable "curated_dataset_id" {
  description = "Dataset curated_<env>."
  type        = string
  default     = null
}

variable "analytics_dataset_id" {
  description = "Dataset analytics_<env>."
  type        = string
  default     = null
}

variable "raw_external_dataset_id" {
  description = "Dataset raw_ext_<env>."
  type        = string
  default     = null
}

variable "curated_iceberg_dataset_id" {
  description = "Dataset curated_iceberg_<env>."
  type        = string
  default     = null
}

variable "tmp_dataset_id" {
  description = "Dataset tmp_lakehouse_<env>."
  type        = string
  default     = null
}

variable "enable_tmp_dataset" {
  description = "Active IAM Dataproc sur tmp_dataset_id."
  type        = bool
  default     = true
}

variable "enterprise_dataset_id" {
  description = "Dataset enterprise_<env>."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Lakehouse buckets
# -----------------------------------------------------------------------------
variable "raw_bucket_name" {
  description = "Bucket RAW."
  type        = string
  default     = null
}

variable "curated_bucket_name" {
  description = "Bucket CURATED."
  type        = string
  default     = null
}

variable "iceberg_bucket_name" {
  description = "Bucket ICEBERG."
  type        = string
  default     = null
}

variable "dataproc_temp_bucket_name" {
  description = "Bucket TEMP Dataproc."
  type        = string
  default     = null
}

variable "scripts_bucket_name" {
  description = "Bucket SCRIPTS."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# GitHub / WIF (foundation only)
# -----------------------------------------------------------------------------
variable "github_repository" {
  description = "Repo GitHub (owner/repo). Requis seulement si manage_wif = true."
  type        = string
  default     = null
}

variable "tf_state_bucket_name" {
  description = "Bucket backend Terraform. Requis seulement si bootstrap_ci_iam = true."
  type        = string
  default     = null
}

variable "bootstrap_ci_iam" {
  description = "Si true, donne au SA GitHub CI les droits backend+secret."
  type        = bool
  default     = false
}

variable "git_token_secret_id" {
  description = "Secret ID du token Git Dataform."
  type        = string
  default     = "dataform-git-token"
}

variable "manage_wif" {
  description = "Si true, le module gère WIF."
  type        = bool
  default     = false
}

variable "enable_github_cicd_wif_pool_admin" {
  description = "Si true, donne workloadIdentityPoolAdmin au SA GitHub CI."
  type        = bool
  default     = false
}

variable "github_repository_owner" {
  description = "Optionnel. Si null, déduit automatiquement depuis github_repository."
  type        = string
  default     = null
}

variable "allow_pull_request" {
  description = "Autoriser l'auth via PR."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Build humain local
# -----------------------------------------------------------------------------
variable "human_user_email" {
  description = "Adresse email de l'utilisateur humain."
  type        = string
  default     = null
}

variable "enable_human_build_access" {
  description = "Active les rôles Cloud Build / Artifact Registry pour l'utilisateur humain."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Cloud Build runtime
# -----------------------------------------------------------------------------
variable "cloud_build_service_account_email" {
  description = "Service account utilisé par Cloud Build."
  type        = string
  default     = null
}

variable "enable_cloud_build_runtime_access" {
  description = "Active les droits IAM nécessaires au service account Cloud Build."
  type        = bool
  default     = false
}