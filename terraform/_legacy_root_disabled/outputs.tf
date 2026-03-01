# ============================================================
# outputs.tf (ROOT) — Remonter outputs du module IAM
# ============================================================

output "github_wif_provider" {
  description = "WIF provider name to use in GitHub Actions"
  value       = module.iam.github_wif_provider
}

output "github_cicd_sa_email" {
  description = "CI/CD service account used by GitHub Actions"
  value       = module.iam.github_cicd_sa_email
}