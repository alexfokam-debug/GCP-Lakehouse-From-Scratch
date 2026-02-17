#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="lakehouse-486419"
REGION="europe-west1"
ENV="dev"

SCRIPTS_BUCKET="${PROJECT_ID}-scripts-${ENV}"
ICEBERG_BUCKET="${PROJECT_ID}-iceberg-${ENV}"
WAREHOUSE_URI="gs://${ICEBERG_BUCKET}/warehouse"

LOCAL_PYSPARK="scripts/iceberg/create_iceberg_tables.py"
GCS_PYSPARK="gs://${SCRIPTS_BUCKET}/iceberg/create_iceberg_tables.py"

BATCH_ID="iceberg-${ENV}-$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo " Dataproc Serverless Iceberg - START"
echo " PROJECT_ID : ${PROJECT_ID}"
echo " REGION     : ${REGION}"
echo " ENV        : ${ENV}"
echo " SCRIPTS    : ${SCRIPTS_BUCKET}"
echo " ICEBERG    : ${ICEBERG_BUCKET}"
echo " WAREHOUSE  : ${WAREHOUSE_URI}"
echo " BATCH_ID   : ${BATCH_ID}"
echo "============================================================"

echo "==> Upload du script PySpark sur GCS..."
gsutil cp "${LOCAL_PYSPARK}" "${GCS_PYSPARK}"

# Dataproc Serverless runtime 2.2 = Spark 3.5.x => jar Iceberg runtime 3.5
ICEBERG_VERSION="1.10.0"

PROPS="spark.jars.packages=org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:${ICEBERG_VERSION},spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions,spark.sql.catalog.lakehouse=org.apache.iceberg.spark.SparkCatalog,spark.sql.catalog.lakehouse.type=hadoop,spark.sql.catalog.lakehouse.warehouse=${WAREHOUSE_URI},dataproc.driver.cores=2,dataproc.driver.memory=4g,dataproc.executor.cores=2,dataproc.executor.memory=4g,dataproc.executor.instances=2,dataproc.driver.disk.size=50,dataproc.executor.disk.size=100"
gcloud dataproc batches submit pyspark "${GCS_PYSPARK}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --batch="${BATCH_ID}" \
  --version="2.2" \
  --service-account="sa-dataproc-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --properties="${PROPS}" \
  -- \
  --project_id="${PROJECT_ID}" \
  --raw_table="raw_ext_${ENV}.sample_ext" \
  --iceberg_catalog="lakehouse" \
  --iceberg_db="curated_iceberg_${ENV}" \
  --iceberg_table="sample_ext"

echo "============================================================"
echo " Dataproc Serverless Iceberg - SUBMITTED"
echo "============================================================"