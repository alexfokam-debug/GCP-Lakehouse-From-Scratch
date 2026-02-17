# Nom du bucket créé
# → utile pour chaîner avec d’autres modules
output "bucket_name" {
  description = "Name of the created bucket"
  value       = google_storage_bucket.this.name
}

# URL du bucket (gs://...)
# → très utile pour BigQuery / BigLake
output "bucket_url" {
  description = "GCS URL of the bucket"
  value       = google_storage_bucket.this.url
}

