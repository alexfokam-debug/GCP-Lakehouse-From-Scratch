-- ============================================================
-- 03_gold_amount_by_name.sql.tpl
-- Objectif:
--   Agrégat GOLD (table de restitution) à partir du curated
-- ============================================================

BEGIN
  CREATE OR REPLACE TABLE `${PROJECT_ID}.${CURATED_DATASET}.amount_by_name_gold`
  OPTIONS (
    description = "Gold aggregate: amount KPIs by name.",
    labels = [("layer","gold"), ("env","${ENV}")]
  ) AS
  SELECT
    name,
    COUNT(*)            AS nb_rows,
    SUM(amount)         AS total_amount,
    MIN(ts)             AS first_ts,
    MAX(ts)             AS last_ts,
    CURRENT_TIMESTAMP() AS built_ts,
    "${ENV}"            AS env
  FROM `${PROJECT_ID}.${CURATED_DATASET}.sample_curated`
  GROUP BY name;

  -- Tests minimum GOLD
  ASSERT (SELECT COUNT(*) FROM `${PROJECT_ID}.${CURATED_DATASET}.amount_by_name_gold`) > 0
    AS "GOLD amount_by_name_gold is empty";

  ASSERT (SELECT COUNT(*) FROM `${PROJECT_ID}.${CURATED_DATASET}.amount_by_name_gold` WHERE name IS NULL) = 0
    AS "GOLD: name contains NULLs";

EXCEPTION WHEN ERROR THEN
  RAISE;
END;