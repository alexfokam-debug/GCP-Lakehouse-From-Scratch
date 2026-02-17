###############################################################################
# outputs.tf – Module Dataform
# Objectif :
# - Exposer des outputs stables (repo + release + workflow)
# - Éviter les erreurs si une ressource n’existe pas encore
###############################################################################

output "repository_name" {
  description = "Nom complet (API) du repository Dataform."
  value       = google_dataform_repository.this.name
}

output "release_config_name" {
  description = "Nom complet (API) de la release config Dataform."
  value       = try(google_dataform_repository_release_config.prod_release.name, null)
}

output "workflow_config_name" {
  description = "Nom complet (API) du workflow config Dataform."
  value       = try(google_dataform_repository_workflow_config.prod_weekdays.name, null)
}