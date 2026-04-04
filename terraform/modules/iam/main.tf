###############################################################################
# main.tf — Module IAM (OPTION 1)
# -----------------------------------------------------------------------------
# Ce fichier est volontairement MINIMAL.
#
# Pourquoi ?
# - Ton ancien main.tf était trop long et mélangeait 3 sujets :
#   (1) Runtime Dataform
#   (2) Runtime Dataproc
#   (3) CI/CD GitHub (WIF)
#
# Ici :
# - La logique runtime Dataform est dans runtime_dataform.tf
# - La logique runtime Dataproc est dans runtime_dataproc.tf
# - La logique CI/CD est dans github_ci_iam.tf
#
# Résultat :
# - Lisible
# - Évite les oublis
# - Facile à tester / maintenir
###############################################################################

# =============================================================================
# 0) Infos projet : récupérer le PROJECT NUMBER
# -----------------------------------------------------------------------------
# Utilité :
# - Construire l'email du Dataform Service Agent (Google-managed)
#   service-${PROJECT_NUMBER}@gcp-sa-dataform.iam.gserviceaccount.com
# =============================================================================
data "google_project" "current" {
  project_id = var.project_id # projet où l’IAM est appliqué
}

# =============================================================================
# 1) Locals = constantes calculées une seule fois (évite répétitions)
# =============================================================================
locals {
  # Email du service agent Dataform (identité gérée par Google)
  dataform_service_agent = "service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

