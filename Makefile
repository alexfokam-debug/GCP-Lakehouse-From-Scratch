# ============================================================
# Makefile - GCP Lakehouse From Scratch (Enterprise)
# ============================================================
# Rôle :
# - Orchestrer l'expérience dev (UX) : terraform + scripts Python + Dataform
# - Respecter la séparation "foundation" vs "lakehouse"
# - Zéro ambiguïté : chaque target pointe vers le bon dossier Terraform
# ============================================================

# -----------------------------------------------------------------------------
# (0) ROOT_DIR (robuste)
# -----------------------------------------------------------------------------
# MAKEFILE_LIST contient la liste des Makefiles inclus.
# lastword(...) -> le Makefile courant
# abspath(...)  -> chemin absolu
# dir(...)      -> dossier contenant le Makefile
# patsubst ...  -> enlève le / final (plus clean)
#
# Résultat :
# ROOT_DIR = racine du repo, stable même si tu lances `make` depuis un sous-dossier
ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# -----------------------------------------------------------------------------
# (1) ENV (dev/staging/prod)
# -----------------------------------------------------------------------------
# ENV par défaut (tu peux override : make <target> ENV=staging)
ENV ?= dev

# Garde-fou : refuse un ENV non prévu
ifeq (,$(filter $(ENV),dev staging prod))
$(error ENV invalid: '$(ENV)'. Use ENV=dev|staging|prod)
endif

# -----------------------------------------------------------------------------
# (2) Project mapping (utile pour scripts / affichage)
# -----------------------------------------------------------------------------
# NOTE :
# - Terraform lit project_id depuis terraform.tfvars
# - Mais côté Makefile c'est pratique pour afficher et pour certains scripts
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
# (3) Terraform stacks (nouvelle arborescence)
# -----------------------------------------------------------------------------
# TF_ROOT_DIR          -> dossier terraform/ à la racine
# TF_FOUNDATION_DIR    -> stack "foundation"
# TF_LAKEHOUSE_DIR     -> stack "lakehouse"
TF_ROOT_DIR       := $(ROOT_DIR)/terraform
TF_FOUNDATION_DIR := $(TF_ROOT_DIR)/foundation
TF_LAKEHOUSE_DIR  := $(TF_ROOT_DIR)/lakehouse

# -----------------------------------------------------------------------------
# (4) Backend & tfvars (paths relatifs au dossier -chdir)
# -----------------------------------------------------------------------------
# Important :
# - Comme on utilise `terraform -chdir=<stack>`, les fichiers backend/tfvars
#   doivent être donnés RELATIFS à ce dossier.
#
# Ex :
# terraform -chdir=terraform/foundation init -backend-config=envs/dev/backend.hcl
TF_FOUNDATION_BACKEND := envs/$(ENV)/backend.hcl
TF_FOUNDATION_VARS    := envs/$(ENV)/terraform.tfvars

TF_LAKEHOUSE_BACKEND  := envs/$(ENV)/backend.hcl
TF_LAKEHOUSE_VARS     := envs/$(ENV)/terraform.tfvars

# -----------------------------------------------------------------------------
# (5) TF vars export (optionnel)
# -----------------------------------------------------------------------------
# Si tes modules consomment TF_VAR_environment (ou scripts legacy),
# tu peux garder cette export.
# Sinon, ça ne gêne pas.
export TF_VAR_environment := $(ENV)

# -----------------------------------------------------------------------------
# (6) Bootstrap config (Python)
# -----------------------------------------------------------------------------
BOOTSTRAP_CONFIG ?= $(ROOT_DIR)/configs/projects.yaml
CONFIRM ?= NO

# -----------------------------------------------------------------------------
# (7) Python interpreter (robuste)
# -----------------------------------------------------------------------------
# - Si .venv existe à la racine, on l'utilise
# - Sinon fallback sur python3
PYTHON_BIN := $(ROOT_DIR)/.venv/bin/python
ifeq (,$(wildcard $(PYTHON_BIN)))
PYTHON_BIN := python3
endif

# -----------------------------------------------------------------------------
# (8) Orchestration / Dataproc
# -----------------------------------------------------------------------------
ORCH_MODULE   := orchestration.src.lakehouse_cli.cli
ENV_FILE      := $(ROOT_DIR)/configs/env.$(ENV).yaml
PROFILES_FILE := $(ROOT_DIR)/configs/profiles.yaml
ICEBERG_JOB   := $(ROOT_DIR)/jobs/iceberg_writer/create_iceberg_tables.py

# =============================================================================
# HELP
# =============================================================================
.PHONY: help
help:
	@echo ""
	@echo "============================================================"
	@echo " GCP Lakehouse From Scratch - Commands"
	@echo "============================================================"
	@echo ""
	@echo "Bootstrap:"
	@echo "  make bootstrap-config-template > configs/projects.yaml"
	@echo "  make bootstrap-projects CONFIRM=YES"
	@echo ""
	@echo "Terraform - FOUNDATION:"
	@echo "  make tf-foundation-init ENV=dev"
	@echo "  make tf-foundation-plan ENV=dev"
	@echo "  make tf-foundation-apply ENV=dev"
	@echo ""
	@echo "Terraform - LAKEHOUSE:"
	@echo "  make tf-lakehouse-init ENV=dev"
	@echo "  make tf-lakehouse-plan ENV=dev"
	@echo "  make tf-lakehouse-apply ENV=dev"
	@echo ""
	@echo "Dataform:"
	@echo "  make dataform-run ENV=dev"
	@echo ""
	@echo "Dataproc:"
	@echo "  make iceberg ENV=dev"
	@echo ""
	@echo "Dev tools:"
	@echo "  make venv"
	@echo "  make doctor"
	@echo "============================================================"
	@echo ""

# =============================================================================
# BOOTSTRAP (Python)
# =============================================================================
.PHONY: bootstrap-projects bootstrap-config-template bootstrap-doctor

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

# =============================================================================
# Terraform helpers (guards)
# =============================================================================
# Macro tf_guard :
# - Vérifie que backend.hcl et terraform.tfvars existent
# - Empêche les erreurs floues "file not found" plus tard
#
# Usage :
#   $(call tf_guard,<stack_dir>,<backend_rel>,<tfvars_rel>)
define tf_guard
	@test -f "$(1)/$(2)" || (echo "❌ Missing backend file: $(1)/$(2)" && exit 1)
	@test -f "$(1)/$(3)" || (echo "❌ Missing tfvars file:  $(1)/$(3)" && exit 1)
endef

# =============================================================================
# Terraform — FOUNDATION stack
# =============================================================================
.PHONY: tf-foundation-validate tf-foundation-init tf-foundation-plan tf-foundation-apply tf-foundation-destroy

tf-foundation-validate:
	@echo "==> Terraform VALIDATE (FOUNDATION) ENV=$(ENV)"
	# validate ne touche pas le backend, mais nécessite souvent les providers
	terraform -chdir="$(TF_FOUNDATION_DIR)" validate

tf-foundation-init:
	@echo "==> Terraform INIT (FOUNDATION) ENV=$(ENV)"
	# (1) Guard : fichiers présents
	@$(call tf_guard,$(TF_FOUNDATION_DIR),$(TF_FOUNDATION_BACKEND),$(TF_FOUNDATION_VARS))
	# (2) Init dans LE BON DOSSIER (foundation)
	terraform -chdir="$(TF_FOUNDATION_DIR)" init -reconfigure \
  	-backend-config="envs/$(ENV)/backend.hcl"

tf-foundation-plan: tf-foundation-init
	@echo "==> Terraform PLAN (FOUNDATION) ENV=$(ENV)"
	terraform -chdir="$(TF_FOUNDATION_DIR)" plan \
	  -var-file="$(TF_FOUNDATION_VARS)"

tf-foundation-apply: tf-foundation-init
	@echo "==> Terraform APPLY (FOUNDATION) ENV=$(ENV)"
	terraform -chdir="$(TF_FOUNDATION_DIR)" apply \
	  -var-file="$(TF_FOUNDATION_VARS)"

tf-foundation-destroy: tf-foundation-init
	@echo "==> Terraform DESTROY (FOUNDATION) ENV=$(ENV)"
	terraform -chdir="$(TF_FOUNDATION_DIR)" destroy \
	  -var-file="$(TF_FOUNDATION_VARS)"

# =============================================================================
# Terraform — LAKEHOUSE stack
# =============================================================================
.PHONY: tf-lakehouse-validate tf-lakehouse-init tf-lakehouse-plan tf-lakehouse-apply tf-lakehouse-destroy

tf-lakehouse-validate:
	@echo "==> Terraform VALIDATE (LAKEHOUSE) ENV=$(ENV)"
	terraform -chdir="$(TF_LAKEHOUSE_DIR)" validate

tf-lakehouse-init:
	@echo "==> Terraform INIT (LAKEHOUSE) ENV=$(ENV)"
	@$(call tf_guard,$(TF_LAKEHOUSE_DIR),$(TF_LAKEHOUSE_BACKEND),$(TF_LAKEHOUSE_VARS))
	terraform -chdir="$(TF_LAKEHOUSE_DIR)" init -reconfigure \
	  -backend-config="$(TF_LAKEHOUSE_BACKEND)"

tf-lakehouse-plan: tf-lakehouse-init
	@echo "==> Terraform PLAN (LAKEHOUSE) ENV=$(ENV)"
	terraform -chdir="$(TF_LAKEHOUSE_DIR)" plan \
	  -var-file="$(TF_LAKEHOUSE_VARS)"

tf-lakehouse-apply: tf-lakehouse-init
	@echo "==> Terraform APPLY (LAKEHOUSE) ENV=$(ENV)"
	terraform -chdir="$(TF_LAKEHOUSE_DIR)" apply \
	  -var-file="$(TF_LAKEHOUSE_VARS)"

tf-lakehouse-destroy: tf-lakehouse-init
	@echo "==> Terraform DESTROY (LAKEHOUSE) ENV=$(ENV)"
	terraform -chdir="$(TF_LAKEHOUSE_DIR)" destroy \
	  -var-file="$(TF_LAKEHOUSE_VARS)"

# =============================================================================
# Dataproc (Iceberg writer)
# =============================================================================
.PHONY: iceberg
iceberg:
	@echo "Submitting Iceberg job to Dataproc (ENV=$(ENV))..."
	@$(PYTHON_BIN) -m $(ORCH_MODULE) dataproc-iceberg \
	  --local-job "$(ICEBERG_JOB)" \
	  --env-file "$(ENV_FILE)" \
	  --profiles-file "$(PROFILES_FILE)" \
	  --profile dev_small

# =============================================================================
# DEV TOOLING
# =============================================================================
.PHONY: venv doctor

venv:
	@echo "Bootstrapping python environment (repo venv)..."
	@$(PYTHON_BIN) $(ROOT_DIR)/scripts/bootstrap_venv.py

doctor:
	@echo "== Repo doctor checks =="
	@echo "ENV=$(ENV)"
	@echo "PROJECT_ID=$(PROJECT_ID)"
	@echo "LOCATION=$(LOCATION)"
	@echo ""
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

# =============================================================================
# Dataform orchestration (Python) — safe mapping
# =============================================================================
.PHONY: dataform-run dataform-run-dev dataform-run-prod \
        bq-test-curated upload-sample bq-fix-dataset-access bq-test e2e

# Workflow par défaut : mapping SAFE selon ENV
ifeq ($(ENV),dev)
DATAFORM_WORKFLOW_DEFAULT := wf-dev-on-demand
endif
ifeq ($(ENV),staging)
DATAFORM_WORKFLOW_DEFAULT := wf-dev-on-demand
endif
ifeq ($(ENV),prod)
DATAFORM_WORKFLOW_DEFAULT := wf-prod-weekdays
endif

# Workflow réellement utilisé :
# - si WORKFLOW=xxx est fourni, il écrase le default
WORKFLOW ?= $(DATAFORM_WORKFLOW_DEFAULT)

dataform-run:
	@echo "==> Dataform RUN"
	@echo "    ENV=$(ENV)"
	@echo "    WORKFLOW=$(WORKFLOW)"
	@$(PYTHON_BIN) -m scripts.run_dataform_workflow_env \
	  --env $(ENV) \
	  --workflow $(WORKFLOW) \
	  --timeout-sec 1800 \
	  --poll-sec 10

dataform-run-dev:
	@$(MAKE) dataform-run ENV=dev

dataform-run-prod:
	@$(MAKE) dataform-run ENV=prod

bq-test-curated:
	@echo "==> BQ test curated table (ENV=$(ENV))"
	@$(PYTHON_BIN) -m scripts.test_bigquery_curated_table_env \
	  --env $(ENV) \
	  --table stg_sample \
	  --min-rows 1 \
	  --limit 5

upload-sample:
	@echo "==> Upload sample to GCS (ENV=$(ENV))"
	@$(PYTHON_BIN) scripts/upload_sample_to_gcs_env.py --env $(ENV)

bq-fix-dataset-access:
	@echo "==> Fix dataset access (ENV=$(ENV))"
	@$(PYTHON_BIN) scripts/fix_bq_dataset_access_env.py --env $(ENV) --dataset curated_$(ENV)

bq-test:
	@echo "==> BQ test external table (ENV=$(ENV))"
	@$(PYTHON_BIN) -m scripts.test_bigquery_external_table_env --env $(ENV) --table sample_ext --limit 5

# End-to-end :
# - exécute Dataform
# - puis vérifie une table curated
e2e:
	@$(MAKE) dataform-run ENV=$(ENV)
	@$(MAKE) bq-test-curated ENV=$(ENV)