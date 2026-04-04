# =============================================================================
# OUTPUTS
# =============================================================================

output "repository_url" {
  description = "URL du repository Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}"
}