output "environment_tag_key_name" {
  description = "Nom complet de la TagKey (ex: tagKeys/123...)"
  value       = google_tags_tag_key.environment.name
}

output "environment_tag_key_id" {
  description = "ID de la TagKey (utile pour data sources)."
  value       = google_tags_tag_key.environment.id
}

output "environment_tag_values" {
  description = "Map des TagValues (nom complet tagValues/...)."
  value = {
    for k, v in google_tags_tag_value.values :
    k => v.name
  }
}