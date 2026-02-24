variable "org_id" {
  description = "Organization ID (numérique)."
  type        = string
}

variable "tag_key_short_name" {
  description = "Nom court de la TagKey (ex: environment)."
  type        = string
  default     = "environment"
}

variable "tag_key_description" {
  description = "Description de la TagKey."
  type        = string
  default     = "Environment tag (dev/staging/prod)"
}

/**
 * Une map pour construire proprement :
 * tag_values = {
 *   dev = { short_name = "Development", description = "..." }
 *   ...
 * }
 */
variable "tag_values" {
  description = "Valeurs possibles pour la TagKey environment."
  type = map(object({
    short_name  = string
    description = string
  }))
}