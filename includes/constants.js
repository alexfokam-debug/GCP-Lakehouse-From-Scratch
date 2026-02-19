// includes/constants.js
const env = (dataform.projectConfig.vars && dataform.projectConfig.vars.env) || "dev";

module.exports = {
  env,

  projectId: dataform.projectConfig.defaultDatabase, // ou "lakehouse-486419"

  // datasets (dev/prod)
  rawExtDataset: `raw_ext_${env}`,
  curatedExtDataset: `curated_ext_${env}`,
  curatedDataset: `curated_${env}`,
  curatedIcebergDataset: `curated_iceberg_${env}`,
  analyticsDataset: `analytics_${env}`,
  tmpDataset: `tmp_lakehouse_${env}`
};