-- ============================================================
-- 99_quality_checks.sql.tpl
-- Objectif:
--   Contrôles transverses (qualité) après exécution des layers
--   -> si un test échoue, le run doit échouer
-- ============================================================

BEGIN
  -- Exemples de checks globaux
  ASSERT (
    SELECT COUNT(*) FROM `${PROJECT_ID}.${CURATED_DATASET}.sample_curated`
  ) > 0 AS "Q: sample_curated empty";

  ASSERT (
    SELECT COUNT(*) FROM `${PROJECT_ID}.${CURATED_DATASET}.sample_curated`
    WHERE amount < 0
  ) = 0 AS "Q: negative amounts found";

  ASSERT (
    SELECT COUNT(*) FROM `${PROJECT_ID}.${CURATED_DATASET}.amount_by_name_gold`
  ) > 0 AS "Q: amount_by_name_gold empty";

EXCEPTION WHEN ERROR THEN
  RAISE;
END;