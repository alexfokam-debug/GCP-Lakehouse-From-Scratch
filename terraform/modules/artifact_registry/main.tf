# =============================================================================
# RESOURCE - Artifact Registry Repository
# =============================================================================

resource "google_artifact_registry_repository" "this" {

  # Projet GCP
  project = var.project_id

  # Région
  location = var.region

  # Nom du repo (ex: dataproc-custom)
  repository_id = var.repository_id

  # Format Docker (important pour Dataproc custom container)
  format = "DOCKER"

  # Description
  description = var.description

  # Mode standard (pas remote)
  mode = "STANDARD_REPOSITORY"
}