# -----------------------------------------------------------------------------
# versions.tf – Module Dataform
# -----------------------------------------------------------------------------
# Objectif :
# - Déclarer les providers nécessaires au module
# - Forcer google-beta en plus de google
# -----------------------------------------------------------------------------

terraform {
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