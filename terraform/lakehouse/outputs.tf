###############################################################################
# terraform/lakehouse/outputs.tf — ROOT (LAKEHOUSE)
# -----------------------------------------------------------------------------
# Objectif :
# - Exposer uniquement les outputs produits par le stack LAKEHOUSE
# - Interdiction : duplication d'output (un output = un nom unique)
# - Interdiction : output dans main.tf (tout ici)
###############################################################################

# -----------------------------------------------------------------------------
# (1) Buckets GCS
# -----------------------------------------------------------------------------
output "raw_bucket_name" {
  description = "Nom du bucket GCS RAW."
  value       = module.gcs_raw.bucket_name
}

output "curated_bucket_name" {
  description = "Nom du bucket GCS CURATED."
  value       = module.gcs_curated.bucket_name
}

output "iceberg_bucket_name" {
  description = "Nom du bucket GCS ICEBERG."
  value       = module.gcs_iceberg.bucket_name
}

output "dataproc_temp_bucket_name" {
  description = "Nom du bucket GCS DATAPROC TEMP."
  value       = module.gcs_dataproc_temp.bucket_name
}

output "scripts_bucket_name" {
  description = "Nom du bucket GCS SCRIPTS."
  value       = module.gcs_scripts.bucket_name
}

# -----------------------------------------------------------------------------
# (2) BigQuery datasets (créés dans ce root)
# -----------------------------------------------------------------------------
output "analytics_dataset_id" {
  description = "Dataset BigQuery analytics_<env> (sortie Dataform)."
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "raw_external_dataset_id" {
  description = "Dataset BigQuery raw_ext_<env> (external tables RAW)."
  value       = google_bigquery_dataset.raw_external.dataset_id
}

output "curated_external_dataset_id" {
  description = "Dataset BigQuery curated_ext_<env> (external tables curated via BigLake)."
  value       = google_bigquery_dataset.curated_external.dataset_id
}

output "curated_iceberg_dataset_id" {
  description = "Dataset BigQuery dédié Iceberg (managed)."
  value       = google_bigquery_dataset.curated_iceberg.dataset_id
}

# -----------------------------------------------------------------------------
# (3) BigLake connection (créée par module.bq)
# -----------------------------------------------------------------------------
output "biglake_connection_id" {
  description = "BigQuery BigLake connection id."
  value       = module.bq.biglake_connection_id
}

output "biglake_connection_sa" {
  description = "Service account utilisé par la BigLake connection pour accéder à GCS."
  value       = module.bq.biglake_connection_sa
}

# -----------------------------------------------------------------------------
# (4) Dataform
# -----------------------------------------------------------------------------
# Seulement si ton module dataform expose bien repository_name.
# Sinon : supprime cet output ou remplace par le bon output du module.
output "dataform_repository_name" {
  description = "Nom complet du repository Dataform."
  value       = module.dataform.repository_name
}