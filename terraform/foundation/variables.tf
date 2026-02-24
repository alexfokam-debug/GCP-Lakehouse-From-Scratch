variable "org_id" {
  description = "Organization ID (numérique)."
  type        = string
}

variable "bootstrap_project_id" {
  description = "Un projet GCP hôte utilisé par le provider."
  type        = string
}

variable "location" {
  description = "Région par défaut."
  type        = string
  default     = "europe-west1"
}