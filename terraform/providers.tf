terraform {
  backend "gcs" {}
}

terraform {
  required_version = ">= 1.4.0"

  # Déclaration des providers utilisés dans le projet
  required_providers {

    # Provider GCP STABLE
    # → utilisé pour BigQuery, IAM, GCS, Dataplex, etc.
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Provider GCP BETA
    # → nécessaire pour Dataform (non disponible dans google stable)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Provider utilitaire (scheduling, time-based resources)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

# Provider Google Cloud (utilise tes credentials gcloud ADC)
provider "google" {
  project = var.project_id
  region  = var.region
}


# Provider GCP beta (Dataform uniquement)
provider "google-beta" {
  project = var.project_id
  region  = var.region
}