output "dataform_service_account_email" {
  description = "Email of the Dataform execution service account"
  value       = google_service_account.dataform.email
}

output "github_wif_provider" {
  description = "Full resource name of the GitHub WIF provider"
  value       = try(google_iam_workload_identity_pool_provider.github[0].name, null)
}

output "github_cicd_sa_email" {
  description = "Service account email used by GitHub Actions"
  value       = google_service_account.github_cicd.email
}
