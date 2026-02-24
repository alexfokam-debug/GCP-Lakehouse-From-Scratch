/**
 * Stack FOUNDATION (org-level)
 * - Crée les tags Resource Manager.
 * - À exécuter 1 fois (ou rarement).
 */
module "org_tags" {
  source = "./modules/org_tags"

  org_id = var.org_id

  tag_key_short_name  = "environment"
  tag_key_description = "Environment tag (Development/Test/Staging/Production)"

  tag_values = {
    dev = {
      short_name  = "Development"
      description = "Development environment"
    }
    staging = {
      short_name  = "Staging"
      description = "Staging environment"
    }
    prod = {
      short_name  = "Production"
      description = "Production environment"
    }
  }
}

