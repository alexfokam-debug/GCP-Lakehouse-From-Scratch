# ============================================================
# github_wif.tf — Workload Identity Federation (GitHub -> GCP)
# ============================================================
# OBJECTIF :
# - Authentifier GitHub Actions sur GCP SANS clé JSON (OIDC/WIF)
#
# CE FICHIER = UNIQUEMENT :
# - Workload Identity Pool + Provider (si manage_wif=true)
# - Service Account GitHub CI/CD
# - Binding "roles/iam.workloadIdentityUser" (impersonation)
#
# IMPORTANT :
# - AUCUN rôle projet (editor, securityAdmin, etc.) ici.
# - Les rôles CI/CD sont gérés dans github_ci_iam.tf (plus lisible et pilotable).
# ============================================================

# ------------------------------------------------------------
# 1) Workload Identity Pool (conteneur d'identités externes)
# ------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  count    = var.manage_wif ? 1 : 0
  provider = google-beta

  project = var.project_id

  workload_identity_pool_id = "github-pool-${var.environment}"
  display_name              = "GitHub Pool (${var.environment})"
  description               = "OIDC pool for GitHub Actions (${var.environment})"
}

# ------------------------------------------------------------
# 2) Provider OIDC GitHub (déclare la confiance GitHub -> GCP)
# ------------------------------------------------------------
resource "google_iam_workload_identity_pool_provider" "github" {
  count    = var.manage_wif ? 1 : 0
  provider = google-beta

  project                   = var.project_id
  workload_identity_pool_id = google_iam_workload_identity_pool.github[0].workload_identity_pool_id

  workload_identity_pool_provider_id = "github-provider-${var.environment}"
  display_name                       = "GitHub Provider (${var.environment})"
  description                        = "OIDC provider for GitHub Actions"

  # Issuer OIDC de GitHub Actions
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Mapping claims GitHub -> attributs GCP
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
    "attribute.workflow"   = "assertion.workflow"
  }

  # Condition d'accès "prod-grade"
  # - repo exact
  # - branche main
  attribute_condition = "attribute.repository == \"${var.github_repository}\" && attribute.ref == \"refs/heads/main\""
}

# ------------------------------------------------------------
# 3) Service Account dédié GitHub CI/CD
# ------------------------------------------------------------
resource "google_service_account" "github_cicd" {
  project      = var.project_id
  account_id   = "sa-github-cicd-${var.environment}"
  display_name = "GitHub CI/CD SA (${var.environment})"
}

# ------------------------------------------------------------
# 4) Autoriser GitHub (WIF) à impersonate le SA
# ------------------------------------------------------------
resource "google_service_account_iam_member" "github_cicd_wif" {
  count = var.manage_wif ? 1 : 0

  service_account_id = google_service_account.github_cicd.name
  role               = "roles/iam.workloadIdentityUser"

  # Autorise uniquement les identités WIF du repo exact
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github[0].name}/attribute.repository/${var.github_repository}"
}