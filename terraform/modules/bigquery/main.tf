# =========================
# Dataset CURATED (Silver)
# =========================
resource "google_bigquery_dataset" "curated" {
  # Dataset ID (sans tirets si tu veux être safe sur tous les outils)
  dataset_id = "curated_${var.environment}"

  # Projet + localisation
  project  = var.project_id
  location = var.location

  # Labels pour gouvernance/FinOps
  labels = merge(
    var.labels,
    {
      environment = var.environment
      layer       = "curated"
    }
  )
}

# ==========================================
# BigQuery Connection (BigLake) - Cloud Resource
# ==========================================
# Cette connexion représente une "identité gérée" par BigQuery
# qui servira à accéder à GCS via BigLake.
resource "google_bigquery_connection" "biglake" {
  project       = var.project_id
  location      = var.location
  connection_id = "biglake_conn_${var.environment}"

  # Cloud Resource = connexion managée pour accès à GCS
  cloud_resource {}
}
resource "google_bigquery_dataset" "tmp_lakehouse" {
  project       = var.project_id
  dataset_id    = "tmp_lakehouse_${var.environment}"
  location      = var.location
  friendly_name = "tmp_lakehouse_${var.environment}"
  description   = "Dataset temporaire pour matérialisation / BigQuery connector (Dataproc Serverless)."

  labels = merge(var.labels, {
    purpose     = "tmp"
    managedby   = "terraform"
    environment = var.environment
  })
}
