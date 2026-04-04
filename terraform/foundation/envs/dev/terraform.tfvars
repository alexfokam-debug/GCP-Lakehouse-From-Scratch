##############################################################################
# terraform/foundation/envs/dev/terraform.tfvars
# -----------------------------------------------------------------------------
# STACK : FOUNDATION (SOCLE)
#
# Contient UNIQUEMENT :
# - project_id / region / environment
# - labels globaux
# - GitHub Workload Identity Federation (WIF)
# - bucket de state Terraform (backend)
# - flags de bootstrap IAM CI/CD
#
# IMPORTANT :
# - AUCUNE variable "data" ici (domain, datasets, dataform, external tables, etc.)
##############################################################################

# ---------------------------------------------------------------------------
# (1) Projet GCP cible
# ---------------------------------------------------------------------------
project_id = "lakehouse-486419"

# ---------------------------------------------------------------------------
# (2) Environnement logique
# ---------------------------------------------------------------------------
environment = "dev"

# ---------------------------------------------------------------------------
# (3) Région par défaut
# ---------------------------------------------------------------------------
region = "europe-west1"

# ---------------------------------------------------------------------------
# (4) Labels globaux (gouvernance / FinOps)
# ---------------------------------------------------------------------------
labels = {
  owner       = "alex"
  platform    = "lakehouse"
  cost_center = "data"
}

# ---------------------------------------------------------------------------
# (5) GitHub repository autorisé dans WIF (format owner/repo)
# ---------------------------------------------------------------------------
github_repository = "alexfokam-debug/GCP-Lakehouse-From-Scratch"

# ---------------------------------------------------------------------------
# (6) Bucket GCS de remote state Terraform
# ---------------------------------------------------------------------------
tf_state_bucket_name = "lakehouse-terraform-states-486419"

# ---------------------------------------------------------------------------
# (7) Flags sécurité / bootstrap CI
# ---------------------------------------------------------------------------
# true  -> Terraform attribue automatiquement les droits CI/CD sur bucket state / secrets (bootstrap)
# false -> aucun droit automatique (mode safe)
bootstrap_ci_iam = false

# true  -> Terraform gère le pool+provider WIF
# false -> WIF géré ailleurs (org/platform)
manage_wif = true

# Optionnel (à éviter sauf besoin explicite)
allow_pull_request = true

# ---------------------------------------------------------------------------
# Accès utilisateur humain pour build local (Cloud Build / Artifact Registry)
# ---------------------------------------------------------------------------
enable_human_build_access = true
human_user_email          = "alexbertrand.takoukamfokam@mel.lincoln.fr"

# ---------------------------------------------------------------------------
# Service account utilisé par Cloud Build
# ---------------------------------------------------------------------------
enable_cloud_build_runtime_access = true
cloud_build_service_account_email = "518653594867-compute@developer.gserviceaccount.com"

enable_lakehouse_runtimes = false
