/**
 * includes/constants.js
 * Centralisation des constantes par environnement.
 * L'environnement est injecté via Terraform ReleaseConfig:
 * vars = { env = var.environment }
 */

const env =
  (dataform.projectConfig.vars &&
    dataform.projectConfig.vars.env) ||
  "dev";

const PROJECT_ID =
  dataform.projectConfig.defaultDatabase;

// Export unique et propre
module.exports = {
  ENV: env,
  PROJECT_ID,

  // =========================
  // DATASETS SOURCES
  // =========================
  RAW_DATASET: `raw_${env}`,
  RAW_EXT_DATASET: `raw_ext_${env}`,

  CURATED_DATASET: `curated_${env}`,
  CURATED_EXT_DATASET: `curated_ext_${env}`,
  CURATED_ICEBERG_DATASET: `curated_iceberg_${env}`,

  // =========================
  // DATASETS ANALYTICS (marts)
  // =========================
  ANALYTICS_DATASET: `analytics_${env}`
};