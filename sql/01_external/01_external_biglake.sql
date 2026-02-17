-- ============================================================
-- 01_external_biglake.sql
-- Objectif :
--   Créer une table externe BigLake dans BigQuery qui lit des fichiers
--   stockés dans GCS (RAW bucket) via une BigQuery Connection.
-- ============================================================

-- ⚠️ Remplace :
--   - PROJECT_ID
--   - ENV (dev)
--   - BUCKET_RAW
--   - Le chemin des fichiers (ex: /sample/*.parquet)

CREATE OR REPLACE EXTERNAL TABLE `lakehouse-486419.curated_dev.ext_sample_raw`
WITH CONNECTION `EU.biglake_conn_dev`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://lakehouse-486419-raw-dev/landing/sample/*.parquet']
);


-- Exemple concret attendu :
-- PROJECT_ID = lakehouse-486419
-- ENV        = dev
-- BUCKET_RAW = lakehouse-486419-raw-dev
-- Connection = lakehouse-486419.EU.biglake_conn_dev
