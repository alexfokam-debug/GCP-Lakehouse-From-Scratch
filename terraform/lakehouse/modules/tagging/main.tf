/**
 * Module: tagging (project-level)
 * Rôle: Attacher (bind) un TagValue existant à un projet.
 *
 * IMPORTANT:
 * - Ce module ne crée PAS de TagKey/TagValue (responsabilité foundation).
 * - En entreprise, ce module est autorisé côté projets.
 */

data "google_tags_tag_value" "env" {
  /**
   * parent = TagKey name complet : "tagKeys/123..."
   * short_name = "Development" ou "Staging" ou "Production"
   */
  parent     = var.environment_tag_key_name
  short_name = var.environment_tag_value_short_name
}

resource "google_tags_tag_binding" "project_environment" {
  /**
   * parent = "projects/<PROJECT_NUMBER>"
   * --> attention : c'est le PROJECT NUMBER, pas l'ID.
   */
  parent    = "projects/${var.project_number}"
  tag_value = data.google_tags_tag_value.env.name
}