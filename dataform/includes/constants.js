/**
 * constants.js
 * Objectif : centraliser les datasets par environnement (dev/prod)
 * La variable `dataform.projectConfig.vars.env` vient de Terraform Release Config:
 *  vars = { env = var.environment }
 */

const env = (dataform.projectConfig.vars && dataform.projectConfig.vars.env) || "dev";

module.exports = {
  env,

  // Datasets sources
  rawDataset: `raw_ext_${env}`,         // ex: raw_ext_dev
  curatedExtDataset: `curated_ext_${env}`, // ex: curated_ext_dev (tables externes ICEBERG)

  // Datasets cibles
  analyticsDataset: `analytics_${env}`  // ex: analytics_dev (tables BigQuery natives)
};