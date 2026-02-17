# ID du projet GCP dans lequel les ressources seront créées
# → Permet de réutiliser le module dans plusieurs projets
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

# Nom du bucket GCS
# → Le naming est externalisé pour respecter les conventions
variable "bucket_name" {
  description = "Name of the GCS bucket"
  type        = string
}

# Localisation du bucket (EU, US, etc.)
# → Par défaut EU (bon choix pour la France / RGPD)
variable "location" {
  description = "Bucket location (EU, US, etc.)"
  type        = string
  default     = "EU"
}

# Environnement (dev, prod, etc.)
# → Sert au tagging, à la gouvernance et aux coûts
variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

# Labels personnalisables
# → Permet d’ajouter des tags communs (owner, cost_center, etc.)
variable "labels" {
  description = "Common labels for the bucket"
  type        = map(string)
  default     = {}
}
