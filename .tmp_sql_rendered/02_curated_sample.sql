-- ============================================================
-- 02_curated_sample.sql.tpl
-- Objectif:
--   Transformer la table external (BigLake) en table BigQuery managée
--   avec typage + colonnes techniques (enterprise-ready)
-- ============================================================

-- Convention :
--   - Dataset : ${CURATED_DATASET}
--   - Source : ext_sample_parquet (external table)
--   - Cible  : sample_curated (managed table)

CREATE OR REPLACE TABLE `${PROJECT_ID}.${CURATED_DATASET}.sample_curated`
AS
SELECT
  -- Typage strict (évite les surprises en prod)
  SAFE_CAST(id AS INT64)       AS id,
  SAFE_CAST(name AS STRING)    AS name,
  SAFE_CAST(amount AS NUMERIC) AS amount,
  SAFE_CAST(ts AS TIMESTAMP)   AS ts,

  -- Colonnes techniques “entreprise”
  CURRENT_TIMESTAMP()          AS ingestion_ts,      -- quand on a chargé en curated
  'ext_sample_parquet'         AS source_object,     -- d'où vient la donnée
  '${ENV}'                     AS env                -- traçabilité env
FROM `${PROJECT_ID}.${CURATED_DATASET}.ext_sample_parquet`;

-- Smoke test
SELECT *
FROM `${PROJECT_ID}.${CURATED_DATASET}.sample_curated`
ORDER BY id
LIMIT 10;