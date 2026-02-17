# =========================
# Terraform remote state (DEV)
# =========================
# Ce fichier est lu par:
#   terraform init -backend-config=envs/dev/backend.hcl
#
# IMPORTANT:
# - bucket: ton bucket qui stocke les states terraform (à toi de le créer une fois)
# - prefix: chemin distinct par environnement => 3 states séparés
#
bucket = "lakehouse-terraform-states-486419"  # <-- A MODIFIER: ton bucket de state (unique)
prefix = "gcp-lakehouse/dev"                  # <-- NE PAS MELANGER avec staging/prod