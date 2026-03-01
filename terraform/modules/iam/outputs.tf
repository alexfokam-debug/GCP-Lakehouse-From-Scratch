###############################################################################
# outputs.tf — Module IAM
# -----------------------------------------------------------------------------
# But :
# - Exposer les infos utiles (WIF + SA CI/CD + runtimes)
#
# Attention "count" :
# - github_wif_provider : a un count => on garde [0] avec try(...)
# - dataform : a un count => on garde [0] avec try(...)
# - dataproc_runtime : PAS de count => PAS de [0]
###############################################################################

# =============================================================================
# GitHub CI/CD (toujours créé)
# =============================================================================
output "github_cicd_sa_email" {
  description = "Email du service account utilisé par GitHub Actions."
  value       = google_service_account.github_cicd.email
}

output "github_wif_provider" {
  description = "Nom complet du provider WIF GitHub (utilisé dans GitHub Actions)."
  value       = try(google_iam_workload_identity_pool_provider.github[0].name, null)
}

# =============================================================================
# Lakehouse runtimes
# -----------------------------------------------------------------------------
# Remarque :
# - dataform est conditionné via count => index [0]
# - dataproc_runtime n'est PAS conditionné via count => pas d'index
# =============================================================================
output "dataproc_runtime_sa_email" {
  value       = try(google_service_account.dataproc_runtime[0].email, null)
  description = "Email SA Dataproc runtime (null si non créé)."
}

output "dataform_runtime_sa_email" {
  value       = try(google_service_account.dataform[0].email, null)
  description = "Email SA Dataform runtime (null si non créé)."
}