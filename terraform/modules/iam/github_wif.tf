###############################################################################
# github_wif.tf — Workload Identity Federation (GitHub -> GCP)
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Authentifier GitHub Actions sur GCP SANS clé JSON, via OIDC + Workload
# Identity Federation (WIF).
#
# CE FICHIER GÈRE UNIQUEMENT :
# - le Workload Identity Pool
# - le Workload Identity Provider
# - le Service Account GitHub CI/CD
# - le binding roles/iam.workloadIdentityUser pour permettre l'impersonation
#
# CE FICHIER NE GÈRE PAS :
# - les rôles projet BigQuery / Storage / IAM / Dataform / Dataplex
# - les accès backend Terraform
# - les accès Secret Manager
#
# Ces sujets sont volontairement séparés dans `github_ci_iam.tf`.
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Ce fichier doit être ACTIF uniquement dans la stack FOUNDATION.
#
# Donc :
# - foundation  -> manage_wif = true
# - lakehouse   -> manage_wif = false
#
# Si manage_wif = false :
# - aucun pool
# - aucun provider
# - aucun SA GitHub
# - aucun binding WIF
#
# IMPORTANT BIS
# -----------------------------------------------------------------------------
# Les locals suivants sont déjà définis dans `github_ci_iam.tf` et sont
# accessibles ici car tous les fichiers appartiennent au même module Terraform :
#
# - local.github_enabled
# - local.github_repository_effective
# - local.github_repository_owner_effective
#
# Donc on NE les redéfinit PAS ici.
###############################################################################

###############################################################################
# 1) WORKLOAD IDENTITY POOL
# -----------------------------------------------------------------------------
# Un pool est le conteneur logique qui héberge des identités externes fédérées.
#
# Ici :
# - source externe = GitHub Actions
# - cible = GCP
#
# On utilise google-beta car certaines ressources WIF ont historiquement été
# exposées plus tôt via ce provider.
###############################################################################
resource "google_iam_workload_identity_pool" "github" {
  # ---------------------------------------------------------------------------
  # Si GitHub/WIF est désactivé, aucune ressource ne doit être créée.
  # En particulier dans le root module lakehouse, manage_wif = false.
  # ---------------------------------------------------------------------------
  count    = local.github_enabled ? 1 : 0
  provider = google-beta

  # Projet GCP cible
  project = var.project_id

  # ID technique stable du pool
  workload_identity_pool_id = "github-pool-${var.environment}"

  # Libellés lisibles dans la console GCP
  display_name = "GitHub Pool (${var.environment})"
  description  = "OIDC pool for GitHub Actions (${var.environment})"

  # Pool explicitement actif
  disabled = false
}

###############################################################################
# 2) WORKLOAD IDENTITY PROVIDER — OIDC GITHUB
# -----------------------------------------------------------------------------
# Ce provider déclare :
# - quel issuer OIDC on accepte
# - comment on mappe les claims GitHub vers des attributs GCP
# - quelle condition de sécurité on applique
###############################################################################
resource "google_iam_workload_identity_pool_provider" "github" {
  # ---------------------------------------------------------------------------
  # Même logique : si GitHub/WIF est désactivé, ce provider ne doit pas exister.
  # ---------------------------------------------------------------------------
  count    = local.github_enabled ? 1 : 0
  provider = google-beta

  # Projet GCP cible
  project = var.project_id

  # Référence au pool créé juste au-dessus
  workload_identity_pool_id = google_iam_workload_identity_pool.github[0].workload_identity_pool_id

  # ID technique stable du provider
  workload_identity_pool_provider_id = "github-provider-${var.environment}"

  # Libellés lisibles
  display_name = "GitHub Provider (${var.environment})"
  description  = "OIDC provider for GitHub Actions (${var.environment})"

  # ---------------------------------------------------------------------------
  # Issuer OIDC officiel de GitHub Actions
  # ---------------------------------------------------------------------------
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # ---------------------------------------------------------------------------
  # Mapping des claims GitHub -> attributs GCP
  # ---------------------------------------------------------------------------
  # Ces mappings permettent ensuite d'écrire des conditions CEL robustes.
  #
  # Exemples utiles :
  # - assertion.repository       -> owner/repo
  # - assertion.ref              -> branche / ref
  # - assertion.actor            -> utilisateur / bot
  # - assertion.workflow         -> nom du workflow
  # - assertion.job_workflow_ref -> workflow exact exécuté
  # ---------------------------------------------------------------------------
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.actor"            = "assertion.actor"
    "attribute.workflow"         = "assertion.workflow"
    "attribute.job_workflow_ref" = "assertion.job_workflow_ref"
  }

  # ---------------------------------------------------------------------------
  # Condition CEL de sécurité
  # ---------------------------------------------------------------------------
  # Objectif sécurité :
  # 1. limiter au repository exact
  # 2. autoriser la branche main
  # 3. optionnellement autoriser les Pull Requests
  #
  # Cas 1 : allow_pull_request = true
  #   - refs/heads/main
  #   - refs/pull/<id>/merge
  #   - refs/pull/<id>/head
  #
  # Cas 2 : allow_pull_request = false
  #   - uniquement refs/heads/main
  #
  # Ici on s'appuie directement sur le local déjà calculé dans github_ci_iam.tf
  # pour éviter toute duplication de logique.
  # ---------------------------------------------------------------------------
  attribute_condition = var.allow_pull_request ? format(
    "attribute.repository == %q && (attribute.ref == %q || attribute.ref.matches(%q))",
    local.github_repository_effective,
    "refs/heads/main",
    "^refs/pull/[0-9]+/(merge|head)$"
    ) : format(
    "attribute.repository == %q && attribute.ref == %q",
    local.github_repository_effective,
    "refs/heads/main"
  )
}

###############################################################################
# 3) SERVICE ACCOUNT DÉDIÉ GITHUB CI/CD
# -----------------------------------------------------------------------------
# Ce SA est la cible d'impersonation depuis GitHub Actions.
#
# IMPORTANT
# -----------------------------------------------------------------------------
# C'était un des problèmes observés :
# - le SA se créait aussi dans lakehouse
#
# Maintenant :
# - count = local.github_enabled ? 1 : 0
# - donc si manage_wif = false, il ne sera PAS créé
###############################################################################
resource "google_service_account" "github_cicd" {
  # ---------------------------------------------------------------------------
  # Création uniquement si GitHub/WIF est activé.
  # ---------------------------------------------------------------------------
  count = local.github_enabled ? 1 : 0

  # Projet GCP cible
  project = var.project_id

  # Convention de nommage stable par environnement
  account_id   = "sa-github-cicd-${var.environment}"
  display_name = "GitHub CI/CD SA (${var.environment})"
}

###############################################################################
# 4) BINDING — AUTORISER GITHUB À IMPERSONATE LE SA
# -----------------------------------------------------------------------------
# Ce binding est le cœur du mécanisme WIF :
# - GitHub obtient un token OIDC
# - GCP vérifie le provider + la condition
# - GitHub peut alors impersonate le SA cible
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Comme le SA a un `count`, on doit référencer :
# - google_service_account.github_cicd[0]
# - google_iam_workload_identity_pool.github[0]
###############################################################################
resource "google_service_account_iam_member" "github_cicd_wif" {
  # ---------------------------------------------------------------------------
  # Binding créé uniquement si GitHub/WIF est activé.
  # ---------------------------------------------------------------------------
  count = local.github_enabled ? 1 : 0

  # Resource ID complet du SA cible
  service_account_id = google_service_account.github_cicd[0].name

  # Rôle standard permettant l'impersonation via WIF
  role = "roles/iam.workloadIdentityUser"

  # ---------------------------------------------------------------------------
  # principalSet autorisé
  # ---------------------------------------------------------------------------
  # On autorise UNIQUEMENT les identités fédérées issues du repository exact.
  #
  # Format attendu :
  # principalSet://iam.googleapis.com/projects/<project-number>/locations/global/
  # workloadIdentityPools/<pool-id>/attribute.repository/<owner/repo>
  #
  # Ici, `.name` du pool contient déjà :
  # projects/<number>/locations/global/workloadIdentityPools/<pool-id>
  #
  # Donc on le réutilise directement.
  # ---------------------------------------------------------------------------
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github[0].name}/attribute.repository/${local.github_repository_effective}"
}