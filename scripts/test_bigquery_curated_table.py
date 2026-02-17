#!/usr/bin/env python3
"""
==========================================
BigQuery Automated Test (CURATED table)
==========================================

Objectif :
- Vérifier automatiquement que la table CURATED existe
- Vérifier qu'elle contient au moins 1 ligne
- (Optionnel) afficher 1 ligne exemple

Pourquoi c'est "entreprise" ?
- Un pipeline CI/CD a besoin de "checks" après transformation
- Un test simple de smoke-test évite de déployer une prod cassée

Usage:
  python scripts/test_bigquery_curated_table.py \
    --project lakehouse-stg-486419 \
    --dataset curated_staging \
    --table stg_sample \
    --region europe-west1 \
    --min-rows 1 \
    --limit 5
"""

from __future__ import annotations

import argparse
from google.api_core.exceptions import NotFound, BadRequest
from google.cloud import bigquery


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Automated smoke-test for a curated BigQuery table.")
    p.add_argument("--project", required=True, help="GCP project id")
    p.add_argument("--dataset", required=True, help="Dataset (ex: curated_staging)")
    p.add_argument("--table", required=True, help="Table (ex: stg_sample)")
    p.add_argument("--region", required=True, help="BQ region (ex: europe-west1)")
    p.add_argument("--min-rows", type=int, default=1, help="Minimum rows expected (default: 1)")
    p.add_argument("--limit", type=int, default=5, help="Preview rows (default: 5)")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    print("==========================================")
    print("BigQuery Automated Test (CURATED)")
    print("==========================================")
    print(f"Project : {args.project}")
    print(f"Dataset : {args.dataset}")
    print(f"Table   : {args.table}")
    print(f"Region  : {args.region}")
    print("")

    client = bigquery.Client(project=args.project, location=args.region)

    table_ref = f"{args.project}.{args.dataset}.{args.table}"

    # 1) Vérifier que la table existe
    try:
        tbl = client.get_table(table_ref)
        print(f"✅ Table trouvée : {tbl.full_table_id}")
        print(f"ℹ️  Type table   : {tbl.table_type}")
        print(f"ℹ️  Colonnes     : {len(tbl.schema)}")
    except NotFound:
        print(f"❌ Table introuvable : {table_ref}")
        return 1

    # 2) Vérifier qu'il y a des lignes
    count_sql = f"SELECT COUNT(1) AS cnt FROM `{table_ref}`"
    try:
        cnt = list(client.query(count_sql).result())[0]["cnt"]
        print(f"ℹ️  Row count = {cnt}")
    except BadRequest as e:
        print(f"❌ Query COUNT failed: {e}")
        return 1

    if cnt < args.min_rows:
        print(f"❌ Pas assez de lignes: {cnt} < {args.min_rows}")
        return 1

    # 3) Petite preview (smoke-test)
    preview_sql = f"SELECT * FROM `{table_ref}` LIMIT {args.limit}"
    rows = list(client.query(preview_sql).result())
    print(f"✅ Preview OK. Lignes récupérées : {len(rows)}")
    if rows:
        print("ℹ️  Exemple 1ère ligne (dict) :")
        print(dict(rows[0]))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())