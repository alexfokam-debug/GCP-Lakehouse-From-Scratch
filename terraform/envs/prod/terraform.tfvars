##############################################################################
# =============================================================================
# ENV FILE (PROD) — MODE « GRAND GROUPE / MULTI-PROJECT »
# -----------------------------------------------------------------------------
# PROD = même structure, valeurs PROD.
# =============================================================================
##############################################################################

# ---------------------------------------------------------------------------
# Identité / localisation
# ---------------------------------------------------------------------------
project_id   = "lakehouse-prd-486419"
environment  = "prod"
region       = "europe-west1"
domain       = "sales"
dataset_name = "sample"
project_id_short = "486419"                 # <-- ajouté pour standardiser les noms


# ---------------------------------------------------------------------------
# Labels de gouvernance
# ---------------------------------------------------------------------------
labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
}

# ---------------------------------------------------------------------------
# External tables RAW (BigQuery)
# ---------------------------------------------------------------------------
raw_external_tables = {
  sample_ext = {
    source_format = "PARQUET"

    source_uris = [
      "gs://lakehouse-prd-486419-raw-prd/domain=sales/dataset=sample/*"
    ]

    hive_source_prefix       = "gs://lakehouse-prd-486419-raw-prd/domain=sales/dataset=sample/"
    require_partition_filter = false
  }
}

# ---------------------------------------------------------------------------
# Dataform
# ---------------------------------------------------------------------------
dataform_git_repo_url   = "https://github.com/alexfokam-debug/GCP-Lakehouse-From-Scratch.git"
dataform_default_branch = "main"

dataform_git_token_secret_version = "projects/518653594867/secrets/dataform-git-token/versions/latest"

# ---------------------------------------------------------------------------
# CURATED BigLake tables (Iceberg)
# ---------------------------------------------------------------------------
enable_curated_external_tables = false
curated_external_tables = {
  customer = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-prd-486419-curated-prd/domain=sales/dataset=sample/iceberg/customer/"
    ]
    autodetect = false
  }

  orders = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-prd-486419-curated-prd/domain=sales/dataset=sample/iceberg/orders/"
    ]
    autodetect = false
  }
}

# ---------------------------------------------------------------------------
# Dataset Iceberg dédié
# ---------------------------------------------------------------------------
curated_iceberg_dataset_id = "curated_iceberg_prd"

# SA Dataproc PROD
dataproc_sa_email = "sa-dataproc-prd@lakehouse-prd-486419.iam.gserviceaccount.com"

# ---------------------------------------------------------------------------
# TMP dataset
# ---------------------------------------------------------------------------
enable_tmp_dataset = true

# ---------------------------------------------------------------------------
# var.env (si utilisé)
# ---------------------------------------------------------------------------
env = "prd"
enable_samples = true
# Utilisé dans les noms de buckets:
# lakehouse-<project_id_short>-raw-staging
project_id_short = "486419"