# Déclaration de la ressource Cloud Storage Bucket
resource "google_storage_bucket" "this" {

  # Nom du bucket (fourni par le module appelant)
  name = var.bucket_name

  # Projet GCP cible
  project = var.project_id

  # Région du bucket
  location = var.location

  # Bonne pratique sécurité :
  # IAM au niveau du bucket (pas d’ACL objets)
  uniform_bucket_level_access = true

  # Activation du versioning
  # → indispensable pour :
  #   - rollback
  #   - audit
  #   - protection contre suppressions accidentelles
  versioning {
    enabled = true
  }

  # Labels = gouvernance + FinOps + Data Governance
  # merge() permet de combiner :
  # - labels génériques (passés en variable)
  # - labels standards imposés par l’architecture
  labels = merge(
    var.labels,
    {
      environment = var.environment
      layer       = "raw"
    }
  )
}
