# ID du projet GCP cible
# → utilisé par tous les modules
variable "project_id" {
  description = "GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "Default region for GCP resources"
  type        = string
  default     = "europe-west1"
}

# Environnement de déploiement
# → dev / prod / sandbox
variable "environment" {
  description = "Deployment environment. Must be one of: dev, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Invalid environment. Allowed: dev, staging, prod. (Do NOT use prd)."
  }
}

variable "labels" {
  description = "Common labels applied to all resources"
  type        = map(string)
  default     = {}
}

variable "domain" {
  description = "Domaine métier des données (sales, finance, hr, shared, etc.)"
  type        = string
}

variable "dataset_name" {
  description = "Nom logique du dataset métier"
  type        = string
}


# ------------------------------------------------------------
# Tables externes BigQuery (RAW)
# ------------------------------------------------------------
# Map de tables externes à créer dans le dataset raw_ext_<env>
#
# Exemple :
# raw_external_tables = {
#   sample_ext = {
#     source_uris        = ["gs://<bucket>/domain=sales/dataset=sample/ingest_date=*/event_date=*/*.parquet"]
#     source_format      = "PARQUET"
#     hive_source_prefix = "gs://<bucket>/domain=sales/dataset=sample/"
#     require_partition_filter = false
#   }
# }
variable "raw_external_tables" {
  description = "External BigQuery tables configuration (RAW layer)"
  type = map(object({
    source_uris              = list(string)
    source_format            = string # PARQUET | CSV | AVRO | NEWLINE_DELIMITED_JSON ...
    hive_source_prefix       = optional(string)
    require_partition_filter = optional(bool)
  }))
  default = {}
}

# ------------------------------------------------------------
# Variable dataform
# ------------------------------------------------------------
variable "dataform_git_repo_url" {
  description = "Repo Git (HTTPS) du projet Dataform"
  type        = string
}

variable "dataform_default_branch" {
  description = "Branche Git du projet Dataform"
  type        = string
  default     = "main"
}

variable "dataform_git_token_secret_version" {
  description = "Version du secret Secret Manager contenant le token Git pour Dataform"
  type        = string
}

###############################################################################
# Curated external tables (Iceberg) - toggle
###############################################################################
variable "enable_curated_external_tables" {
  description = "Active la création des tables externes curated (Iceberg) seulement quand les fichiers existent."
  type        = bool
  default     = false
}


# ------------------------------------------------------------
# CURATED external tables (BigLake)
# ------------------------------------------------------------
# Map de tables externes à créer dans curated_ext_<env>
#
# Exemple :
# curated_external_tables = {
#   customer = {
#     source_format = "ICEBERG"
#     source_uris   = ["gs://<bucket-curated>/iceberg/customer/"]
#   }
# }
#
# Ou en Parquet :
# curated_external_tables = {
#   customer = {
#     source_format      = "PARQUET"
#     source_uris        = ["gs://<bucket-curated>/parquet/customer/*"]
#     hive_source_prefix = "gs://<bucket-curated>/parquet/customer/"
#   }
# }
variable "curated_external_tables" {
  description = "External BigQuery tables configuration (CURATED layer via BigLake)"
  type = map(object({
    source_uris              = list(string)
    source_format            = string
    autodetect               = optional(bool)
    hive_source_prefix       = optional(string)
    require_partition_filter = optional(bool)
  }))
  default = {}
}

# =============================================================================
# Iceberg (CURATED layer)
# =============================================================================
# Objectif :
# - Déclarer un dataset BigQuery dédié aux tables Iceberg
# - Permet séparation claire curated_managed vs curated_iceberg
# =============================================================================

variable "curated_iceberg_dataset_id" {
  description = "BigQuery dataset for curated Iceberg tables (ex: curated_iceberg_dev)"
  type        = string
}


variable "dataproc_sa_email" {
  type        = string
  description = "Service Account email used by Dataproc Serverless batches"
}

variable "env" {
  type = string
}
# =============================================================================
# FEATURE FLAG - TMP DATASET (Dataproc / BigQuery connector)
# =============================================================================
# Pourquoi ?
# - Dataproc Serverless + BigQuery connector peut matérialiser des tables temporaires
# - On veut un dataset tmp dédié (ex: tmp_lakehouse_dev)
# - Mais en entreprise on veut pouvoir désactiver ce composant si besoin
# =============================================================================
variable "enable_tmp_dataset" {
  description = "If true, create BigQuery dataset tmp_lakehouse_<env> used by Dataproc/BigQuery connector."
  type        = bool
  default     = true
}

variable "enable_samples" {
  description = "If true, creates sample external table(s). Disable in prod to avoid apply failure."
  type        = bool
  default     = false
}

variable "project_id_short" {
  description = "Identifiant court du projet (ex: 486419) utilisé pour nommer les buckets."
  type        = string
}
############################################################
# Variables Dataform / Secret Manager
############################################################

variable "dataform_git_token_secret_id" {
  description = "Secret Manager secret id contenant le token Git pour Dataform (ex: dataform-git-token)."
  type        = string
  default     = "dataform-git-token"
}

variable "dataform_sa_email" {
  description = "Email du service account Dataform runtime (ex: sa-dataform-dev@PROJECT.iam.gserviceaccount.com)."
  type        = string
}
variable "dataform_repository_name" {
  type        = string
  description = "Nom du repository Dataform (ex: lakehouse-dev-dataform)"
}

variable "enable_sales_orders_external_tables" {
  type        = bool
  description = "Create external external tables for orders and sales_transactions only if data exists."
  default     = false
}
variable "github_repository" {
  type        = string
  description = "GitHub repository allowed to use Workload Identity Federation (owner/repo)"
}
variable "tf_state_bucket_name" {
  type        = string
  description = "Name of the Terraform remote state bucket"
}