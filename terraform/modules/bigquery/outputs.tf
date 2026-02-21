# Dataset ID pour l’utiliser ailleurs (SQL, doc, etc.)
output "curated_dataset_id" {
  description = "Dataset id for curated layer"
  value       = google_bigquery_dataset.curated.dataset_id
}

# Connexion BigLake : nom complet utile pour le SQL
output "biglake_connection_name" {
  # Exemple: projects/<project>/locations/EU/connections/biglake_conn_dev
  value = google_bigquery_connection.biglake.name
}

# Service account créé automatiquement par la connexion (très utile pour IAM)
output "biglake_connection_sa" {
  value = google_bigquery_connection.biglake.cloud_resource[0].service_account_id
}

output "tmp_dataset_id" {
  value = google_bigquery_dataset.tmp_lakehouse.dataset_id
}

output "biglake_connection_id" {
  description = "Full BigQuery BigLake connection ID"
  value       = google_bigquery_connection.biglake.id
}
output "enterprise_dataset_id" {
  value = google_bigquery_dataset.enterprise.dataset_id
}