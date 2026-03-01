###############################################################################
# github_ci_iam.tf — IAM pour GitHub CI/CD
# -----------------------------------------------------------------------------
# IMPORTANT :
# - Le SA github_cicd est créé dans github_wif.tf (tu le gardes séparé)
# - Ici on ne fait QUE des bindings IAM sur bucket/secret/projet.
###############################################################################

# =============================================================================
# 1) Bootstrap backend state bucket (uniquement si bootstrap_ci_iam = true)
# =============================================================================

resource "google_storage_bucket_iam_member" "github_tf_backend_object_admin" {
  count  = var.bootstrap_ci_iam ? 1 : 0
  bucket = var.tf_state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_storage_bucket_iam_member" "github_tf_backend_bucket_reader" {
  count  = var.bootstrap_ci_iam ? 1 : 0
  bucket = var.tf_state_bucket_name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_secret_manager_secret_iam_member" "github_cicd_can_read_dataform_git_token" {
  count     = var.bootstrap_ci_iam ? 1 : 0
  project   = var.project_id
  secret_id = var.git_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.github_cicd.email}"
}

# =============================================================================
# 2) Rôles projet — "least privilege" pour Terraform via GitHub Actions
# -----------------------------------------------------------------------------
# NOTE :
# - Ces rôles sont puissants. C'est OK pour un lab.
# - En entreprise tu passerais par une policy plus fine.
# =============================================================================

resource "google_project_iam_member" "github_cicd_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_project_iam_member" "github_cicd_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_project_iam_member" "github_cicd_iam_admin" {
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_project_iam_member" "github_cicd_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_project_iam_member" "github_cicd_dataform_admin" {
  project = var.project_id
  role    = "roles/dataform.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_project_iam_member" "github_cicd_dataplex_admin" {
  project = var.project_id
  role    = "roles/dataplex.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_project_iam_member" "github_cicd_secret_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

resource "google_project_iam_member" "github_cicd_wif_pool_admin" {
  count   = var.enable_github_cicd_wif_pool_admin ? 1 : 0
  project = var.project_id
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}