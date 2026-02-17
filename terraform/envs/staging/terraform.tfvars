##############################################################################
# =============================================================================
# ENV FILE (STAGING) — MODE « GRAND GROUPE / MULTI-PROJECT »
# -----------------------------------------------------------------------------
# En STAGING, on garde exactement la même structure que DEV.
# Seules les valeurs "d'environnement" changent :
#   - project_id
#   - environment
#   - buckets/datasets suffixés stg
# =============================================================================
##############################################################################

# ---------------------------------------------------------------------------
# Identité / localisation
# ---------------------------------------------------------------------------
project_id   = "lakehouse-stg-486419"
environment  = "staging"
region       = "europe-west1"
domain       = "sales"
dataset_name = "sample"

# ---------------------------------------------------------------------------
# Labels de gouvernance (FinOps / ownership)
# ---------------------------------------------------------------------------
labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
}

# ---------------------------------------------------------------------------
# External tables RAW (BigQuery) - lecture depuis GCS (zone raw)
# ---------------------------------------------------------------------------
raw_external_tables = {
  sample_ext = {
    source_format = "PARQUET"

    # Pattern GCS : bucket raw staging
    source_uris = [
      "gs://lakehouse-stg-486419-raw-staging/domain=sales/dataset=sample/*"
    ]

    hive_source_prefix       = "gs://lakehouse-stg-486419-raw-staging/domain=sales/dataset=sample/"
    require_partition_filter = false
  }
}

# ---------------------------------------------------------------------------
# Dataform (repo + secret token)
# ---------------------------------------------------------------------------
dataform_git_repo_url     = "https://github.com/alexfokam-debug/GCP-Lakehouse-From-Scratch.git"
dataform_default_branch   = "main"

# Stratégie actuelle : secret centralisé (projet 518653594867)
# (Tu peux dupliquer le secret dans stg/prd plus tard)
dataform_git_token_secret_version = "projects/518653594867/secrets/dataform-git-token/versions/latest"

# ---------------------------------------------------------------------------
# CURATED BigLake tables (Iceberg) - externes optionnelles
# ---------------------------------------------------------------------------
enable_curated_external_tables = false
curated_external_tables = {
  customer = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-stg-486419-curated-stg/domain=sales/dataset=sample/iceberg/customer/"
    ]
    autodetect = false
  }

  orders = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-stg-486419-curated-stg/domain=sales/dataset=sample/iceberg/orders/"
    ]
    autodetect = false
  }
}

# ---------------------------------------------------------------------------
# Dataset Iceberg dédié (BigQuery)
# ---------------------------------------------------------------------------
curated_iceberg_dataset_id = "curated_iceberg_stg"

# SA Dataproc dans le projet STG
dataproc_sa_email = "sa-dataproc-staging@lakehouse-stg-486419.iam.gserviceaccount.com"

# ---------------------------------------------------------------------------
# TMP dataset (Dataproc/BigQuery connector)
# ---------------------------------------------------------------------------
enable_tmp_dataset = true

# ---------------------------------------------------------------------------
# Variable normalisée (si ton code/modules utilisent var.env)
# ---------------------------------------------------------------------------
env = "staging"

enable_samples = true

project_id_short = "486419"