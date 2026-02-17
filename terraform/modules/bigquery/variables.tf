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