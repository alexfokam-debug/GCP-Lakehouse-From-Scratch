##############################################################################
# =============================================================================
# ENV FILE (DEV)
# =============================================================================
##############################################################################

# ---------------------------------------------------------------------------
# GCP project cible pour DEV
# -> Tout ce que Terraform crée/lit par défaut (datasets, buckets, IAM, secrets)
# -> Ici DEV tourne dans le projet lakehouse-486419
# ---------------------------------------------------------------------------
project_id = "lakehouse-486419"

# ---------------------------------------------------------------------------
# Nom logique d'environnement
# -> Sert à suffixer les ressources (datasets, buckets, etc.)
# ---------------------------------------------------------------------------
environment = "dev"

# ---------------------------------------------------------------------------
# Région principale pour les ressources régionales (Dataform, Dataplex, etc.)
# ---------------------------------------------------------------------------
region = "europe-west1"

# ---------------------------------------------------------------------------
# Domaine métier (ex: sales, finance, hr)
# -> Utilisé dans les paths GCS/hive partitions et naming logique
# ---------------------------------------------------------------------------
domain = "sales"

# ---------------------------------------------------------------------------
# Dataset name “fonctionnel” pour les exemples / bootstrap
# ---------------------------------------------------------------------------
dataset_name = "sample"


# ---------------------------------------------------------------------------
# Labels GCP (gouvernance / FinOps)
# ---------------------------------------------------------------------------
labels = {
  owner       = "alex"       # owner / responsable
  platform    = "lakehouse"  # nom plateforme
  cost_center = "data"       # centre de coûts
}


##############################################################################
# RAW external tables (BigQuery external tables sur GCS)
##############################################################################

# ---------------------------------------------------------------------------
# Définition des tables externes BigQuery (raw_ext_dev)
# -> Chaque entrée décrit une table externe et son chemin GCS
# ---------------------------------------------------------------------------
raw_external_tables = {
  # Exemple minimal
  sample_ext = {
    source_format = "PARQUET"   # format des fichiers sources
    source_uris = [
      "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sample/*"
    ]
    hive_source_prefix       = "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sample/"
    require_partition_filter = false
  }

  # Table orders
  orders = {
    source_format = "PARQUET"
    source_uris = [
      "gs://lakehouse-486419-raw-dev/domain=sales/dataset=orders/*"
    ]
    hive_source_prefix       = "gs://lakehouse-486419-raw-dev/domain=sales/dataset=orders/"
    require_partition_filter = false
  }

  # Table sales_transactions
  sales_transactions = {
    source_format = "PARQUET"
    source_uris = [
      "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sales_transactions/*"
    ]
    hive_source_prefix       = "gs://lakehouse-486419-raw-dev/domain=sales/dataset=sales_transactions/"
    require_partition_filter = false
  }
}


##############################################################################
# DATAFORM (repo + secret token Git)
##############################################################################

# ---------------------------------------------------------------------------
# Repo GitHub Dataform (URL du repo)
# ---------------------------------------------------------------------------
dataform_git_repo_url = "https://github.com/alexfokam-debug/GCP-Lakehouse-From-Scratch.git"

# ---------------------------------------------------------------------------
# Branche par défaut du repo Dataform
# ---------------------------------------------------------------------------
dataform_default_branch = "main"

# ---------------------------------------------------------------------------
# IMPORTANT : Stratégie DEV simple (recommandée)
# -> Le secret est dans le MÊME projet que project_id (lakehouse-486419)
# -> Donc on référence le secret via son ID simple uniquement
# -> Terraform lira : projects/${project_id}/secrets/${git_token_secret_id}
# ---------------------------------------------------------------------------
git_token_secret_id = "dataform-git-token"

# ---------------------------------------------------------------------------
# (DÉSACTIVÉ) Ancienne approche cross-project / shared-secrets
# -> Ceci force Terraform à lire le secret dans un autre projet (518653594867)
# -> Si tu laisses ça, il faut gérer IAM cross-project => source d’erreurs
# -> On coupe en DEV pour ne pas tourner en rond.
# ---------------------------------------------------------------------------
dataform_git_token_secret_version = "projects/518653594867/secrets/dataform-git-token/versions/latest"


##############################################################################
# CURATED BigLake tables (Iceberg) - optionnel
##############################################################################

# ---------------------------------------------------------------------------
# Active ou non la création de tables externes curated (Iceberg)
# ---------------------------------------------------------------------------
enable_curated_external_tables = false

# ---------------------------------------------------------------------------
# Liste des tables curated externes (Iceberg) si enable_curated_external_tables=true
# ---------------------------------------------------------------------------
curated_external_tables = {
  customer = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-486419-curated-dev/domain=sales/dataset=sample/iceberg/customer/"
    ]
    autodetect = false
  }

  orders = {
    source_format = "ICEBERG"
    source_uris = [
      "gs://lakehouse-486419-curated-dev/domain=sales/dataset=sample/iceberg/orders/"
    ]
    autodetect = false
  }
}


##############################################################################
# Dataset Iceberg dédié
##############################################################################

# ---------------------------------------------------------------------------
# Dataset BigQuery dédié aux tables Iceberg
# ---------------------------------------------------------------------------
curated_iceberg_dataset_id = "curated_iceberg_dev"

# ---------------------------------------------------------------------------
# Service account Dataproc runtime (créé par Terraform)
# ---------------------------------------------------------------------------
dataproc_sa_email = "sa-dataproc-dev@lakehouse-486419.iam.gserviceaccount.com"


##############################################################################
# TMP dataset (Dataproc/BigQuery connector)
##############################################################################

# ---------------------------------------------------------------------------
# Active ou non le dataset temporaire pour jobs/connector
# ---------------------------------------------------------------------------
enable_tmp_dataset = true

# ---------------------------------------------------------------------------
# Alias d’env (souvent redondant avec environment)
# -> Garde-le si ton code l’utilise
# ---------------------------------------------------------------------------
env = "dev"

# ---------------------------------------------------------------------------
# Active la génération de datasets / samples de démo
# ---------------------------------------------------------------------------
enable_samples = true

# ---------------------------------------------------------------------------
# Suffix “court” pour naming (si ton naming le demande)
# ---------------------------------------------------------------------------
project_id_short = "486419"


##############################################################################
# Service Accounts / Naming
##############################################################################

# ---------------------------------------------------------------------------
# Service account Dataform runtime (créé par Terraform)
# ---------------------------------------------------------------------------
dataform_sa_email = "sa-dataform-dev@lakehouse-486419.iam.gserviceaccount.com"

# ---------------------------------------------------------------------------
# Nom du repository Dataform (dans GCP)
# ---------------------------------------------------------------------------
dataform_repository_name = "lakehouse-dev-dataform"

# ---------------------------------------------------------------------------
# Active la création des external tables “sales/orders” (si ton module le gère)
# ---------------------------------------------------------------------------
enable_sales_orders_external_tables = true

# ---------------------------------------------------------------------------
# Repo GitHub autorisé dans WIF (format owner/repo)
# -> Sert au provider WIF attribute_condition
# ---------------------------------------------------------------------------
github_repository = "alexfokam-debug/GCP-Lakehouse-From-Scratch"


##############################################################################
# Terraform Remote State (Backend)
##############################################################################

# ---------------------------------------------------------------------------
# Bucket GCS utilisé par le backend Terraform (state remote)
# -> Doit exister et contenir les states
# -> C’est CE bucket-là qui doit être accessible depuis GitHub CI/CD
# ---------------------------------------------------------------------------
tf_state_bucket_name = "lakehouse-terraform-states-486419"


##############################################################################
# Bootstrap IAM CI/CD
##############################################################################

# ---------------------------------------------------------------------------
# Active/désactive le bootstrap IAM (donner au CI/CD des droits sur le bucket state)
# -> Si false : Terraform n’essaie pas de créer des IAM bindings bootstrap
# -> Une fois DEV stable, on pourra activer proprement ou garder false + gérer à part
# ---------------------------------------------------------------------------
bootstrap_ci_iam = false