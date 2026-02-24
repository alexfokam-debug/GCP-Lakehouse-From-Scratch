/**
 * Module: org_tags
 * Rôle: créer les TagKeys & TagValues au niveau ORGANIZATION (org-wide).
 * En entreprise, ce module serait géré par l’équipe plateforme.
 */
resource "google_tags_tag_key" "environment" {
  parent      = "organizations/${var.org_id}"
  short_name  = var.tag_key_short_name # ex: "environment"
  description = var.tag_key_description
}

/**
 * On crée toutes les valeurs de tag (dev/staging/prod)
 * via for_each sur une map.
 */
resource "google_tags_tag_value" "values" {
  for_each = var.tag_values

  parent      = google_tags_tag_key.environment.name
  short_name  = each.value.short_name
  description = each.value.description
}