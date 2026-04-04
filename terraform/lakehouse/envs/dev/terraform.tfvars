##############################################################################
# terraform/lakehouse/envs/dev/terraform.tfvars
# -----------------------------------------------------------------------------
# STACK : LAKEHOUSE (DATA PLATFORM)
#
# Contient UNIQUEMENT :
# - domain / dataset_name
# - BigQuery external tables RAW
# - Dataform (repo + secret token)
# - Curated external tables (Iceberg via BigLake)
# - feature flags (tmp dataset, samples, bootstrap files)
#
# IMPORTANT :
# - On ne met PAS ici : github_repository, tf_state_bucket_name, manage_wif, etc.
#   => ça appartient à FOUNDATION
##############################################################################

# ---------------------------------------------------------------------------
# (1) Projet / env / region (le stack lakehouse en a besoin aussi)
# ---------------------------------------------------------------------------
project_id  = "lakehouse-486419"
environment = "dev"
region      = "europe-west1"

# ---------------------------------------------------------------------------
# (2) Labels (optionnel mais pratique pour homogénéité)
# ---------------------------------------------------------------------------
labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
}

# ---------------------------------------------------------------------------
# (3) Domaine métier + dataset logique (paths GCS)
# ---------------------------------------------------------------------------
domain       = "sales"
dataset_name = "sample"

##############################################################################
# RAW external tables (BigQuery external tables sur GCS)
##############################################################################
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

##############################################################################
# DATAFORM (repo + secret token Git)
##############################################################################

# Repo Git Dataform
dataform_git_repo_url = "https://github.com/alexfokam-debug/GCP-Lakehouse-From-Scratch.git"

# Branche par défaut
dataform_default_branch = "main"

# Nom du repository Dataform côté GCP
dataform_repository_name = "lakehouse-dev-dataform"

# Runtime SA Dataform (celui utilisé dans invocation_config.service_account)
dataform_sa_email = "sa-dataform-dev@lakehouse-486419.iam.gserviceaccount.com"

# ---------------------------------------------------------------------------
# Secret Dataform Git token
# ---------------------------------------------------------------------------
# Full path version attendu par l’API Dataform (souvent "latest")
dataform_git_token_secret_version = "projects/lakehouse-486419/secrets/dataform-git-token/versions/latest"
enable_git                        = true
# dataform_git_token_secret_id = "dataform-git-token"

##############################################################################
# CURATED BigLake tables (Iceberg) - optionnel
##############################################################################
enable_curated_external_tables = false

curated_external_tables = {
  customer = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-486419-curated-dev/domain=sales/dataset=sample/iceberg/customer/"
    ]
    autodetect = false
  }

  orders = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-486419-curated-dev/domain=sales/dataset=sample/iceberg/orders/"
    ]
    autodetect = false
  }
}

##############################################################################
# Dataset Iceberg dédié
##############################################################################
curated_iceberg_dataset_id = "curated_iceberg_dev"

##############################################################################
# TMP dataset (Dataproc / BigQuery connector)
##############################################################################
enable_tmp_dataset = true

##############################################################################
# Samples / bootstrap data
##############################################################################
enable_samples = true

# Active les fichiers parquet bootstrap pour éviter "matched no files"
enable_sales_orders_external_tables = true

github_repository    = "alexfokam-debug/GCP-Lakehouse-From-Scratch"
tf_state_bucket_name = "lakehouse-terraform-states-486419"

enable_dataplex = false

##############################################################################
# CURATED prepared external tables (Parquet produits par Dataproc)
##############################################################################
curated_prepared_external_tables = {
  arco_era5_vertical_profile_vo = {
    source_format = "PARQUET"
    source_uris = [
      "gs://lakehouse-486419-curated-dev/domain=weather/dataset=arco_era5/prepared/daily_vertical_profile_vo/*.parquet"
    ]
    autodetect = true
  }
}