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
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
# =============================================================================
# ATTENTE DE PROPAGATION APRÈS ACTIVATION DE L'API ARTIFACT REGISTRY
# -----------------------------------------------------------------------------
# Pourquoi ?
# GCP peut répondre "SERVICE_DISABLED" pendant quelques secondes après
# l'activation effective de l'API.
#
# Donc on force une petite temporisation avant de créer le repository.
# =============================================================================
resource "time_sleep" "wait_artifact_registry_api" {
  depends_on = [
    google_project_service.services["artifactregistry.googleapis.com"]
  ]

  create_duration = "45s"
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
# OBJECTIF
# -----------------------------------------------------------------------------
# Centraliser dans un seul module :
# - l'IAM GitHub / WIF
# - le bootstrap CI/CD
# - les accès humains locaux (Cloud Build / Artifact Registry)
# - les accès du runtime Cloud Build
#
# IMPORTANT
# -----------------------------------------------------------------------------
# Ce module IAM est capable de gérer deux modes :
#
# (A) mode FOUNDATION
#     -> gère uniquement :
#        - GitHub WIF
#        - CI bootstrap
#        - accès build local / Cloud Build
#
# (B) mode LAKEHOUSE RUNTIME
#     -> gère en plus :
#        - runtimes Dataform
#        - runtimes Dataproc
#        - bindings IAM sur datasets et buckets data
#
# DANS CE ROOT MODULE "foundation" :
# on veut rester en mode FOUNDATION.
#
# Donc :
# enable_lakehouse_runtimes doit être FALSE ici.
#
# Pourquoi ?
# - foundation ne doit pas dépendre des objets data
# - foundation ne doit pas embarquer les datasets et buckets métiers
# - la couche data doit vivre dans le root module lakehouse
#
# BONNE PRATIQUE
# -----------------------------------------------------------------------------
# On conserve malgré tout le passage des variables datasets/buckets :
# - cela garde le bloc homogène
# - cela évite de réécrire le module plus tard
# - mais elles ne seront PAS consommées tant que
#   enable_lakehouse_runtimes = false
# =============================================================================

###############################################################################
# MODULE IAM — FOUNDATION MODE
###############################################################################

module "iam" {
  source = "../modules/iam"

  # ---------------------------------------------------------------------------
  # (1) COMMON
  # ---------------------------------------------------------------------------
  # project_id :
  #   projet GCP cible sur lequel on applique les droits IAM
  #
  # environment :
  #   environnement logique (dev / staging / prod)
  # ---------------------------------------------------------------------------
  project_id  = var.project_id
  environment = var.environment

  # ---------------------------------------------------------------------------
  # (2) GITHUB / WIF
  # ---------------------------------------------------------------------------
  # github_repository :
  #   dépôt GitHub autorisé à s'authentifier via WIF
  #
  # manage_wif :
  #   true  -> Terraform gère pool + provider WIF
  #   false -> WIF géré ailleurs
  #
  # enable_github_cicd_wif_pool_admin :
  #   option avancée pour donner plus de droits au SA GitHub CI/CD sur le pool
  # ---------------------------------------------------------------------------
  github_repository                 = var.github_repository
  manage_wif                        = var.manage_wif
  enable_github_cicd_wif_pool_admin = var.enable_github_cicd_wif_pool_admin

  # ---------------------------------------------------------------------------
  # (3) CI BOOTSTRAP
  # ---------------------------------------------------------------------------
  # bootstrap_ci_iam :
  #   true  -> donne les droits bootstrap CI/CD
  #   false -> mode sécurisé, pas de bootstrap automatique
  #
  # tf_state_bucket_name :
  #   bucket GCS utilisé pour le remote state Terraform
  # ---------------------------------------------------------------------------
  bootstrap_ci_iam     = var.bootstrap_ci_iam
  tf_state_bucket_name = var.tf_state_bucket_name

  # ---------------------------------------------------------------------------
  # (4) ACTIVATION DES RUNTIMES LAKEHOUSE
  # ---------------------------------------------------------------------------
  # TRÈS IMPORTANT :
  # Ici, dans FOUNDATION, on doit laisser cette valeur à FALSE.
  #
  # Cela permet :
  # - de garder le module compatible avec le mode lakehouse
  # - sans activer ici les ressources Dataform / Dataproc runtime
  #
  # Recommandation :
  # - piloter la valeur via la variable root
  # - et mettre false dans foundation/envs/dev/terraform.tfvars
  # ---------------------------------------------------------------------------
  enable_lakehouse_runtimes = var.enable_lakehouse_runtimes

  # ---------------------------------------------------------------------------
  # (5) DATASETS
  # ---------------------------------------------------------------------------
  # Ces variables restent câblées au module pour garder une interface stable.
  #
  # En mode FOUNDATION :
  # - elles ne doivent pas être utilisées
  # - elles peuvent rester nulles / non renseignées si le module IAM
  #   est bien protégé par enable_lakehouse_runtimes = false
  # ---------------------------------------------------------------------------
  curated_dataset_id         = var.curated_dataset_id
  analytics_dataset_id       = var.analytics_dataset_id
  raw_external_dataset_id    = var.raw_external_dataset_id
  curated_iceberg_dataset_id = var.curated_iceberg_dataset_id
  tmp_dataset_id             = var.tmp_dataset_id
  enable_tmp_dataset         = var.enable_tmp_dataset
  enterprise_dataset_id      = var.enterprise_dataset_id

  # ---------------------------------------------------------------------------
  # (6) BUCKETS
  # ---------------------------------------------------------------------------
  # Même logique que pour les datasets :
  # - on garde l'interface complète
  # - mais en mode FOUNDATION, ces valeurs ne doivent pas déclencher
  #   de bindings IAM data
  # ---------------------------------------------------------------------------
  raw_bucket_name           = var.raw_bucket_name
  curated_bucket_name       = var.curated_bucket_name
  iceberg_bucket_name       = var.iceberg_bucket_name
  dataproc_temp_bucket_name = var.dataproc_temp_bucket_name
  scripts_bucket_name       = var.scripts_bucket_name

  # ---------------------------------------------------------------------------
  # (7) BUILD HUMAIN LOCAL
  # ---------------------------------------------------------------------------
  # Permet à ton utilisateur humain de :
  # - lancer Cloud Build
  # - pousser des images dans Artifact Registry
  # ---------------------------------------------------------------------------
  enable_human_build_access = var.enable_human_build_access
  human_user_email          = var.human_user_email

  # ---------------------------------------------------------------------------
  # (8) CLOUD BUILD RUNTIME
  # ---------------------------------------------------------------------------
  # Permet au service account utilisé par Cloud Build de :
  # - lire l'archive source
  # - pousser l'image Docker dans Artifact Registry
  # ---------------------------------------------------------------------------
  enable_cloud_build_runtime_access = var.enable_cloud_build_runtime_access
  cloud_build_service_account_email = var.cloud_build_service_account_email

  allow_pull_request = var.allow_pull_request
}

# =============================================================================
# ARTIFACT REGISTRY - CUSTOM CONTAINERS DATAPROC SERVERLESS
# -----------------------------------------------------------------------------
# Ce repository Docker héberge les images custom utilisées par Dataproc
# Serverless, notamment pour embarquer des dépendances spécifiques
# (ex: GRIB2, xarray, cfgrib, eccodes, etc.).
#
# On le garde dans FOUNDATION car :
# - c'est une ressource de plateforme
# - elle sert de socle technique partagé
# - elle ne dépend pas directement des datasets métier
# =============================================================================
module "artifact_registry_dataproc" {
  source = "../modules/artifact_registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "dataproc-custom"
  description   = "Custom containers for Dataproc Serverless"

  depends_on = [
    time_sleep.wait_artifact_registry_api
  ]
}