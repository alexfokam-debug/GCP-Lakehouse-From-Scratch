# jobs/iceberg_writer/create_iceberg_tables.py
from __future__ import annotations

import argparse
import sys
import traceback

from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.utils import AnalysisException

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Read BigQuery table and write Iceberg table (GCS warehouse).")
    p.add_argument("--project_id", required=True)
    p.add_argument("--raw_table", required=True, help="dataset.table (ex: raw_ext_dev.sample_ext)")
    p.add_argument("--iceberg_catalog", required=True)
    p.add_argument("--iceberg_db", required=True)
    p.add_argument("--iceberg_table", required=True)
    p.add_argument("--mode", default="overwrite", choices=["overwrite", "append"])
    p.add_argument("--debug", action="store_true")
    p.add_argument("--temporary_gcs_bucket", required=True,
                   help="Bucket GCS temporaire pour BigQuery connector")
    return p.parse_args()


def log(msg: str) -> None:
    print(msg, flush=True)


def build_spark(app_name: str, debug: bool = False) -> SparkSession:
    builder = SparkSession.builder.appName(app_name)
    if debug:
        builder = builder.config("spark.sql.debug.maxToStringFields", "200")
    return builder.getOrCreate()


def print_runtime_diagnostics(spark: SparkSession, iceberg_catalog: str, project_id: str, raw_table: str) -> None:
    log("============================================================")
    log(" Dataproc Serverless - Runtime Diagnostics")
    log("============================================================")
    log(f"Spark version                 : {spark.version}")
    log(f"project_id                    : {project_id}")
    log(f"raw_table (dataset.table)     : {raw_table}")
    log("------------------------------------------------------------")
    log(f"spark.sql.extensions          : {spark.conf.get('spark.sql.extensions', '')}")
    log(f"spark.sql.catalog.{iceberg_catalog}         : {spark.conf.get(f'spark.sql.catalog.{iceberg_catalog}', '')}")
    log(f"spark.sql.catalog.{iceberg_catalog}.type    : {spark.conf.get(f'spark.sql.catalog.{iceberg_catalog}.type', '')}")
    log(f"spark.sql.catalog.{iceberg_catalog}.warehouse: {spark.conf.get(f'spark.sql.catalog.{iceberg_catalog}.warehouse', '')}")
    log(f"spark.bigquery.temporaryGcsBucket: {spark.conf.get('spark.bigquery.temporaryGcsBucket', '')}")
    log("============================================================")


def assert_iceberg_config(spark: SparkSession, iceberg_catalog: str) -> None:
    cat_impl = spark.conf.get(f"spark.sql.catalog.{iceberg_catalog}", "")
    cat_wh = spark.conf.get(f"spark.sql.catalog.{iceberg_catalog}.warehouse", "")
    if not cat_impl or not cat_wh:
        log("[ERREUR] Iceberg catalog non configuré dans Spark (properties côté submit).")
        sys.exit(2)


def read_bigquery_table(
    spark: SparkSession,
    project_id: str,
    raw_table: str,
    temporary_gcs_bucket: str
) -> DataFrame:
    """
    Lecture d'une table BigQuery via le connector Spark BigQuery.

    Parameters
    ----------
    project_id : str
        Projet GCP
    raw_table : str
        dataset.table (ex: raw_ext_dev.sample_ext)
    temporary_gcs_bucket : str
        Bucket GCS temporaire utilisé par le connector
    """

    bq_fqn = f"{project_id}.{raw_table}"

    log("------------------------------------------------------------")
    log("==> Lecture BigQuery via QUERY (external table safe mode)")
    log(f"    table : {bq_fqn}")
    log("------------------------------------------------------------")

    sql = f"SELECT * FROM `{bq_fqn}`"

    df = (
        spark.read.format("bigquery")
        .option("query", sql)
        .option("viewsEnabled", "true")
        .option("materializationProject", project_id)
        .option("materializationDataset", "tmp_lakehouse_dev")
        .load()
    )

    log("==> OK - BigQuery query initialisée")
    return df


# ============================================================
# BigQuery - Ensure materialization dataset exists
# ============================================================

from google.cloud import bigquery
from google.api_core.exceptions import NotFound


def ensure_bq_dataset_exists(
        project_id: str,
        dataset_id: str,
        location: str = "europe-west1"
) -> None:
    """
    Crée un dataset BigQuery s'il n'existe pas.

    Parameters
    ----------
    project_id : str
        Projet GCP
    dataset_id : str
        Nom du dataset (ex: tmp_lakehouse_dev)
    location : str
        Région BigQuery (doit matcher celle du dataset source)
    """

    print("------------------------------------------------------------")
    print("==> Vérification dataset de matérialisation BigQuery")
    print(f"    project_id : {project_id}")
    print(f"    dataset_id : {dataset_id}")
    print(f"    location   : {location}")
    print("------------------------------------------------------------")

    client = bigquery.Client(project=project_id)

    dataset_ref = f"{project_id}.{dataset_id}"

    try:
        client.get_dataset(dataset_ref)
        print("==> Dataset déjà existant ✅")

    except NotFound:
        print("==> Dataset non trouvé, création en cours...")

        dataset = bigquery.Dataset(dataset_ref)
        dataset.location = location

        client.create_dataset(dataset)

        print("==> Dataset créé avec succès ✅")

def sanity_check_bigquery(df: DataFrame) -> None:
    _ = df.limit(1).collect()
    log("==> OK - BigQuery access check (limit(1))")


def ensure_namespace(spark: SparkSession, namespace_fqn: str) -> None:
    log(f"==> Ensure namespace: {namespace_fqn}")
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {namespace_fqn}")


def write_iceberg_writeTo(df: DataFrame, table_fqn: str, mode: str) -> None:
    log(f"==> Iceberg writeTo: {table_fqn}")
    if mode == "overwrite":
        df.writeTo(table_fqn).createOrReplace()
    else:
        df.writeTo(table_fqn).append()


def write_iceberg_sql_fallback(spark: SparkSession, df: DataFrame, table_fqn: str, mode: str) -> None:
    log(f"[WARN] Fallback SQL Iceberg: {table_fqn}")
    df.createOrReplaceTempView("tmp_raw")
    if mode == "overwrite":
        spark.sql(f"DROP TABLE IF EXISTS {table_fqn}")
        spark.sql(f"CREATE TABLE {table_fqn} USING iceberg AS SELECT * FROM tmp_raw")
    else:
        spark.sql(f"INSERT INTO {table_fqn} SELECT * FROM tmp_raw")


def main() -> None:
    args = parse_args()

    namespace = f"{args.iceberg_catalog}.{args.iceberg_db}"
    table_fqn = f"{args.iceberg_catalog}.{args.iceberg_db}.{args.iceberg_table}"



    spark = build_spark("iceberg-create-tables", debug=args.debug)
    log(f"Spark version: {spark.version}")
    log(f"Scala version: {spark.sparkContext._jvm.scala.util.Properties.versionNumberString()}")

    try:
        print_runtime_diagnostics(spark, args.iceberg_catalog, args.project_id, args.raw_table)
        assert_iceberg_config(spark, args.iceberg_catalog)

        ensure_bq_dataset_exists(
            project_id=args.project_id,
            dataset_id="tmp_lakehouse_dev",
            location="europe-west1"
        )

        df = read_bigquery_table(
            spark,
            args.project_id,
            args.raw_table,
            args.temporary_gcs_bucket
        )
        sanity_check_bigquery(df)

        ensure_namespace(spark, namespace)

        try:
            write_iceberg_writeTo(df, table_fqn, args.mode)
            log("==> OK - Iceberg writeTo ✅")
        except Exception:
            log(traceback.format_exc())
            write_iceberg_sql_fallback(spark, df, table_fqn, args.mode)
            log("==> OK - Iceberg SQL fallback ✅")

        # validation lecture
        _ = spark.read.table(table_fqn).limit(1).collect()
        log("✅ Job terminé avec succès.")
        spark.stop()

    except AnalysisException:
        log("[ERREUR] Spark AnalysisException")
        log(traceback.format_exc())
        spark.stop()
        sys.exit(1)
    except Exception:
        log("[ERREUR] Job failed")
        log(traceback.format_exc())
        spark.stop()
        sys.exit(1)


if __name__ == "__main__":
    main()