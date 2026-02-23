variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "curated_dataset_id" {
  type = string
}

variable "analytics_dataset_id" {
  type = string
}

###############################################################################
# variables.tf – Module IAM
# Objectif :
# - Recevoir l’ID du dataset Curated Iceberg afin d’y appliquer des droits
###############################################################################

variable "curated_iceberg_dataset_id" {
  description = "Dataset BigQuery Curated Iceberg (ex: curated_iceberg_dev)."
  type        = string
}
variable "iceberg_bucket_name" { type = string }

# Dataset BigQuery RAW external (ex: raw_ext_dev)
variable "raw_external_dataset_id" {
  type        = string
  description = "BigQuery dataset id for RAW external tables (e.g. raw_ext_dev)"
}


variable "dataproc_sa_email" {
  type = string
}
variable "tmp_dataset_id" {
  type = string
}


variable "dataproc_temp_bucket_name" {
  description = "Nom du bucket GCS temp utilisé par le connector BigQuery/Dataproc Serverless"
  type        = string
}


variable "enable_tmp_dataset" {
  description = "Active l'IAM sur le dataset temporaire."
  type        = bool
  default     = true
}

variable "project_number" { type = string }
variable "dataform_sa_email" { type = string }

variable "raw_bucket_name" {
  type        = string
  description = "Bucket GCS RAW (ex: lakehouse-486419-raw-dev)"
}

variable "enterprise_dataset_id" {
  type        = string
  description = "Enterprise dataset id created by bigquery module"
}

# Repo GitHub autorisé (sécurité WIF)
variable "github_repository" {
  type        = string
  description = "GitHub repository in the form owner/repo"
}
variable "tf_state_bucket_name" {
  type        = string
  description = "Name of the Terraform remote state bucket"
}