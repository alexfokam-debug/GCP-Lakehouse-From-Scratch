variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Dataplex region (ex: EU)"
  default     = "europe-west1"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev / prod)"
}

variable "raw_bucket" {
  type        = string
  description = "Name of the RAW GCS bucket"
}

variable "curated_dataset" {
  type        = string
  description = "BigQuery curated dataset ID"
}

variable "labels" {
  type        = map(string)
  description = "Common resource labels"
  default     = {}
}

variable "raw_external_dataset" {
  type        = string
  description = "BigQuery RAW external dataset ID (for external tables)"
}

