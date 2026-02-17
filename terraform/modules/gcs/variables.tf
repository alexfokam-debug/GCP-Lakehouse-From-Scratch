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
  default     = "europe-west1"

}

# Environnement (dev, prod, etc.)
# → Sert au tagging, à la gouvernance et aux coûts
variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

# Labels personnalisables
# → Permet d’ajouter des tags communs (owner, cost_center, platform, etc.)
variable "labels" {
  description = "Common labels for the bucket (owner, cost_center, platform, etc.)"
  type        = map(string)
  default     = {}
}

# Couche data (raw / curated / gold...)
variable "layer" {
  description = "Data layer for this bucket (raw, curated, etc.)"
  type        = string
  default     = "raw"
}

# Nom logique du domaine data (ex: sales, finance, hr)
variable "domain" {
  description = "Business data domain (sales, finance, hr, etc.)"
  type        = string
}

# Nom logique du dataset métier
variable "dataset_name" {
  description = "Logical dataset name (used for Dataplex asset naming)"
  type        = string
}
