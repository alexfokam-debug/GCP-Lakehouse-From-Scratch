terraform {
  required_version = ">= 1.5.0"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

/**
 * Provider google :
 * On utilisera l'auth via WIF depuis GitHub Actions.
 */
provider "google" {
  project = var.bootstrap_project_id
  region  = var.location
}

