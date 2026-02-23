# ============================================================
# github_wif.tf — Workload Identity Federation (GitHub -> GCP)
# ============================================================
# OBJECTIF :
# - Permettre à GitHub Actions de s'authentifier sur GCP SANS clé JSON
#
# CONCEPT :
# - GitHub émet un jeton OIDC (OpenID Connect)
# - GCP vérifie ce jeton via un "Workload Identity Provider"
# - Si tout est OK, GCP donne un access token temporaire
# - GitHub peut alors "impersonate" (agir en tant que) un Service Account
#
# SECURITE :
# - On filtre strictement le repo autorisé via var.github_repository
# - On évite tout secret long terme dans GitHub
# ============================================================

# ------------------------------------------------------------
# 1) Workload Identity Pool
# ------------------------------------------------------------
# Un "pool" = conteneur logique des identités externes
# Ici : identités issues de GitHub Actions
resource "google_iam_workload_identity_pool" "github" {
  provider = google-beta

  # Projet GCP où créer le pool
  project = var.project_id

  # ID unique du pool (dans le projet)
  # On inclut l'environnement pour éviter collisions dev/stg/prd
  workload_identity_pool_id = "github-pool-${var.environment}"

  # Libellés (lisibles dans la console)
  display_name = "GitHub Pool (${var.environment})"

  # Description (gouvernance)
  description = "OIDC pool for GitHub Actions (${var.environment})"
}

# ------------------------------------------------------------
# 2) Workload Identity Provider (OIDC GitHub)
# ------------------------------------------------------------
# Le provider dit à GCP :
# - "Je fais confiance à l'issuer OIDC GitHub"
# - "Voici comment mapper les claims GitHub"
# - "Voici la condition de sécurité : seul ce repo est autorisé"
resource "google_iam_workload_identity_pool_provider" "github" {
  provider = google-beta

  project                   = var.project_id
  workload_identity_pool_id = google_iam_workload_identity_pool.github.workload_identity_pool_id

  # ID unique du provider (dans le pool)
  workload_identity_pool_provider_id = "github-provider-${var.environment}"

  display_name = "GitHub Provider (${var.environment})"
  description  = "OIDC provider for GitHub Actions"

  # ----------------------------------------------------------
  # OIDC issuer : GitHub Actions
  # ----------------------------------------------------------
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # ----------------------------------------------------------
  # Mapping des claims OIDC -> attributs GCP
  # ----------------------------------------------------------
  # google.subject : identifiant unique de l'identité externe
  # attribute.repository : ex "owner/repo"
  # attribute.ref : ex "refs/heads/main" (utile pour filtrer main)
  # attribute.actor : utilisateur GitHub déclencheur
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }
  # CONDITION “prod-grade”
  # On n'autorise l'émission de credential QUE si :
  # - le workflow vient du repo exact (owner/repo)
  # - ET la ref est la branche main (évite les branches non maîtrisées)
  #
  # Important:
  # - assertion.repository = "owner/repo"
  # - assertion.ref        = "refs/heads/main" (pour un push main)
  attribute_condition = join(" && ", [
    "attribute.repository == \"${var.github_repository}\"",
  "attribute.ref == \"refs/heads/main\""])
}

# ------------------------------------------------------------
# 3) Service Account dédié CI/CD
# ------------------------------------------------------------
# Ce SA sera "utilisé" par GitHub Actions via impersonation.
# Ici on le crée dans le module IAM (propre et reproductible).
resource "google_service_account" "github_cicd" {
  project = var.project_id

  # account_id = nom technique (sans @)
  account_id = "sa-github-cicd-${var.environment}"

  display_name = "GitHub CI/CD SA (${var.environment})"
}

# ------------------------------------------------------------
# 4) Autoriser GitHub (WIF) à impersonate ce SA
# ------------------------------------------------------------
# C’est LE lien entre :
# - l’identité externe (GitHub OIDC)
# - et le Service Account GCP
#
# rôle : roles/iam.workloadIdentityUser
# member : principalSet:// ... (tout ce qui match repository)
resource "google_service_account_iam_member" "github_cicd_wif" {
  service_account_id = google_service_account.github_cicd.name
  role               = "roles/iam.workloadIdentityUser"

  # ----------------------------------------------------------
  # principalSet = ensemble d'identités dans le pool
  # On filtre sur attribute.repository = var.github_repository
  # ----------------------------------------------------------
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# ------------------------------------------------------------
# 5) Permissions projet (MVP)
# ------------------------------------------------------------
# Pour aller vite en sandbox : roles/editor
# En entreprise : tu réduiras ensuite (BigQuery, Storage, Dataform, IAM…)
resource "google_project_iam_member" "github_cicd_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}

# ------------------------------------------------------------
# 6) Optionnel : droits IAM plus élevés pour Terraform
# ------------------------------------------------------------
# Certains modules IAM peuvent nécessiter des droits IAM.
# Si tu veux minimiser : tu pourras remplacer par roles/iam.admin ciblé.
resource "google_project_iam_member" "github_cicd_security_admin" {
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd.email}"
}