##############################################################################
# =============================================================================
# ENV FILE (DEV) — MODE « GRAND GROUPE / MULTI-PROJECT »
# -----------------------------------------------------------------------------
# Dans un setup entreprise réaliste (Option B), chaque environnement vit dans
# *son propre projet GCP* :
#   - DEV     -> project_id dédié (ex: lakehouse-dev-xxxxx)
#   - STAGING -> project_id dédié (ex: lakehouse-stg-xxxxx)
#   - PROD    -> project_id dédié (ex: lakehouse-prd-xxxxx)
#
# Ce fichier reste identique en structure entre environnements.
# La différence se fait via : project_id + environment (+ éventuellement region).
# =============================================================================
##############################################################################
project_id   = "lakehouse-486419"
environment  = "dev"
region       = "europe-west1"
domain       = "sales"
dataset_name = "sample"

labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
}

raw_external_tables = {
  sample_ext = {
    source_format = "PARQUET"
    source_uris = [
      "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sample/*"
    ]
    hive_source_prefix       = "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sample/"
    require_partition_filter = false
  }

  orders = {
    source_format = "PARQUET"
    source_uris = [
      "gs://lakehouse-486419-raw-dev/domain=sales/dataset=orders/*"
    ]
    hive_source_prefix       = "gs://lakehouse-486419-raw-dev/domain=sales/dataset=orders/"
    require_partition_filter = false
  }

  sales_transactions = {
    source_format = "PARQUET"
    source_uris = [
      "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sales_transactions/*"
    ]
    hive_source_prefix       = "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sales_transactions/"
    require_partition_filter = false
  }
}

dataform_git_repo_url   = "https://github.com/alexfokam-debug/GCP-Lakehouse-From-Scratch.git"
dataform_default_branch = "main"
# NOTE ENTERPRISE (multi-project):
# - Ici, le Secret Manager est dans le projet numéro 518653594867.
# - En Option B (multi-projet), tu as 2 stratégies :
#   (1) Dupliquer le secret dans chaque projet (DEV/STG/PROD) -> plus simple.
#   (2) Garder un projet "shared-secrets" et accorder l'accès au SA Dataform
#       de chaque environnement -> plus centralisé.
# - On garde cette valeur telle quelle pour DEV, puis on décidera pour STG/PROD.
dataform_git_token_secret_version = "projects/518653594867/secrets/dataform-git-token/versions/latest"

# ------------------------------------------------------------
# CURATED BigLake tables (Iceberg)
# ------------------------------------------------------------
enable_curated_external_tables = false
curated_external_tables = {
  # Table "customer"
  customer = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-486419-curated-dev/domain=sales/dataset=sample/iceberg/customer/"
    ]
    autodetect = false
  }

  # Table "orders"
  orders = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-486419-curated-dev/domain=sales/dataset=sample/iceberg/orders/"
    ]
    autodetect = false
  }
}

# =============================================================================
# Dataset Iceberg dédié
# =============================================================================

curated_iceberg_dataset_id = "curated_iceberg_dev"
dataproc_sa_email          = "sa-dataproc-dev@lakehouse-486419.iam.gserviceaccount.com"


# =============================================================================
# TMP dataset (Dataproc/BigQuery connector)
# =============================================================================
enable_tmp_dataset = true

env = "dev"

enable_samples = true

project_id_short = "486419"

dataform_sa_email                   = "sa-dataform-dev@lakehouse-486419.iam.gserviceaccount.com"
dataform_repository_name            = "lakehouse-dev-dataform"
enable_sales_orders_external_tables = true
