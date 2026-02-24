variable "project_number" {
  description = "Project NUMBER (pas l'ID) du projet cible."
  type        = string
}

variable "environment_tag_key_name" {
  description = "Nom complet de la TagKey (ex: tagKeys/123...). Sortie de foundation."
  type        = string
}

variable "environment_tag_value_short_name" {
  description = "Nom court de la TagValue (Development/Staging/Production)."
  type        = string
}