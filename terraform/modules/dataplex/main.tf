locals {
  lake_name = "lakehouse-${var.environment}"
}

# =====================================================
# Dataplex Lake
# =====================================================
resource "google_dataplex_lake" "this" {
  count = var.enable_dataplex ? 1 : 0

  project  = var.project_id
  location = var.region

  name         = local.lake_name
  display_name = "Lakehouse ${var.environment}"

  labels = var.labels
}

# =====================================================
# RAW Zone (GCS)
# =====================================================
resource "google_dataplex_zone" "raw" {
  count = var.enable_dataplex ? 1 : 0

  project  = var.project_id
  location = var.region

  name = "raw-zone"
  lake = google_dataplex_lake.this.name
  type = "RAW"

  discovery_spec {
    enabled = true
  }

  resource_spec {
    location_type = "SINGLE_REGION"
  }

  labels = var.labels
}

# =====================================================
# CURATED Zone (BigQuery)
# =====================================================
resource "google_dataplex_zone" "curated" {
  count = var.enable_dataplex ? 1 : 0

  project  = var.project_id
  location = var.region

  name = "curated-zone"
  lake = google_dataplex_lake.this.name
  type = "CURATED"

  discovery_spec {
    enabled = true
  }

  resource_spec {
    location_type = "SINGLE_REGION"
  }

  labels = var.labels
}

# =====================================================
# RAW Asset (GCS bucket)
# =====================================================
resource "google_dataplex_asset" "raw_bucket" {
  count = var.enable_dataplex ? 1 : 0

  name          = "raw-gcs"
  lake          = google_dataplex_lake.this.name
  dataplex_zone = google_dataplex_zone.raw.name
  location      = var.region
  project       = var.project_id

  depends_on = [
    google_dataplex_zone.raw
  ]

  resource_spec {
    name = "projects/${var.project_id}/buckets/${var.raw_bucket}"
    type = "STORAGE_BUCKET"
  }

  discovery_spec {
    enabled = true
  }

  labels = var.labels
}

# =====================================================
# CURATED Asset (BigQuery dataset)
# =====================================================
resource "google_dataplex_asset" "curated_bq" {
  count = var.enable_dataplex ? 1 : 0

  name          = "curated-bq"
  lake          = google_dataplex_lake.this.name
  dataplex_zone = google_dataplex_zone.curated.name
  location      = var.region
  project       = var.project_id

  depends_on = [
    google_dataplex_zone.curated
  ]

  resource_spec {
    name = "projects/${var.project_id}/datasets/${var.curated_dataset}"
    type = "BIGQUERY_DATASET"
  }

  discovery_spec {
    enabled = true
  }

  labels = var.labels
}

# =====================================================
# RAW Asset (BigQuery dataset - external tables)
# =====================================================
# Ce dataset (ex: raw_ext_dev) expose les fichiers du data lake (GCS)
# via des tables externes BigQuery. On le catalogue dans Dataplex pour :
# - Découverte (discovery) et métadonnées
# - Gouvernance légère / search / lineage
# - Vision “entreprise” d’un lakehouse (RAW + CURATED)
resource "google_dataplex_asset" "raw_bq_external" {
  count = var.enable_dataplex ? 1 : 0

  name          = "raw-bq-external"
  lake          = google_dataplex_lake.this.name
  dataplex_zone = google_dataplex_zone.raw.name
  location      = var.region
  project       = var.project_id

  depends_on = [
    google_dataplex_zone.raw
  ]

  resource_spec {
    name = "projects/${var.project_id}/datasets/${var.raw_external_dataset}"
    type = "BIGQUERY_DATASET"
  }

  discovery_spec {
    enabled = true
  }

  labels = var.labels
}