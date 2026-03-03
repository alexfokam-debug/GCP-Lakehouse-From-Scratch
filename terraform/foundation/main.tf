/*
================================================================================
FOUNDATION STACK — terraform/foundation/main.tf

Objectif :
- Tout ce qui est “plateforme / sécurité / entreprise” et stable
- Ce qui permet ensuite à Lakehouse de se déployer proprement

Contenu typique :
✅ Activation des APIs (prérequis)
✅ Labels projet “global”
✅ IAM / WIF GitHub CI/CD + Service Accounts (Dataform/Dataproc/GitHub)
✅ Bootstrapping CI : droits sur backend bucket terraform + secrets

Ce que FOUNDATION ne doit PAS contenir :
❌ Datasets BigQuery
❌ Buckets data (raw/curated/iceberg/scripts/temp)
❌ Dataplex lake/zones/assets
❌ Dataform repository/workflows
=> tout ça va dans LAKEHOUSE

Pourquoi ?
- En entreprise : les ressources “org / security / IAM” sont souvent séparées
- Ça évite les cycles et ça isole les changements fréquents (lakehouse)
================================================================================
*/

# =============================================================================
# 0) LOCALS — Naming & conventions (single source of truth)
# =============================================================================
locals {
  # Environnement courant : dev | staging | prod
  env = var.environment

  # Convention de nommage globale
  project_prefix = "lakehouse"

  # Extrait un suffixe "court" depuis le project_id
  # Ex : lakehouse-486419 => 486419
  project_id_short = element(
    split("-", var.project_id),
    length(split("-", var.project_id)) - 1
  )
}

# =============================================================================
# 1) ACTIVER LES APIs (prérequis)
# -----------------------------------------------------------------------------
# Pourquoi dans FOUNDATION ?
# - Ces APIs sont des prérequis transverses.
# - En entreprise, l'activation des APIs est souvent gérée par une couche “platform”.
# =============================================================================
resource "google_project_service" "services" {
  for_each = toset([
    "dataform.googleapis.com",
    "bigquery.googleapis.com",
    "dataplex.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "dataproc.googleapis.com",
    "compute.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# =============================================================================
# 2) LABELS PROJET (FinOps / gouvernance)
# -----------------------------------------------------------------------------
# Pourquoi ici ?
# - Les labels projet sont globaux, pas spécifiques au lakehouse.
# - Garder ces labels dans foundation évite les changements à chaque refacto lakehouse.
# =============================================================================
module "project_labels" {
  source     = "../modules/project_labels"
  project_id = var.project_id

  labels = {
    environment = var.environment
    system      = "gcp-lakehouse"
    managed_by  = "terraform"
    repository  = "gcp-lakehouse-from-scratch"
    owner       = "alexfokam"
    cost_center = "lab"
  }
}

# =============================================================================
# 3) IAM / WIF / CI Bootstrap (Module IAM)
# -----------------------------------------------------------------------------
# Objectif :
# - Créer / gérer la partie “security & access” (CI/CD GitHub, Dataform, Dataproc)
# - Centraliser l’IAM pour éviter les doublons au root et le drift

# Note clé :
# Dans ton root initial, ton module IAM recevait des buckets/datasets issus
# de lakehouse. Ça crée une dépendance FOUNDATION -> LAKEHOUSE.
#
# Pour respecter la séparation :
# - FOUNDATION ne doit pas avoir besoin des buckets/datasets.
# - Donc dans foundation, on active UNIQUEMENT la partie WIF/CI + accès secret/backend,
#   et on laisse les bindings bucket/datasets au lakehouse.
#
# => Concrètement :
# - Dans ton module IAM, il faut supporter un mode “foundation_only”
#   où il ne requiert pas raw_bucket_name, curated_dataset_id, etc.
#
# Si tu ne veux pas modifier le module tout de suite :
# - Tu peux mettre IAM dans lakehouse temporairement,
# - ou bien passer des strings dummy et désactiver les bindings via flags.
# =============================================================================

###############################################################################
# MODULE IAM — FOUNDATION MODE
###############################################################################

module "iam" {
  source = "../modules/iam"

  # ---------------------------------------------------------------------------
  # Common
  # ---------------------------------------------------------------------------
  project_id  = var.project_id
  environment = var.environment


  # ---------------------------------------------------------------------------
  # GitHub / WIF
  # ---------------------------------------------------------------------------
  github_repository                 = var.github_repository
  manage_wif                        = var.manage_wif
  enable_github_cicd_wif_pool_admin = var.enable_github_cicd_wif_pool_admin

  # ---------------------------------------------------------------------------
  # CI bootstrap (backend state bucket uniquement)
  # ---------------------------------------------------------------------------
  bootstrap_ci_iam     = var.bootstrap_ci_iam
  tf_state_bucket_name = var.tf_state_bucket_name

  # ---------------------------------------------------------------------------
  # 🔥 MODE FOUNDATION (TRÈS IMPORTANT)
  # ---------------------------------------------------------------------------
  enable_lakehouse_runtimes = false

  allow_pull_request = var.allow_pull_request
}

