output "lake_name" {
  description = "Full resource name of the Dataplex lake"
  value       = google_dataplex_lake.this.name
}

output "raw_zone_name" {
  description = "Full resource name of RAW zone"
  value       = google_dataplex_zone.raw.name
}

output "curated_zone_name" {
  description = "Full resource name of CURATED zone"
  value       = google_dataplex_zone.curated.name
}