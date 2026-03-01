###############################################################################
# terraform/foundation/outputs.tf — ROOT (FOUNDATION)
# -----------------------------------------------------------------------------
# Objectif :
# - Exposer uniquement ce qui concerne la fondation :
#   - WIF provider GitHub
#   - Service Account GitHub CI/CD
#
# IMPORTANT :
# - Foundation ne doit PAS exposer des outputs lakehouse (BQ/Dataform/etc).
###############################################################################

# -----------------------------------------------------------------------------
# (1) Email du service account GitHub CI/CD
# -----------------------------------------------------------------------------
# Utilisé par :
# - GitHub Actions (pour savoir quel SA est impersonated)
# - Debug IAM côté GCP
output "github_cicd_sa_email" {
  description = "CI/CD service account email used by GitHub Actions (created in foundation)."
  value       = module.iam.github_cicd_sa_email
}

# -----------------------------------------------------------------------------
# (2) Nom complet du provider WIF GitHub
# -----------------------------------------------------------------------------
# Utilisé dans GitHub Actions :
# - google-github-actions/auth -> workload_identity_provider: <this output>
output "github_wif_provider" {
  description = "Workload Identity Federation provider name to use in GitHub Actions."
  value       = module.iam.github_wif_provider
}