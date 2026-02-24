locals {
  labels_csv = join(",", [for k, v in var.labels : "${k}=${v}"])
}

resource "null_resource" "apply_labels" {
  triggers = {
    project_id = var.project_id
    labels_csv = local.labels_csv
  }

  provisioner "local-exec" {
    command = <<EOT
set -euo pipefail

PROJECT_ID="${var.project_id}"
LABELS="${local.labels_csv}"

echo "[project_labels] Applying labels to $PROJECT_ID: $LABELS"

# 1) Try GA track
if gcloud projects update "$PROJECT_ID" --update-labels="$LABELS" >/dev/null 2>&1; then
  echo "[project_labels] Labels applied (GA)."
  exit 0
fi

echo "[project_labels] GA flag not available; trying alpha..."

# 2) Ensure alpha components exist (best effort)
gcloud components install alpha -q >/dev/null 2>&1 || true

# 3) Try alpha track
gcloud alpha projects update "$PROJECT_ID" --update-labels="$LABELS"
echo "[project_labels] Labels applied (alpha)."
EOT
  }
}