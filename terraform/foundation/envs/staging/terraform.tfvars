##############################################################################
# terraform/foundation/envs/staging/terraform.tfvars
# STAGING dans le MÊME PROJET (on isole via suffixes env + backend prefixes)
##############################################################################

project_id  = "lakehouse-486419"
environment = "staging"
region      = "europe-west1"

labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
  env         = "staging"
}

github_repository    = "alexfokam-debug/GCP-Lakehouse-From-Scratch"
tf_state_bucket_name = "lakehouse-terraform-states-486419"

bootstrap_ci_iam = false
manage_wif       = true

# ✅ Autorise les PR (refs/pull/...) dans la condition WIF
allow_pull_request = true