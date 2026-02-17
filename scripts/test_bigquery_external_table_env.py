# scripts/test_bigquery_external_table_env.py
from __future__ import annotations

import argparse
from google.cloud import bigquery

from scripts._env import load_env_config, get_required


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="BigQuery Automated Test (External Table) - ENV aware")
    p.add_argument("--env", required=True, choices=["dev", "staging", "prod"])
    p.add_argument("--table", required=True, help="Table name (ex: sample_ext)")
    p.add_argument("--limit", type=int, default=5)
    return p.parse_args()


def main() -> int:
    args = parse_args()
    cfg = load_env_config(args.env)

    project_id = get_required(cfg, "project_id")
    location = get_required(cfg, "location")
    dataset_id = get_required(cfg, "bq.raw_dataset")

    print("==========================================")
    print("BigQuery Automated Test (External Table)")
    print("==========================================")
    print(f"ENV     : {args.env}")
    print(f"Project : {project_id}")
    print(f"Dataset : {dataset_id}")
    print(f"Table   : {args.table}")
    print(f"Region  : {location}")
    print("")

    client = bigquery.Client(project=project_id, location=location)

    # dataset check
    ds_ref = bigquery.DatasetReference(project_id, dataset_id)
    client.get_dataset(ds_ref)
    print(f"✅ Dataset trouvé : {project_id}:{dataset_id}")

    # table check
    table_ref = ds_ref.table(args.table)
    table_obj = client.get_table(table_ref)
    print(f"✅ Table trouvée : {project_id}:{dataset_id}.{args.table}")
    print(f"ℹ️  Type table : {table_obj.table_type}")
    print(f"ℹ️  Schéma : {len(table_obj.schema)} colonnes")

    sql = f"SELECT * FROM `{project_id}.{dataset_id}.{args.table}` LIMIT {args.limit}"
    print("ℹ️  Lancement requête de test :")
    print(f"ℹ️  {sql}")

    rows = list(client.query(sql).result())
    print(f"✅ Query OK. Lignes récupérées : {len(rows)}")
    if rows:
        print("ℹ️  Exemple 1ère ligne (dict) :")
        print(f"ℹ️  {dict(rows[0])}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())