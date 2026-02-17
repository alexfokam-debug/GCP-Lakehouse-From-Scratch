# ------------------------------------------------------------------------------
# jobs/iceberg_writer/create_iceberg_tables.py
#
# Objectif (Lakehouse "mode entreprise")
# -------------------------------------
# Lire une table BigQuery (external RAW) et l’écrire dans une table Iceberg
# stockée dans un warehouse GCS, via un catalog Iceberg (SparkCatalog).
#
# Pourquoi ce script ?
# - Spark ne sait PAS lire une table BigQuery via `spark.read.table(...)`
#   (ça ne marche que pour les tables connues du catalog Spark).
# - Pour BigQuery : on utilise le connector Spark BigQuery :
#     spark.read.format("bigquery").option("table", "...").load()
#
# Prérequis côté submit (Dataproc Serverless)
# -------------------------------------------
# 1) Connector BigQuery présent (au choix)
#    - soit via --properties spark.jars.packages=...spark-bigquery...
#    - soit via une image/container avec le jar déjà présent
#
# 2) Bucket de staging BigQuery (très recommandé)
#    - --properties spark.bigquery.temporaryGcsBucket=<bucket>
#    - ex: lakehouse-486419-dataproc-temp-dev
#
# 3) Iceberg package adapté AU runtime Dataproc
#    - Dataproc Serverless runtime 2.2 => Spark 3.5.x
#    - Donc Iceberg runtime doit être "iceberg-spark-runtime-3.5_2.12"
#      (sinon erreur type NoClassDefFoundError: scala/Serializable)
#
# 4) IAM (service account Dataproc)
#    - BigQuery: roles/bigquery.jobUser (projet)
#    - BigQuery: roles/bigquery.dataViewer (dataset raw_ext_dev)
#    - GCS temp bucket: droit d'écrire (roles/storage.objectAdmin ou équivalent)
#    - GCS warehouse Iceberg: droit d'écrire
#
# Comportement
# ------------
# - Vérifie la config Iceberg (catalog, warehouse, extensions)
# - Vérifie l'accès à BigQuery (dry-run: lecture schema + 1 action légère)
# - Crée le namespace Iceberg si besoin
# - Écrit en priorité via DataFrameWriterV2 `writeTo(...).createOrReplace()`
# - Fallback en SQL CTAS si writeTo échoue
#
# Notes de perf
# -------------
# - Pas de df.count() en prod (ça scanne toute la table)
# - On log plutôt `df.schema`, `df.rdd.getNumPartitions()`, un `limit(10)` si besoin.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# create_iceberg_tables.py
#
# OBJECTIF
# --------
# Ce job PySpark (Dataproc Serverless) fait :
#   1) Lecture d'une table BigQuery (typiquement RAW externe)
#   2) Écriture dans une table Apache Iceberg (catalog SparkCatalog + warehouse GCS)
#
# CONTEXTE "ENTREPRISE"
# ---------------------
# - Logs très explicites (pour debug prod)
# - Vérifications de configuration Spark (extensions + catalog Iceberg)
# - Lecture BigQuery robuste (via spark-bigquery connector)
# - Création du namespace Iceberg si absent
# - 2 stratégies d'écriture :
#       A) df.writeTo(...).createOrReplace()  (Spark 3 + Iceberg v2)
#       B) fallback SQL CTAS si writeTo() échoue
#
# REMARQUES IMPORTANTES
# ---------------------
# 1) Pour lire BigQuery de manière fiable, on recommande :
#       spark.bigquery.temporaryGcsBucket=<bucket staging>
#    (sinon certains jobs échouent selon volumétrie/runtime)
#
# 2) Si tu vois une erreur scala/Serializable :
#    => problème de classpath Scala/Iceberg (à corriger côté spark.jars.packages)
#
# ------------------------------------------------------------------------------

import argparse
import sys
import traceback
from datetime import datetime
from pyspark.sql import SparkSession


# ------------------------------------------------------------------------------
# CLI ARGS
# ------------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    """
    Arguments passés par ton CLI (gcloud dataproc batches submit pyspark ... -- <args>)

    Exemple :
        --project_id=lakehouse-486419
        --raw_table=raw_ext_dev.sample_ext
        --iceberg_catalog=lakehouse
        --iceberg_db=curated_iceberg_dev
        --iceberg_table=sample_ext
    """
    p = argparse.ArgumentParser(description="Read BigQuery table and write Iceberg table")
    p.add_argument("--project_id", required=True, help="GCP project id (BigQuery)")
    p.add_argument("--raw_table", required=True, help="BigQuery dataset.table (ex: raw_ext_dev.sample_ext)")
    p.add_argument("--iceberg_catalog", required=True, help="Spark catalog name (ex: lakehouse)")
    p.add_argument("--iceberg_db", required=True, help="Iceberg namespace / db (ex: curated_iceberg_dev)")
    p.add_argument("--iceberg_table", required=True, help="Iceberg table name (ex: sample_ext)")
    return p.parse_args()


# ------------------------------------------------------------------------------
# LOGGING SIMPLE (stdout)
# ------------------------------------------------------------------------------
def log(msg: str) -> None:
    """
    Log simple en stdout (Dataproc capture ça dans driveroutput).
    """
    print(msg, flush=True)


def banner(title: str) -> None:
    log("\n" + "=" * 78)
    log(title)
    log("=" * 78)


# ------------------------------------------------------------------------------
# SPARK SESSION / DIAGNOSTICS
# ------------------------------------------------------------------------------
def build_spark(app_name: str) -> SparkSession:
    """
    Crée une SparkSession. Toute la conf Iceberg + BigQuery connector
    doit être injectée via --properties côté Dataproc Serverless.

    => Ici on ne fait PAS .config(...) car on veut garder le job "portable"
    et piloté par l'orchestrateur.
    """
    return SparkSession.builder.appName(app_name).getOrCreate()


def log_runtime_diagnostics(spark: SparkSession, iceberg_catalog: str) -> None:
    """
    Imprime les propriétés Spark "critiques" pour déboguer en prod.
    Très utile quand un job casse au runtime.
    """
    banner("Dataproc Serverless - Runtime Diagnostics")

    # Extensions (Iceberg)
    ext = spark.conf.get("spark.sql.extensions", "")
    log(f"spark.sql.extensions = {ext}")

    # Catalog Iceberg (SparkCatalog)
    cat_impl = spark.conf.get(f"spark.sql.catalog.{iceberg_catalog}", "")
    cat_type = spark.conf.get(f"spark.sql.catalog.{iceberg_catalog}.type", "")
    cat_wh = spark.conf.get(f"spark.sql.catalog.{iceberg_catalog}.warehouse", "")

    log(f"spark.sql.catalog.{iceberg_catalog}           = {cat_impl}")
    log(f"spark.sql.catalog.{iceberg_catalog}.type      = {cat_type}")
    log(f"spark.sql.catalog.{iceberg_catalog}.warehouse = {cat_wh}")

    # BigQuery staging bucket (souvent oublié)
    tmp_bucket = spark.conf.get("spark.bigquery.temporaryGcsBucket", "")
    log(f"spark.bigquery.temporaryGcsBucket = {tmp_bucket}")

    log("-" * 78)


def assert_iceberg_catalog_is_configured(spark: SparkSession, iceberg_catalog: str) -> None:
    """
    Stoppe le job si le catalog Iceberg n'est pas configuré.
    Sinon tu vas avoir des erreurs cryptiques plus loin.
    """
    cat_impl = spark.conf.get(f"spark.sql.catalog.{iceberg_catalog}", "")
    if not cat_impl:
        banner("ERREUR - Iceberg catalog non configuré")
        log(
            "Le catalog Iceberg n'est pas configuré dans Spark.\n"
            "=> Ton batch Dataproc doit fournir --properties avec (exemple) :\n"
            f"   spark.sql.catalog.{iceberg_catalog}=org.apache.iceberg.spark.SparkCatalog\n"
            f"   spark.sql.catalog.{iceberg_catalog}.type=hadoop\n"
            f"   spark.sql.catalog.{iceberg_catalog}.warehouse=gs://.../warehouse\n"
            f"   spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions\n"
        )
        sys.exit(2)


# ------------------------------------------------------------------------------
# BIGQUERY READ
# ------------------------------------------------------------------------------
def read_bigquery_table(spark: SparkSession, project_id: str, raw_table: str, temp_bucket: str):
    """
    IMPORTANT:
    - readMethod=indirect => évite BigQuery Storage API (qui bloque sur certaines external tables)
    - temporaryGcsBucket obligatoire en indirect
    """
    bq_fqn = f"{project_id}.{raw_table}"

    df = (
        spark.read.format("bigquery")
        .option("table", bq_fqn)
        .option("readMethod", "indirect")              # <-- FIX
        .option("temporaryGcsBucket", temp_bucket)     # <-- FIX
        .load()
    )
    # En prod, éviter df.count() (ça déclenche un full scan).
    # Ici on log juste le schema + un sample.
    log("BigQuery read OK ✅")
    log("Schema:")
    df.printSchema()

    log("Sample rows (limit 5):")
    df.show(5, truncate=False)

    return df


# ------------------------------------------------------------------------------
# ICEBERG WRITE
# ------------------------------------------------------------------------------
def ensure_namespace(spark: SparkSession, iceberg_namespace: str) -> None:
    """
    Crée le namespace Iceberg s'il n'existe pas.
    Non-bloquant si déjà présent.
    """
    banner("STEP 2 - Ensure Iceberg namespace")
    log(f"Creating namespace if not exists: {iceberg_namespace}")

    try:
        spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {iceberg_namespace}")
        log("Namespace OK ✅")
    except Exception:
        log("[WARN] CREATE NAMESPACE failed (not blocking if already exists).")
        log(traceback.format_exc())


def write_iceberg_writeTo(df, iceberg_fqn: str) -> None:
    """
    Méthode 1 (préférée) : DataFrameWriterV2 writeTo()
    - clean
    - gère mieux la table Iceberg (metadata, etc.)
    """
    banner("STEP 3A - Write Iceberg (writeTo)")
    log(f"Writing Iceberg table with writeTo(): {iceberg_fqn}")

    # createOrReplace() : pratique en dev
    # En prod, tu peux préférer .create() + gérer le mode update séparément
    df.writeTo(iceberg_fqn).createOrReplace()

    log("Iceberg writeTo OK ✅")


def write_iceberg_sql_ctas(df, spark: SparkSession, iceberg_fqn: str) -> None:
    """
    Méthode 2 (fallback) : CTAS
    - utile si writeTo() échoue selon versions Spark/Iceberg
    """
    banner("STEP 3B - Write Iceberg (SQL CTAS fallback)")
    log(f"Writing Iceberg table with SQL CTAS: {iceberg_fqn}")

    # On passe par une temp view pour CTAS
    tmp_view = "tmp_raw"
    df.createOrReplaceTempView(tmp_view)

    # Drop si existe (dev)
    spark.sql(f"DROP TABLE IF EXISTS {iceberg_fqn}")

    # CTAS Iceberg
    spark.sql(f"""
        CREATE TABLE {iceberg_fqn}
        USING iceberg
        AS SELECT * FROM {tmp_view}
    """)

    log("Iceberg SQL CTAS OK ✅")


# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
def main() -> None:
    args = parse_args()

    # Identifiants Iceberg
    iceberg_namespace = f"{args.iceberg_catalog}.{args.iceberg_db}"
    iceberg_fqn = f"{args.iceberg_catalog}.{args.iceberg_db}.{args.iceberg_table}"

    banner("Iceberg writer job - START")
    log(f"Start time UTC: {datetime.utcnow().isoformat()}Z")
    log(f"Args: {vars(args)}")
    log(f"Iceberg namespace: {iceberg_namespace}")
    log(f"Iceberg table FQN: {iceberg_fqn}")

    spark = None
    try:
        # 0) Spark init
        spark = build_spark(app_name="iceberg-writer")

        # 0.1) Diagnostics
        log_runtime_diagnostics(spark, args.iceberg_catalog)

        # 0.2) Hard check catalog
        assert_iceberg_catalog_is_configured(spark, args.iceberg_catalog)

        # 1) Read BigQuery
        df = read_bigquery_table(spark, args.project_id, args.raw_table)

        # 2) Ensure namespace
        ensure_namespace(spark, iceberg_namespace)

        # 3) Write Iceberg
        # On tente writeTo en premier, sinon fallback CTAS.
        try:
            write_iceberg_writeTo(df, iceberg_fqn)
        except Exception:
            log("[WARN] writeTo() failed, switching to SQL CTAS fallback.")
            log(traceback.format_exc())
            write_iceberg_sql_ctas(df, spark, iceberg_fqn)

        banner("Iceberg writer job - SUCCESS ✅")
        log(f"End time UTC: {datetime.utcnow().isoformat()}Z")

    except Exception:
        banner("Iceberg writer job - FAILED ❌")
        log(traceback.format_exc())
        sys.exit(1)

    finally:
        if spark is not None:
            try:
                spark.stop()
            except Exception:
                pass


if __name__ == "__main__":
    main()