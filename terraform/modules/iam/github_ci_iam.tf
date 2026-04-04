###############################################################################
# github_ci_iam.tf — IAM pour GitHub CI/CD
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Ce fichier gère UNIQUEMENT les bindings IAM liés à GitHub CI/CD :
# - accès éventuel au bucket backend Terraform
# - accès éventuel au secret Git Dataform
# - rôles projet nécessaires au service account GitHub CI/CD
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Le service account `github_cicd` n'est PAS créé ici.
# Il est créé dans `github_wif.tf`.
#
# Donc ici :
# - on ne crée pas le SA
# - on lui attribue seulement des permissions IAM
#
# ARCHITECTURE CIBLE
# -----------------------------------------------------------------------------
# FOUNDATION :
# - manage_wif = true
# - crée le SA GitHub + pool WIF + provider WIF
# - applique les bindings IAM GitHub CI/CD
#
# LAKEHOUSE :
# - manage_wif = false
# - ne doit créer AUCUNE ressource GitHub / WIF / bootstrap backend
#
# CONSÉQUENCE
# -----------------------------------------------------------------------------
# Toutes les ressources de ce fichier sont protégées par des flags calculés
# dans les locals ci-dessous.
###############################################################################

###############################################################################
# LOCALS — GARDES DE SÉCURITÉ / ACTIVATION CONDITIONNELLE
###############################################################################
locals {
  # ---------------------------------------------------------------------------
  # Flag global d'activation GitHub / WIF
  # ---------------------------------------------------------------------------
  github_enabled = var.manage_wif

  # ---------------------------------------------------------------------------
  # Repository GitHub effectif
  # ---------------------------------------------------------------------------
  # IMPORTANT :
  # `trimspace(null)` provoque une erreur Terraform.
  # Donc on sécurise avec coalesce(var.github_repository, "").
  # ---------------------------------------------------------------------------
  github_repository_effective = (
    var.manage_wif &&
    trimspace(coalesce(var.github_repository, "")) != ""
  ) ? var.github_repository : null

  # ---------------------------------------------------------------------------
  # Owner GitHub effectif
  # ---------------------------------------------------------------------------
  github_repository_owner_effective = (
    local.github_enabled && local.github_repository_effective != null
    ? coalesce(var.github_repository_owner, split("/", local.github_repository_effective)[0])
    : null
  )

  # ---------------------------------------------------------------------------
  # Flag bootstrap backend / secret
  # ---------------------------------------------------------------------------
  github_bootstrap_enabled = (
    local.github_enabled &&
    var.bootstrap_ci_iam
  )
}

# =============================================================================
# 1) BOOTSTRAP BACKEND STATE BUCKET + SECRET
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Donner au SA GitHub CI/CD les droits minimum pour :
# - lire/écrire le state Terraform dans le bucket backend
# - lire le secret Git utilisé par Dataform si nécessaire
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Ces ressources ne doivent exister que si :
# - GitHub/WIF est activé
# - ET bootstrap_ci_iam = true
#
# Donc : count = local.github_bootstrap_enabled ? 1 : 0
# =============================================================================

# -----------------------------------------------------------------------------
# Accès objets sur le bucket backend Terraform
# -----------------------------------------------------------------------------
# Permet au SA GitHub CI/CD de :
# - lire le fichier state
# - écrire le fichier state
# - mettre à jour les objets du backend GCS
#
# NOTE IMPORTANTE
# -----------------------------------------------------------------------------
# Ici on référence google_service_account.github_cicd[0].email
# car dans github_wif.tf le service account doit être déclaré avec :
#
# resource "google_service_account" "github_cicd" {
#   count = local.github_enabled ? 1 : 0
#   ...
# }
# -----------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "github_tf_backend_object_admin" {
  count  = local.github_bootstrap_enabled ? 1 : 0
  bucket = var.tf_state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Lecture metadata bucket backend
# -----------------------------------------------------------------------------
# Certaines opérations backend GCS nécessitent aussi de lire les métadonnées
# du bucket lui-même.
# -----------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "github_tf_backend_bucket_reader" {
  count  = local.github_bootstrap_enabled ? 1 : 0
  bucket = var.tf_state_bucket_name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Lecture du secret Git Dataform
# -----------------------------------------------------------------------------
# Permet au SA GitHub CI/CD de lire le secret Git si le pipeline en a besoin.
# -----------------------------------------------------------------------------
resource "google_secret_manager_secret_iam_member" "github_cicd_can_read_dataform_git_token" {
  count     = local.github_bootstrap_enabled ? 1 : 0
  project   = var.project_id
  secret_id = var.git_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# =============================================================================
# 2) RÔLES PROJET — GITHUB CI/CD
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Donner au SA GitHub CI/CD les rôles nécessaires pour piloter Terraform
# depuis GitHub Actions.
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Ces rôles ne dépendent PAS du bootstrap backend.
# Ils dépendent uniquement du fait que GitHub/WIF soit activé.
#
# Donc : count = local.github_enabled ? 1 : 0
# =============================================================================

# -----------------------------------------------------------------------------
# BigQuery Admin
# -----------------------------------------------------------------------------
# Permet à Terraform de gérer datasets, tables, connexions, etc.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_bigquery_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Storage Admin
# -----------------------------------------------------------------------------
# Permet à Terraform de gérer buckets, IAM buckets et objets si nécessaire.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_storage_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# IAM Security Admin
# -----------------------------------------------------------------------------
# Permet de gérer les bindings IAM sur le projet et certaines ressources.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_iam_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/iam.securityAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Service Account User
# -----------------------------------------------------------------------------
# Permet au pipeline d'attacher / utiliser des service accounts existants.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_sa_user" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Dataform Admin
# -----------------------------------------------------------------------------
# Permet de gérer les repositories, release configs, workflow configs, etc.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_dataform_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/dataform.admin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Dataplex Admin
# -----------------------------------------------------------------------------
# Permet de gérer les lakes, zones, assets Dataplex.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_dataplex_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/dataplex.admin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Secret Manager Admin
# -----------------------------------------------------------------------------
# Permet de gérer certains secrets via Terraform si besoin.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_secret_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Workload Identity Pool Admin (option avancée)
# -----------------------------------------------------------------------------
# À activer seulement si tu veux que GitHub CI/CD puisse lui-même gérer
# le pool/provider WIF.
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_wif_pool_admin" {
  count   = (local.github_enabled && var.enable_github_cicd_wif_pool_admin) ? 1 : 0
  project = var.project_id
  role    = "roles/iam.workloadIdentityPoolAdmin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Artifact Registry Admin
# -----------------------------------------------------------------------------
# Permet au pipeline Terraform GitHub CI/CD de :
# - lire les repositories Artifact Registry
# - faire le refresh Terraform sans erreur 403
# - créer / modifier les repositories si nécessaire
#
# C'est précisément ce rôle qui évite les erreurs du type :
# artifactregistry.repositories.get denied
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_artifactregistry_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# =============================================================================
# 3) ACCÈS HUMAIN LOCAL — ARTIFACT REGISTRY (OPTIONNEL)
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Permettre à ton utilisateur humain de :
# - lancer des builds locaux
# - pousser des images Docker
# - lire / gérer les repositories Artifact Registry
#
# REMARQUE
# -----------------------------------------------------------------------------
# Si tu veux être plus restrictif :
# - remplace artifactregistry.admin par artifactregistry.writer
# =============================================================================
resource "google_project_iam_member" "human_artifactregistry_admin" {
  count   = var.enable_human_build_access ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "user:${var.human_user_email}"
}