-- ============================================================
-- 02_curated_sample.sql.tpl
-- Objectif:
--   External (BigLake) -> BigQuery managé (CURATED)
--   Typage strict + colonnes techniques + garde-fous
-- ============================================================

BEGIN
  -- 1) Table managée curated
  CREATE OR REPLACE TABLE `${PROJECT_ID}.${CURATED_DATASET}.sample_curated`
  OPTIONS (
    description = "Curated table built from external Parquet (BigLake).",
    labels = [("layer","curated"), ("env","${ENV}")]
  ) AS
  SELECT
    SAFE_CAST(id AS INT64)       AS id,
    SAFE_CAST(name AS STRING)    AS name,
    SAFE_CAST(amount AS NUMERIC) AS amount,
    SAFE_CAST(ts AS TIMESTAMP)   AS ts,

    -- Colonnes techniques (standard entreprise)
    CURRENT_TIMESTAMP()          AS ingestion_ts,
    "ext_sample_parquet"         AS source_object,
    "${ENV}"                     AS env
  FROM `${PROJECT_ID}.${CURATED_DATASET}.ext_sample_parquet`;

  -- 2) Contrôles minimum (cassent le job si KO)
  ASSERT (SELECT COUNT(*) FROM `${PROJECT_ID}.${CURATED_DATASET}.sample_curated`) > 0
    AS "CURATED sample_curated is empty";

  ASSERT (SELECT COUNT(*) FROM `${PROJECT_ID}.${CURATED_DATASET}.sample_curated` WHERE id IS NULL) = 0
    AS "CURATED: id contains NULLs";

EXCEPTION WHEN ERROR THEN
  -- Optionnel: on pourra logger un FAILED ici plus tard (Cloud Run/Composer)
  RAISE;
END;