# Projet GCP
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

# Environnement (dev/prod)
variable "environment" {
  description = "Deployment environment"
  type        = string
}

# Localisation BigQuery
variable "location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "europe-west1"
}

# Labels communs
variable "labels" {
  description = "Labels applied to BigQuery resources"
  type        = map(string)
  default     = {}
}
variable "env" {
  type    = string
  default = null
}
locals {
  effective_env = coalesce(var.environment, var.env)
}

variable "enable_tmp_dataset" {
  description = "Active la création du dataset BigQuery temporaire (tmp_lakehouse_<env>)."
  type        = bool
  default     = true
}
variable "raw_external_tables" {
  description = "External tables definitions (BigQuery external tables backed by GCS)"
  type = map(object({
    source_format = string
    source_uris   = list(string)
    autodetect    = optional(bool, true)

    hive_source_prefix       = optional(string)
    require_partition_filter = optional(bool, false)
  }))
  default = {}
}

variable "enable_sales_orders_external_tables" {
  type        = bool
  description = "Create external tables for orders and sales_transactions only when files exist in GCS."
  default     = false
}

