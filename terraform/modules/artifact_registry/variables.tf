# =============================================================================
# VARIABLES - Artifact Registry module
# =============================================================================

variable "project_id" {
  description = "ID du projet GCP"
  type        = string
}

variable "region" {
  description = "Région du repository"
  type        = string
}

variable "repository_id" {
  description = "Nom du repository Artifact Registry"
  type        = string
}

variable "description" {
  description = "Description du repo"
  type        = string
  default     = "Artifact Registry repository"
}