###############################################################################
# variables.tf — Module IAM (OPTION 1 = SA Dataproc unique géré par Terraform)
# -----------------------------------------------------------------------------
# Objectif :
# - Centraliser la gestion IAM des runtimes (Dataform / Dataproc / GitHub CI/CD)
# - Éviter tout “SA externe” passé en variable (source de bugs / incohérences)
#
# Principe Option 1 :
# - Le SA Dataproc runtime est créé DANS ce module :
#     google_service_account.dataproc_runtime
# - Donc : on NE passe PLUS "dataproc_sa_email" en variable.
###############################################################################

# -----------------------------------------------------------------------------
# (A) Infos de base
# -----------------------------------------------------------------------------
variable "project_id" {
  description = "ID du projet GCP où on applique IAM (ex: lakehouse-486419)."
  type        = string
}

variable "environment" {
  description = "Nom de l'environnement (dev/staging/prod). Sert aux suffixes et à la séparation."
  type        = string
}

# -----------------------------------------------------------------------------
# (B) Datasets BigQuery (IDs uniquement)
# -----------------------------------------------------------------------------
variable "curated_dataset_id" {
  description = "ID dataset Curated (ex: curated_dev). Dataform a besoin de lecture."
  type        = string
}

variable "analytics_dataset_id" {
  description = "ID dataset Analytics (ex: analytics_dev). Dataform a besoin d'écriture."
  type        = string
}

variable "raw_external_dataset_id" {
  description = "ID dataset RAW external (ex: raw_ext_dev). Dataform/Dataproc ont souvent besoin de lecture."
  type        = string
}

variable "curated_iceberg_dataset_id" {
  description = "ID dataset BigQuery dédié aux tables Iceberg (ex: curated_iceberg_dev)."
  type        = string
}

variable "tmp_dataset_id" {
  description = "ID dataset TMP (ex: tmp_lakehouse_dev). Utilisé par Dataproc/Connectors si besoin."
  type        = string
}

variable "enterprise_dataset_id" {
  description = "ID dataset Enterprise (ex: enterprise_dev). Si Dataform doit y écrire."
  type        = string
}

# -----------------------------------------------------------------------------
# (C) Buckets GCS
# -----------------------------------------------------------------------------
variable "raw_bucket_name" {
  description = "Nom du bucket RAW (ex: lakehouse-486419-raw-dev). Dataform doit lire."
  type        = string
}

variable "iceberg_bucket_name" {
  description = "Nom du bucket ICEBERG (ex: lakehouse-486419-iceberg-dev). Dataproc écrit/maj des objets."
  type        = string
}

variable "dataproc_temp_bucket_name" {
  description = "Nom du bucket GCS temp Dataproc (ex: ...-dataproc-temp-dev)."
  type        = string
}

# -----------------------------------------------------------------------------
# (D) Feature flags
# -----------------------------------------------------------------------------
variable "enable_tmp_dataset" {
  description = "Active les droits Dataproc sur le dataset TMP (true/false)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# (E) Dataform runtime SA (email)
# -----------------------------------------------------------------------------
# IMPORTANT :
# - Dataform workflow_config.invocation_config.service_account utilise un email.
# - On garde la variable car ton module Dataform peut référencer ce SA.
# - MAIS dans IAM, on crée aussi un SA Dataform (google_service_account.dataform).
#   => Tu peux à terme converger et ne plus passer cette variable.
variable "dataform_sa_email" {
  description = "Email du Service Account runtime Dataform (ex: sa-dataform-dev@...).Peut être celui créé par ce module, ou fourni par le root. (On standardisera ensuite.)"
  type        = string
}

# -----------------------------------------------------------------------------
# (F) GitHub CI/CD (WIF)
# -----------------------------------------------------------------------------
variable "github_repository" {
  description = "Repo GitHub autorisé par WIF au format owner/repo (ex: alexfokam-debug/GCP-Lakehouse-From-Scratch)."
  type        = string
}

variable "tf_state_bucket_name" {
  description = "Bucket GCS utilisé comme backend Terraform (remote state)."
  type        = string
}

variable "bootstrap_ci_iam" {
  description = "Sécurité : si false, on ne donne PAS automatiquement les droits CI/CD sur backend+secret."
  type        = bool
  default     = false
}

variable "git_token_secret_id" {
  description = "Secret ID (pas le full path) du token Dataform Git (ex: dataform-git-token)."
  type        = string
}

# -----------------------------------------------------------------------------
# (G) Project number (OPTIONNEL)
# -----------------------------------------------------------------------------
# Dans ton main.tf on peut récupérer le project number via data.google_project.current.number.
# => Je te conseille de SUPPRIMER cette variable à terme.
# Je la laisse si tu veux garder compatibilité, mais on ne l'utilise plus dans le code “clean”.
variable "project_number" {
  description = "Project number GCP (legacy). On préfère data.google_project.current.number."
  type        = string
  default     = ""
}

variable "manage_wif" {
  type        = bool
  description = "Manage GitHub WIF resources in this module."
  default     = true
}