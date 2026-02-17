-- ============================================================
-- 01_external_biglake.sql (Enterprise)
-- ============================================================
-- Objectif :
--   Créer une table EXTERNE BigQuery (BigLake) qui lit du PARQUET sur GCS
--
-- Bonnes pratiques "grand groupe" :
--   1) On isole dans un dataset dédié (ex: raw_ext / curated_ext)
--   2) On versionne le SQL (repo Git)
--   3) On évite "OR REPLACE" si on veut éviter les surprises
--      -> ici on peut garder OR REPLACE pour dev, mais pas pour prod.
--
-- Prérequis :
--   - Connection BigLake existe (Terraform) : biglake_conn_dev
--   - Bucket RAW existe et contient les fichiers parquet
-- ============================================================

-- ---------------------------------------------------------------------------
-- PARAMETRES (à adapter)
-- ---------------------------------------------------------------------------
-- NOTE :
-- BigQuery n'a pas un "var" natif dans bq CLI comme Terraform,
-- donc on documente les paramètres et on garde des noms standards.
--
-- project_id = lakehouse-486419
-- dataset    = curated_dev
-- table      = ext_sample_parquet
-- gcs_path   = gs://lakehouse-486419-raw-dev/landing/sample/*.parquet
-- connection = EU.biglake_conn_dev
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- CREATION TABLE EXTERNE
-- ---------------------------------------------------------------------------
-- OR REPLACE :
--   - OK en DEV (tu itères vite)
--   - à éviter en PROD (préférer CREATE IF NOT EXISTS + contrôles)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE EXTERNAL TABLE `lakehouse-486419.curated_dev.ext_sample_parquet`
WITH CONNECTION `EU.biglake_conn_dev`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://lakehouse-486419-raw-dev/landing/sample/*.parquet']
);

-- ---------------------------------------------------------------------------
-- TEST LECTURE (smoke test)
-- ---------------------------------------------------------------------------
-- LIMIT 10 pour vérifier :
-- - droits BigLake OK
-- - format parquet lisible
-- - chemin GCS correct
-- ---------------------------------------------------------------------------

SELECT *
FROM `lakehouse-486419.curated_dev.ext_sample_parquet`
LIMIT 10;