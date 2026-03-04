##############################################################################
# terraform/foundation/envs/prod/terraform.tfvars
# PROD dans le MÊME PROJET (pour test mécanique CI/CD)
##############################################################################

project_id   = "lakehouse-486419"
environment  = "prod"
region       = "europe-west1"

labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
  env         = "prod"
}

github_repository    = "alexfokam-debug/GCP-Lakehouse-From-Scratch"
tf_state_bucket_name = "lakehouse-terraform-states-486419"

bootstrap_ci_iam   = false
manage_wif         = true

# ✅ Si tu veux "prod hardening" plus tard :
# - tu mettras allow_pull_request = false en prod
# - et tu garderas les plans PR en lecture seule via un autre mécanisme
allow_pull_request = true