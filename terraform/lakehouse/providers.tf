###############################################################################
# terraform/lakehouse/providers.tf
# -----------------------------------------------------------------------------
# Rôle de ce fichier :
# - Déclarer les providers (google + google-beta + time)
# - Déclarer le backend "gcs" (config injectée via backend.hcl au `terraform init`)
#
# Important :
# - Le backend ne doit PAS contenir bucket/prefix ici, pour rester multi-env.
#   => Ces valeurs viennent de: terraform/lakehouse/envs/<env>/backend.hcl
# - Le provider google-beta est requis pour certaines ressources Dataform.
###############################################################################

terraform {
  # ---------------------------------------------------------------------------
  # Backend Terraform
  # ---------------------------------------------------------------------------
  # On déclare simplement le type "gcs".
  # La config (bucket/prefix) est fournie au runtime via:
  #   terraform init -backend-config=envs/<env>/backend.hcl
  # ---------------------------------------------------------------------------
  backend "gcs" {}

  # ---------------------------------------------------------------------------
  # Version minimale Terraform
  # ---------------------------------------------------------------------------
  required_version = ">= 1.4.0"

  # ---------------------------------------------------------------------------
  # Providers requis (versions épinglées)
  # ---------------------------------------------------------------------------
  required_providers {
    # Provider Google Cloud "stable"
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Provider Google Cloud "beta" (Dataform / features en preview)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Provider "time" (attentes type time_sleep)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

###############################################################################
# Provider Google Cloud (stable)
###############################################################################
provider "google" {
  # Projet GCP cible (ex: lakehouse-dev-486419)
  project = var.project_id

  # Région par défaut (ex: europe-west1)
  region = var.region
}

###############################################################################
# Provider Google Cloud (beta)
###############################################################################
provider "google-beta" {
  # Même projet / région
  project = var.project_id
  region  = var.region
}