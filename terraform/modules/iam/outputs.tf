output "dataform_service_account_email" {
  description = "Email of the Dataform execution service account"
  value       = google_service_account.dataform.email
}