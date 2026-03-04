##############################################################################
# terraform/lakehouse/envs/staging/terraform.tfvars
##############################################################################

project_id    = "lakehouse-486419"
environment   = "staging"
region        = "europe-west1"

labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
  env         = "staging"
}

domain       = "sales"
dataset_name = "sample"

curated_iceberg_dataset_id = "curated_iceberg_staging"
enable_tmp_dataset         = true

enable_sales_orders_external_tables = true

raw_external_tables = {
  sample_ext = {
    source_format = "PARQUET"
    source_uris   = ["gs://lakehouse-486419-raw-staging/domain=sales/dataset=sample/*"]
  }
}

dataform_repository_name          = "lakehouse-staging-dataform"
dataform_enable_git               = true
dataform_git_repo_url             = "https://github.com/alexfokam-debug/GCP-Lakehouse-From-Scratch.git"
dataform_default_branch           = "main"
dataform_git_token_secret_version = "projects/518653594867/secrets/dataform-git-token/versions/latest"

dataform_workflow_cron = "0 7 * * 1-5"
dataform_time_zone     = "Europe/Paris"
dataform_sa_email      = "sa-dataform-staging@lakehouse-486419.iam.gserviceaccount.com"

enable_curated_external_tables = false
curated_external_tables        = {}