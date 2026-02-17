# ============================================================
# Makefile - GCP Lakehouse From Scratch (Enterprise)
# ============================================================
# - Makefile = orchestrateur (UX dev)
# - Python/Terraform = logique & infra
# ============================================================


# -----------------------------------------------------------------------------
# ROOT_DIR (robuste "enterprise")
# -----------------------------------------------------------------------------
# MAKEFILE_LIST contient le chemin du Makefile en cours.
# On prend son dossier => racine stable du repo.
# Ça marche même si tu exécutes `make` depuis un sous-dossier.
# ROOT_DIR = racine du repo (sans slash final)
# -> évite les chemins en // et rend l’output plus clean
ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# -----------------------------------------------------------------------------
# ENV (dev/staging/prod)
# -----------------------------------------------------------------------------
ENV ?= dev
# Mapping propre multi-projet
ifeq ($(ENV),dev)
PROJECT_ID := lakehouse-dev-486419
LOCATION   := europe-west1
endif

ifeq ($(ENV),staging)
PROJECT_ID := lakehouse-stg-486419
LOCATION   := europe-west1
endif

ifeq ($(ENV),prod)
PROJECT_ID := lakehouse-prd-486419
LOCATION   := europe-west1
endif
# -----------------------------------------------------------------------------
# Terraform
# -----------------------------------------------------------------------------
TF_DIR := $(ROOT_DIR)/terraform
TF_VARS := $(TF_DIR)/envs/$(ENV)/terraform.tfvars

# IMPORTANT (grand groupe) :
# On évite le prompt interactif "var.env Enter a value".
# -> On fixe TF_VAR_env en dur via Makefile.
export TF_VAR_env := $(ENV)

# -----------------------------------------------------------------------------
# Bootstrap config
# -----------------------------------------------------------------------------
BOOTSTRAP_CONFIG ?= $(ROOT_DIR)/configs/projects.yaml
CONFIRM ?= NO
# -----------------------------------------------------------------------------
# PYTHON BIN (enterprise)
# -----------------------------------------------------------------------------
# Objectif :
#   - Toujours exécuter avec le même interpréteur
#   - Reproductible sur n'importe quel poste / CI
#
# Stratégie :
#   - Si .venv existe à la racine => on utilise .venv/bin/python
#   - Sinon => fallback sur python3 (CI / machine sans venv)
PYTHON_BIN := $(ROOT_DIR)/.venv/bin/python
ifeq (,$(wildcard $(PYTHON_BIN)))
PYTHON_BIN := python3
endif

# =============================================================================
# HELP
# =============================================================================
help:
	@echo ""
	@echo "============================================================"
	@echo " Lakehouse - Available Commands"
	@echo "============================================================"
	@echo ""
	@echo "Bootstrap:"
	@echo "  make bootstrap-config-template > configs/projects.yaml"
	@echo "  make bootstrap-projects CONFIRM=YES"
	@echo ""
	@echo "Terraform:"
	@echo "  make tf-init ENV=dev"
	@echo "  make tf-plan ENV=dev"
	@echo "  make tf-apply ENV=dev"
	@echo ""
	@echo "Dataproc:"
	@echo "  make iceberg ENV=dev"
	@echo ""
	@echo "============================================================"
	@echo ""

# =============================================================================
# BOOTSTRAP (Python) — Enterprise
# =============================================================================

.PHONY: bootstrap-projects bootstrap-config-template bootstrap-doctor

# ROOT_DIR stable (exécutable depuis n'importe quel dossier)
ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Fichier de config YAML (source-of-truth)
BOOTSTRAP_CONFIG ?= $(ROOT_DIR)/configs/projects.yaml
CONFIRM ?= NO

# Python venv du repo (si présent), sinon python3
PYTHON_BIN := $(ROOT_DIR)/.venv/bin/python
ifeq (,$(wildcard $(PYTHON_BIN)))
PYTHON_BIN := python3
endif

bootstrap-config-template:
	@echo "# ============================================================================="
	@echo "# projects.yaml — SOURCE OF TRUTH (multi-project bootstrap)"
	@echo "# ============================================================================="
	@echo "billing_account_id: \"REPLACE-ME\""
	@echo "projects:"
	@echo "  dev: \"lakehouse-dev-486419\""
	@echo "  staging: \"lakehouse-stg-486419\""
	@echo "  prod: \"lakehouse-prd-486419\""
	@echo ""
	@echo "labels:"
	@echo "  owner: \"alex\""
	@echo "  platform: \"lakehouse\""
	@echo "  cost_center: \"data\""

bootstrap-projects:
	@echo "⚠️  Bootstrap will CREATE projects + LINK billing + ENABLE APIs"
	@echo "    Config: $(BOOTSTRAP_CONFIG)"
	@echo ""
	@echo "To proceed:"
	@echo "  make bootstrap-projects CONFIRM=YES BOOTSTRAP_CONFIG=$(BOOTSTRAP_CONFIG)"
	@if [ "$(CONFIRM)" != "YES" ]; then \
		echo "❌ Aborted (set CONFIRM=YES)."; \
		exit 1; \
	fi
	@if [ ! -f "$(BOOTSTRAP_CONFIG)" ]; then \
		echo "❌ Missing file: $(BOOTSTRAP_CONFIG)"; \
		echo "   Generate it with: make bootstrap-config-template > configs/projects.yaml"; \
		exit 1; \
	fi
	@echo "Running bootstrap from YAML config..."
	@$(PYTHON_BIN) $(ROOT_DIR)/scripts/bootstrap_projects.py \
		--config "$(BOOTSTRAP_CONFIG)" \
		--confirm "YES"

bootstrap-doctor:
	@echo "== gcloud version =="
	@gcloud --version | head -n 1 || true
	@echo "== active account =="
	@gcloud config get-value core/account || true
	@echo "== visible billing accounts =="
	@gcloud billing accounts list --format="table(name,displayName,open)" || true
# =========================
# Terraform (safe multi-env)
# =========================
# Usage:
#   make tf-init ENV=staging
#   make tf-plan ENV=staging
#   make tf-apply ENV=staging
#   make tf-destroy ENV=staging
#
# Important:
# - ENV doit être dev|staging|prod
# - On force le backend via terraform/envs/<ENV>/backend.hcl
# - On force les variables via terraform/envs/<ENV>/terraform.tfvars
# - On exécute terraform dans le dossier terraform/ via -chdir (propre)
#
ENV ?= staging
TF_DIR := terraform
TF_BACKEND := envs/$(ENV)/backend.hcl
TF_VARS := envs/$(ENV)/terraform.tfvars

# Petit garde-fou : refuse un ENV non prévu
ifeq (,$(filter $(ENV),dev staging prod))
$(error ENV invalid: '$(ENV)'. Use ENV=dev|staging|prod)
endif

.PHONY: tf-init tf-plan tf-apply tf-destroy tf-refresh tf-state-list

tf-init:
	@echo "==> Terraform INIT for ENV=$(ENV)"
	@echo "    - Backend: $(TF_DIR)/$(TF_BACKEND)"
	@echo "    - Vars:    $(TF_DIR)/$(TF_VARS)"
	# -reconfigure : utile si tu as déjà initialisé avec un autre backend
	terraform -chdir=$(TF_DIR) init -reconfigure -backend-config=$(TF_BACKEND)

tf-plan: tf-init
	@echo "==> Terraform PLAN for ENV=$(ENV)"
	terraform -chdir=$(TF_DIR) plan -var-file=$(TF_VARS)

.PHONY: tf-guard

tf-guard:
	@echo "==> Guard check for ENV=$(ENV)"
	@echo "    Ensuring backend file exists..."
	@test -f "$(TF_DIR)/$(TF_BACKEND)" || (echo "Missing backend: $(TF_DIR)/$(TF_BACKEND)" && exit 1)
	@echo "    Ensuring vars file exists..."
	@test -f "$(TF_DIR)/$(TF_VARS)" || (echo "Missing vars: $(TF_DIR)/$(TF_VARS)" && exit 1)

tf-apply: tf-init tf-guard
	@echo "==> Terraform APPLY for ENV=$(ENV)"
	terraform -chdir=$(TF_DIR) apply -var-file=$(TF_VARS)

tf-destroy: tf-init
	@echo "==> Terraform DESTROY for ENV=$(ENV)"
	# Attention: destroy détruit VRAIMENT l'environnement ciblé
	terraform -chdir=$(TF_DIR) destroy -var-file=$(TF_VARS)

tf-refresh: tf-init
	@echo "==> Terraform REFRESH for ENV=$(ENV)"
	terraform -chdir=$(TF_DIR) refresh -var-file=$(TF_VARS)

tf-state-list: tf-init
	@echo "==> Terraform STATE LIST for ENV=$(ENV)"
	terraform -chdir=$(TF_DIR) state list
# -----------------------------------------------------------------------------
# Orchestration / Dataproc (PySpark)
# -----------------------------------------------------------------------------
ORCH_MODULE := orchestration.src.lakehouse_cli.cli
ENV_FILE := $(ROOT_DIR)/configs/env.$(ENV).yaml
PROFILES_FILE := $(ROOT_DIR)/configs/profiles.yaml
ICEBERG_JOB := $(ROOT_DIR)/jobs/iceberg_writer/create_iceberg_tables.py

iceberg:
	@echo "Submitting Iceberg job to Dataproc (ENV=$(ENV))..."
	@$(PYTHON_BIN) -m $(ORCH_MODULE) dataproc-iceberg \
	  --local-job $(ICEBERG_JOB) \
	  --env-file $(ENV_FILE) \
	  --profiles-file $(PROFILES_FILE) \
	  --profile dev_small


# =============================================================================
# GUARD RAILS (enterprise)
# =============================================================================
# Macro: check-file
# Usage: $(call check-file,<path>,<message>)
define check-file
	@if [ ! -f "$(1)" ]; then \
		echo "❌ Missing file: $(1)"; \
		echo "   $(2)"; \
		exit 1; \
	fi
endef

# =============================================================================
# DEV TOOLING (Enterprise)
# =============================================================================

.PHONY: venv doctor

# Installe les deps du repo dans le venv du repo (pas ailleurs)
venv:
	@echo "Bootstrapping python environment (repo venv)..."
	@$(PYTHON_BIN) $(ROOT_DIR)/scripts/bootstrap_venv.py

# Check rapide: gcloud + python + terraform
doctor:
	@echo "== Repo doctor checks =="
	@echo "Python:"
	@$(PYTHON_BIN) -c "import sys; print(sys.executable)"
	@echo ""
	@echo "PyYAML:"
	@$(PYTHON_BIN) -c "import yaml; print('OK:', yaml.__version__)" || true
	@echo ""
	@echo "gcloud:"
	@command -v gcloud >/dev/null 2>&1 && gcloud --version | head -n 1 || echo "❌ gcloud not found"
	@echo ""
	@echo "terraform:"
	@command -v terraform >/dev/null 2>&1 && terraform version | head -n 1 || echo "❌ terraform not found"


# ==========================================
# Dataform orchestration (Python)
# ==========================================

bq-test-curated:
	python scripts/test_bigquery_curated_table.py \
	  --project $(PROJECT_ID) \
	  --dataset curated_$(ENV) \
	  --table stg_sample \
	  --region $(LOCATION) \
	  --min-rows 1 \
	  --limit 5

upload-sample:
	python scripts/upload_sample_to_gcs_env.py --env $(ENV)

bq-fix-dataset-access:
	python scripts/fix_bq_dataset_access_env.py --env $(ENV) --dataset curated_$(ENV)

bq-test:
	python -m scripts.test_bigquery_external_table_env --env $(ENV) --table sample_ext --limit 5

dataform-run:
	python -m scripts.run_dataform_workflow_env --env $(ENV) --timeout-sec 1800 --poll-sec 10
e2e:
	$(MAKE) dataform-run
	$(MAKE) bq-test-curated

bq-test-curated:
	python -m scripts.test_bigquery_curated_table_env --env $(ENV) --table stg_sample --min-rows 1 --limit 5