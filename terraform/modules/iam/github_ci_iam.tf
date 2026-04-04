###############################################################################
# github_ci_iam.tf — IAM pour GitHub CI/CD
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Ce fichier gère uniquement les bindings IAM liés à GitHub CI/CD :
# - accès éventuel au bucket backend Terraform
# - accès éventuel au secret Git Dataform
# - rôles projet nécessaires au service account GitHub CI/CD
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Le service account `github_cicd` n'est PAS créé ici.
# Il est supposé être créé dans `github_wif.tf`.
#
# Donc ici :
# - on ne crée pas le SA
# - on lui attribue seulement des permissions IAM
#
# PROBLÈME INITIAL CORRIGÉ
# -----------------------------------------------------------------------------
# Avant :
# - certaines ressources GitHub CI/CD se créaient même quand on appelait
#   le module IAM depuis `lakehouse`, alors que `lakehouse` ne doit PAS gérer
#   GitHub / WIF / bootstrap CI
#
# Maintenant :
# - tout ce fichier est protégé par `local.github_enabled`
# - si `manage_wif = false` :
#   => aucune ressource GitHub CI/CD ne se crée
#
# PHILOSOPHIE
# -----------------------------------------------------------------------------
# Deux niveaux de contrôle :
#
# (1) Activation globale GitHub CI/CD / WIF
#     -> pilotée par `var.manage_wif`
#
# (2) Bootstrap backend / secret
#     -> piloté par `var.bootstrap_ci_iam`
#     -> utile seulement dans foundation
#
# Donc :
# - `manage_wif = false`  => aucune ressource GitHub/WIF
# - `manage_wif = true`
#   + `bootstrap_ci_iam = false` => rôles projet oui, bootstrap backend non
# - `manage_wif = true`
#   + `bootstrap_ci_iam = true`  => rôles projet + bootstrap backend/secret
###############################################################################

###############################################################################
# LOCALS — GARDES DE SÉCURITÉ / ACTIVATION CONDITIONNELLE
###############################################################################
locals {
  # ---------------------------------------------------------------------------
  # Flag global d'activation GitHub / WIF
  # ---------------------------------------------------------------------------
  # Si false :
  # - on ne crée aucun binding IAM GitHub
  # - on ne touche pas au SA GitHub
  # - on ne bootstrap pas le backend
  #
  # C'est exactement ce qu'on veut dans le root module `lakehouse`.
  # ---------------------------------------------------------------------------
  github_enabled = var.manage_wif

  # ---------------------------------------------------------------------------
  # Repository GitHub effectif
  # ---------------------------------------------------------------------------
  # On ne le calcule que si :
  # - manage_wif = true
  # - github_repository est non null
  # - github_repository n'est pas vide
  #
  # Sinon => null
  # ---------------------------------------------------------------------------
  github_repository_effective = (
    var.manage_wif &&
    var.github_repository != null &&
    trimspace(var.github_repository) != ""
  ) ? var.github_repository : null

  # ---------------------------------------------------------------------------
  # Owner GitHub effectif
  # ---------------------------------------------------------------------------
  # Si l'utilisateur n'a pas fourni github_repository_owner, on l'infère depuis
  # owner/repo.
  #
  # Cette valeur n'est calculée que si GitHub est activé.
  # ---------------------------------------------------------------------------
  github_repository_owner_effective = (
    local.github_enabled
    ? coalesce(var.github_repository_owner, split("/", local.github_repository_effective)[0])
    : null
  )

  # ---------------------------------------------------------------------------
  # Flag bootstrap backend / secret
  # ---------------------------------------------------------------------------
  # Le bootstrap n'est autorisé que si :
  # - GitHub/WIF est activé globalement
  # - bootstrap_ci_iam = true
  #
  # Cela évite de créer des bindings backend inutiles dans `lakehouse`.
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
# - manipuler le backend Terraform (bucket state)
# - lire le secret du token Git Dataform
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Ces ressources ne doivent exister que si :
# - GitHub/WIF est activé
# - ET bootstrap_ci_iam = true
#
# Donc `count = local.github_bootstrap_enabled ? 1 : 0`
# =============================================================================

# -----------------------------------------------------------------------------
# Accès objets sur le bucket de state Terraform
# -----------------------------------------------------------------------------
# Permet au SA GitHub CI/CD de :
# - lire le state
# - écrire le state
# - mettre à jour les objets du backend
# -----------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "github_tf_backend_object_admin" {
  count  = local.github_bootstrap_enabled ? 1 : 0
  bucket = var.tf_state_bucket_name
  role   = "roles/storage.objectAdmin"

  # IMPORTANT :
  # Le SA github_cicd a très probablement un `count = 1` dans github_wif.tf
  # lorsqu'il est activé.
  # Donc ici on référence bien `[0]`.
  member = "serviceAccount:${google_service_account.github_cicd[0].email}"
}

# -----------------------------------------------------------------------------
# Lecture metadata bucket
# -----------------------------------------------------------------------------
# Permet la lecture des métadonnées de bucket nécessaires dans certains contextes
# backend GCS.
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
# Permet à GitHub CI/CD de lire le token Git utilisé côté Dataform
# (si ton pipeline doit l'utiliser).
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
# Donner au SA GitHub CI/CD les rôles nécessaires pour piloter Terraform depuis
# GitHub Actions.
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Ces rôles ne dépendent PAS du bootstrap backend.
# Ils dépendent uniquement du fait que GitHub/WIF soit activé.
#
# Donc `count = local.github_enabled ? 1 : 0`
#
# REMARQUE
# -----------------------------------------------------------------------------
# Ces rôles sont puissants.
# C'est acceptable pour un lab / projet perso structuré.
# En entreprise, on viserait souvent une séparation plus fine des permissions.
# =============================================================================

# -----------------------------------------------------------------------------
# BigQuery Admin
# -----------------------------------------------------------------------------
# Permet au pipeline Terraform de créer / modifier :
# - datasets
# - tables
# - connexions BigQuery
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
# Permet au pipeline Terraform de gérer :
# - buckets
# - IAM buckets
# - objets si nécessaire
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
# Permet au pipeline Terraform de gérer des bindings IAM projet / ressources.
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
# Permet au pipeline d'utiliser / attacher certains service accounts.
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
# Permet au pipeline de gérer :
# - repository Dataform
# - workflow configs
# - release configs
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
# Permet au pipeline de créer / modifier :
# - lakes
# - zones
# - assets
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
# Permet au pipeline de gérer certains secrets si nécessaire.
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
# À n'activer que si tu veux que le pipeline CI/CD gère lui-même le pool/provider
# WIF. Souvent désactivé par défaut.
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
# - planifier les changements
# - créer / mettre à jour les repositories si nécessaire
#
# Sans ce rôle, le refresh Terraform peut échouer avec :
# artifactregistry.repositories.get denied
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_cicd_artifactregistry_admin" {
  count   = local.github_enabled ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:${google_service_account.github_cicd[0].email}"
}