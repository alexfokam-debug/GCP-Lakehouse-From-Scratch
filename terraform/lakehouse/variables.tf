###############################################################################
# terraform/lakehouse/variables.tf — ROOT (LAKEHOUSE uniquement)
# -----------------------------------------------------------------------------
# Objectif :
# - Variables nécessaires au déploiement de la couche DATA (lakehouse)
# - BigQuery / Dataform / Dataplex / Iceberg / External tables / Samples
#
# IMPORTANT :
# - Le stack "lakehouse" est un ROOT terraform indépendant.
# - Donc il DOIT aussi avoir project_id / region / environment / labels ici,
#   même si ces variables existent dans foundation.
###############################################################################

# -----------------------------------------------------------------------------
# (0) Variables communes indispensables (car root indépendant)
# -----------------------------------------------------------------------------
variable "project_id" {
  description = "GCP project ID where resources will be created (ex: lakehouse-486419)."
  type        = string
}

variable "region" {
  description = "Default region for GCP resources (ex: europe-west1)."
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Deployment environment. Must be one of: dev, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Invalid environment. Allowed: dev, staging, prod. (Do NOT use prd)."
  }
}

variable "labels" {
  description = "Common labels applied to all resources."
  type        = map(string)
  default     = {}
}
variable "github_repository" {
  description = "Repository GitHub (owner/repo). Requis par le module IAM, même si WIF est désactivé ici."
  type        = string
}

variable "tf_state_bucket_name" {
  description = "Nom du bucket GCS de remote state Terraform. Requis par le module IAM."
  type        = string
}

# -----------------------------------------------------------------------------
# (1) Métadonnées "data domain"
# -----------------------------------------------------------------------------
variable "domain" {
  description = "Domaine métier des données (sales, finance, hr, shared, etc.)."
  type        = string
}

variable "dataset_name" {
  description = "Nom logique du dataset métier (utilisé dans les paths GCS: dataset=...)."
  type        = string
}

# -----------------------------------------------------------------------------
# (2) External tables BigQuery RAW (dataset raw_ext_<env>)
# -----------------------------------------------------------------------------
variable "raw_external_tables" {
  description = "External BigQuery tables configuration (RAW layer)."
  type = map(object({
    source_uris              = list(string)
    source_format            = string
    hive_source_prefix       = optional(string)
    require_partition_filter = optional(bool)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# (3) Dataform - repo Git
# -----------------------------------------------------------------------------
variable "dataform_git_repo_url" {
  description = "Repo Git (HTTPS) du projet Dataform."
  type        = string
}

variable "dataform_default_branch" {
  description = "Branche Git du projet Dataform."
  type        = string
  default     = "main"
}

# -----------------------------------------------------------------------------
# (4) Dataform - Secret Manager (VERSION complète attendue par l’API Dataform)
# -----------------------------------------------------------------------------
# Exemple :
# projects/<project>/secrets/dataform-git-token/versions/latest
variable "dataform_git_token_secret_version" {
  description = "Secret Manager secret VERSION (full path) containing the Git token for Dataform."
  type        = string
}

# -----------------------------------------------------------------------------
# (5) Curated external tables (BigLake / Iceberg)
# -----------------------------------------------------------------------------
variable "enable_curated_external_tables" {
  description = "Active la création des tables externes curated (Iceberg) seulement quand les fichiers existent."
  type        = bool
  default     = false
}

variable "curated_external_tables" {
  description = "External BigQuery tables configuration (CURATED layer via BigLake)."
  type = map(object({
    source_uris              = list(string)
    source_format            = string
    autodetect               = optional(bool)
    hive_source_prefix       = optional(string)
    require_partition_filter = optional(bool)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# (6) Dataset Iceberg “managed” côté BigQuery
# -----------------------------------------------------------------------------
variable "curated_iceberg_dataset_id" {
  description = "BigQuery dataset for curated Iceberg tables (ex: curated_iceberg_dev)."
  type        = string
}

# -----------------------------------------------------------------------------
# (7) Feature flag : dataset TMP (Dataproc / BigQuery connector)
# -----------------------------------------------------------------------------
variable "enable_tmp_dataset" {
  description = "If true, create / manage dataset tmp used by Dataproc BigQuery connector."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# (8) Samples / bootstrap data
# -----------------------------------------------------------------------------
variable "enable_samples" {
  description = "If true, creates sample external table(s). Disable in prod to avoid apply failure."
  type        = bool
  default     = false
}

variable "enable_sales_orders_external_tables" {
  description = "Create external tables for orders and sales_transactions only if data exists."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# (9) Dataform runtime SA + repo name
# -----------------------------------------------------------------------------
variable "dataform_sa_email" {
  description = "Email du service account Dataform runtime (ex: sa-dataform-dev@PROJECT.iam.gserviceaccount.com)."
  type        = string
}

variable "dataform_repository_name" {
  description = "Nom du repository Dataform (ex: lakehouse-dev-dataform)."
  type        = string
}

variable "dataform_enable_git" {
  description = "Active la config Git sur le repo Dataform."
  type        = bool
  default     = true
}

variable "dataform_workflow_cron" {
  type    = string
  default = "0 6 * * 1-5"
}
variable "dataform_time_zone" {
  type    = string
  default = "Europe/Paris"
}
variable "enable_git" {
  description = "Enable git integration for Dataform repository"
  type        = bool
  default     = false
}

variable "dataform_git_token_secret_id" {
  description = "Secret Manager secret_id containing the Git token"
  type        = string
  default     = ""
}
variable "enable_dataplex" {
  type    = bool
  default = false
}

# -----------------------------------------------------------------------------
# (10) External tables CURATED en Parquet (prepared zone)
# -----------------------------------------------------------------------------
# Objectif :
# - exposer dans BigQuery les fichiers Parquet produits par Dataproc
# - permettre requêtage SQL immédiat sans charger physiquement la donnée
# - préparer la couche d'entrée pour Dataform
#
# Exemple typique :
# curated_prepared_external_tables = {
#   arco_era5_vertical_profile_vo = {
#     source_format = "PARQUET"
#     source_uris = [
#       "gs://lakehouse-486419-curated-dev/domain=weather/dataset=arco_era5/prepared/daily_vertical_profile_vo/*.parquet"
#     ]
#   }
# }
# -----------------------------------------------------------------------------
variable "curated_prepared_external_tables" {
  description = "External BigQuery tables configuration for prepared parquet data stored in curated GCS."
  type = map(object({
    source_uris   = list(string)
    source_format = string
    autodetect    = optional(bool)
  }))
  default = {}
}