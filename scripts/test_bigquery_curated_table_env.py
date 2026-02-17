#!/usr/bin/env python3
"""
Test BigQuery CURATED (ENV aware) - MODE ENTREPRISE
==================================================

Objectif:
- Valider qu'une table CURATED existe ET contient au moins N lignes
- Utilisable en local + CI
- Retourne code != 0 si KO

Usage:
  python -m scripts.test_bigquery_curated_table_env \
    --env dev --table stg_sample --min-rows 1 --limit 5
"""

from __future__ import annotations

import argparse
from google.cloud import bigquery

from scripts._env import load_env_config, get_required


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Test curated BigQuery table (ENV aware).")
    p.add_argument("--env", required=True, choices=["dev", "staging", "prod"])
    p.add_argument("--table", required=True, help="Table name (ex: stg_sample)")
    p.add_argument("--min-rows", type=int, default=1, help="Minimum expected row count")
    p.add_argument("--limit", type=int, default=5, help="Preview limit")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    cfg = load_env_config(args.env)

    project_id = get_required(cfg, "project_id")
    dataset_id = get_required(cfg, "bq.curated_dataset")

    print("==========================================")
    print("BigQuery Automated Test (CURATED)")
    print("==========================================")
    print(f"ENV     : {args.env}")
    print(f"Project : {project_id}")
    print(f"Dataset : {dataset_id}")
    print(f"Table   : {args.table}")
    print("")

    client = bigquery.Client(project=project_id)
    table_ref = f"{project_id}.{dataset_id}.{args.table}"

    # 1) Check existence
    try:
        table = client.get_table(table_ref)
    except Exception as e:
        print(f"❌ Table introuvable : {table_ref}")
        print(f"❌ {e}")
        return 2

    print(f"✅ Table trouvée : {table.project}:{table.dataset_id}.{table.table_id}")

    # 2) Row count (cheap)
    sql_count = f"SELECT COUNT(1) AS cnt FROM `{table_ref}`"
    cnt = list(client.query(sql_count).result())[0]["cnt"]
    print(f"ℹ️  Row count = {cnt}")

    if cnt < args.min_rows:
        print(f"❌ Pas assez de lignes: {cnt} < min={args.min_rows}")
        return 3

    # 3) Preview rows
    sql_preview = f"SELECT * FROM `{table_ref}` LIMIT {args.limit}"
    rows = list(client.query(sql_preview).result())
    print(f"✅ Preview OK. Lignes récupérées : {len(rows)}")
    if rows:
        print(f"ℹ️  Exemple 1ère ligne : {dict(rows[0])}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())