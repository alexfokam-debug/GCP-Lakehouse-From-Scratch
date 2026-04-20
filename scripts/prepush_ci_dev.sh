#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID_DEV:?Missing GCP_PROJECT_ID_DEV}"
: "${TF_STATE_BUCKET_DEV:?Missing TF_STATE_BUCKET_DEV}"

export CLOUDSDK_CORE_PROJECT="$GCP_PROJECT_ID_DEV"
export GOOGLE_CLOUD_PROJECT="$GCP_PROJECT_ID_DEV"
export GOOGLE_PROJECT="$GCP_PROJECT_ID_DEV"

echo "== gcloud identity =="
gcloud config set project "$GCP_PROJECT_ID_DEV" >/dev/null
gcloud projects describe "$GCP_PROJECT_ID_DEV" >/dev/null && echo "OK project"

echo "== Terraform foundation (dev) =="
terraform -chdir=terraform/foundation fmt -check -recursive
terraform -chdir=terraform/foundation init -reconfigure \
  -backend-config="bucket=$TF_STATE_BUCKET_DEV" \
  -backend-config="prefix=foundation/dev"
terraform -chdir=terraform/foundation validate
terraform -chdir=terraform/foundation plan -var-file=envs/dev/terraform.tfvars -compact-warnings

echo "== Terraform lakehouse (dev) =="
terraform -chdir=terraform/lakehouse fmt -check -recursive
terraform -chdir=terraform/lakehouse init -reconfigure \
  -backend-config="bucket=$TF_STATE_BUCKET_DEV" \
  -backend-config="prefix=lakehouse/dev"
terraform -chdir=terraform/lakehouse validate
terraform -chdir=terraform/lakehouse plan -var-file=envs/dev/terraform.tfvars -compact-warnings

echo " OK: local CI-like plan succeeded (dev)."