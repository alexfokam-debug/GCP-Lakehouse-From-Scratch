# ============================================================
# github_wif.tf — Workload Identity Federation (GitHub -> GCP)
# ============================================================
# OBJECTIF :
# - Authentifier GitHub Actions sur GCP SANS clé JSON (OIDC/WIF)
#
# PRINCIPE :
# - GitHub émet un token OIDC (issuer: token.actions.githubusercontent.com)
# - GCP valide via un Workload Identity Pool + Provider
# - Si la condition passe, GitHub peut "impersonate" un Service Account
#
# SECURITE (DEV "secure") :
# - On filtre STRICTEMENT :
#     1) repository == owner/repo
#     2) ref == refs/heads/main
# - On NE filtre PAS encore sur workflow tant qu’on n’a pas validé
#   la valeur exacte du claim (sinon tu risques un blocage inutile).
# ============================================================

# ------------------------------------------------------------
# 1) Workload Identity Pool (conteneur d'identités externes)
# ------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  provider = google-beta

  # Projet où vit le pool WIF
  project = var.project_id

  # ID du pool (unique dans le projet)
  workload_identity_pool_id = "github-pool-${var.environment}"

  # Nom lisible dans la console
  display_name = "GitHub Pool (${var.environment})"

  # Description
  description = "OIDC pool for GitHub Actions (${var.environment})"
}

# ------------------------------------------------------------
# 2) Provider OIDC GitHub (déclare la confiance GitHub -> GCP)
# ------------------------------------------------------------
resource "google_iam_workload_identity_pool_provider" "github" {
  provider = google-beta

  # Projet + pool
  project                   = var.project_id
  workload_identity_pool_id = google_iam_workload_identity_pool.github.workload_identity_pool_id

  # ID du provider (unique dans le pool)
  workload_identity_pool_provider_id = "github-provider-${var.environment}"

  # Nom lisible
  display_name = "GitHub Provider (${var.environment})"
  description  = "OIDC provider for GitHub Actions"

  # -------------------------
  # Issuer OIDC GitHub
  # -------------------------
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # -------------------------
  # Mapping claims GitHub -> attributs GCP
  # -------------------------
  # IMPORTANT :
  # - "attribute.repository" est la base pour filtrer owner/repo
  # - "attribute.ref" permet de filtrer sur la branche main
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
    "attribute.workflow"   = "assertion.workflow"
  }

  # -------------------------
  # CONDITION "prod-grade" (fiable)
  # -------------------------
  # On autorise uniquement :
  # - le repo exact
  # - la branche main
  #
  # Simple, robuste, évite 95% des erreurs.
  # (On ajoutera la contrainte workflow après vérif du claim)
  attribute_condition = "attribute.repository == \"${var.github_repository}\" && attribute.ref == \"refs/heads/main\""
}

# ------------------------------------------------------------
# 3) Service Account dédié GitHub CI/CD
# ------------------------------------------------------------
resource "google_service_account" "github_cicd" {
  project = var.project_id

  # Nom technique (sans @)
  account_id = "sa-github-cicd-${var.environment}"

  # Nom lisible
  display_name = "GitHub CI/CD SA (${var.environment})"
}

# ------------------------------------------------------------
# 4) Autoriser GitHub (WIF) à impersonate le SA
# ------------------------------------------------------------
resource "google_service_account_iam_member" "github_cicd_wif" {
  # SA cible
  service_account_id = google_service_account.github_cicd.name

  # Rôle OBLIGATOIRE pour WIF
  role = "roles/iam.workloadIdentityUser"

  # Groupe d'identités autorisées (principalSet) filtré sur repo
  # => Seuls les tokens dont attribute.repository == owner/repo passent
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# ------------------------------------------------------------
# 5) Permissions projet (DEV sécurisé)
# ------------------------------------------------------------
#  Pour DEV, tu peux garder roles/editor pour aller vite.
#  Mais en "secure dev", je conseille de le mettre derrière un flag.
#    (sinon tu donnes trop de pouvoir au pipeline)
resource "google_project_iam_member" "github_cicd_editor" {
  count   = var.bootstrap_ci_iam ? 1 : 0
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# ------------------------------------------------------------
# 6) Permissions IAM élevées (OPTIONNEL / à éviter en prod)
# ------------------------------------------------------------
# Pareil : uniquement si bootstrap_ci_iam = true, sinon OFF.
resource "google_project_iam_member" "github_cicd_security_admin" {
  count   = var.bootstrap_ci_iam ? 1 : 0
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}