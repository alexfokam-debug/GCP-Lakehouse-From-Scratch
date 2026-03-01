###############################################################################
# variables.tf — Module IAM (dual-mode)
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
  description = "true: IAM runtimes Dataform/Dataproc + IAM datasets/buckets. false: foundation-only (WIF/CI)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Lakehouse datasets (OPTIONAL en foundation)
# -----------------------------------------------------------------------------
variable "curated_dataset_id" {
  description = "Dataset curated_<env>."
  type        = string
  nullable    = true
  default     = null
}

variable "analytics_dataset_id" {
  description = "Dataset analytics_<env>."
  type        = string
  nullable    = true
  default     = null
}

variable "raw_external_dataset_id" {
  description = "Dataset raw_ext_<env>."
  type        = string
  nullable    = true
  default     = null
}

variable "curated_iceberg_dataset_id" {
  description = "Dataset curated_iceberg_<env>."
  type        = string
  nullable    = true
  default     = null
}

variable "tmp_dataset_id" {
  description = "Dataset tmp_lakehouse_<env>."
  type        = string
  nullable    = true
  default     = null
}

variable "enable_tmp_dataset" {
  description = "Active IAM Dataproc sur tmp_dataset_id."
  type        = bool
  default     = true
}

variable "enterprise_dataset_id" {
  description = "Dataset enterprise_<env> (optionnel)."
  type        = string
  nullable    = true
  default     = null
}

# -----------------------------------------------------------------------------
# Lakehouse buckets (OPTIONAL en foundation)
# -----------------------------------------------------------------------------
variable "raw_bucket_name" {
  description = "Bucket RAW."
  type        = string
  nullable    = true
  default     = null
}

variable "iceberg_bucket_name" {
  description = "Bucket ICEBERG."
  type        = string
  nullable    = true
  default     = null
}

variable "dataproc_temp_bucket_name" {
  description = "Bucket TEMP Dataproc."
  type        = string
  nullable    = true
  default     = null
}

# -----------------------------------------------------------------------------
# GitHub / WIF (foundation)
# -----------------------------------------------------------------------------
variable "github_repository" {
  description = "Repo GitHub (owner/repo)."
  type        = string
}

variable "tf_state_bucket_name" {
  description = "Bucket backend Terraform."
  type        = string
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
  description = "Si true, le module gère WIF dans github_wif.tf."
  type        = bool
  default     = true
}

variable "enable_github_cicd_wif_pool_admin" {
  description = "Si true, donne workloadIdentityPoolAdmin au SA GitHub CI."
  type        = bool
  default     = false
}