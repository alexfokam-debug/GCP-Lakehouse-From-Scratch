terraform {
  backend "gcs" {}

  required_version = ">= 1.4.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

# Provider Google Cloud (ADC via gcloud / workload identity)
provider "google" {
  project = var.project_id
  region  = var.region
}

# Provider beta (utile si WIF/Dataform beta dans certains cas)
provider "google-beta" {
  project = var.project_id
  region  = var.region
}