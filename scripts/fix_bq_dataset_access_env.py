#!/usr/bin/env python3
"""
Sanitize BigQuery dataset access entries (env-aware, enterprise-grade).

But:
----
Supprimer les entrées IAM invalides dans les datasets BigQuery
(ex: "deleted:serviceaccount:...") qui cassent Terraform.

Pourquoi ta version a planté ?
------------------------------
Parce que le script utilisait un project_id hardcodé (lakehouse-dev-486419),
alors que ton infra DEV est dans (lakehouse-486419).

Solution entreprise:
--------------------
- On lit *terraform/envs/<env>/terraform.tfvars* (source of truth)
- On récupère project_id + location
- On applique le nettoyage au bon projet/dataset

Usage:
------
python scripts/fix_bq_dataset_access_env.py --env dev --dataset curated_dev
python scripts/fix_bq_dataset_access_env.py --env staging --dataset curated_staging
"""

from __future__ import annotations

import argparse
import os
import re
from typing import Dict, List, Optional

from google.cloud import bigquery


# ============================================================
# 1) Parsing "simple" d'un terraform.tfvars
#    - On veut juste project_id et location
#    - On évite toute dépendance externe
# ============================================================
TFVARS_RE = re.compile(r'^\s*([A-Za-z0-9_]+)\s*=\s*"(.*)"\s*$')


def load_tfvars(env: str) -> Dict[str, str]:
    """
    Lit terraform/envs/<env>/terraform.tfvars et récupère les variables simples.

    ⚠️ On gère ici uniquement le cas "key = \"value\""
    C'est largement suffisant pour project_id/location.
    """
    path = os.path.join("terraform", "envs", env, "terraform.tfvars")
    if not os.path.isfile(path):
        raise FileNotFoundError(f"tfvars introuvable: {path}")

    out: Dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()

            # Ignore commentaires / lignes vides
            if not line or line.startswith("#") or line.startswith("//"):
                continue

            m = TFVARS_RE.match(line)
            if not m:
                # On ignore les structures complexes (maps, lists, etc.)
                continue

            key, val = m.group(1), m.group(2)
            out[key] = val

    return out


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Sanitize BigQuery dataset access entries (env-aware via tfvars).")
    p.add_argument("--env", required=True, help="Environment name (dev/staging/prod)")
    p.add_argument("--dataset", required=True, help="Dataset id (ex: curated_dev)")
    p.add_argument("--dry-run", action="store_true", help="Affiche seulement (ne modifie rien)")
    return p.parse_args()


# ============================================================
# 2) Détection entrée invalide
# ============================================================
def is_invalid_access_entry(entry: bigquery.AccessEntry) -> bool:
    """
    Détermine si une access_entry est invalide.

    Cas réel rencontré:
    - entity_id = "deleted:serviceaccount:....?uid=..."
    BigQuery refuse ensuite les updates IAM du dataset.
    """
    entity_id = getattr(entry, "entity_id", None)
    if not entity_id:
        return False

    # On supprime tout ce qui commence par "deleted:"
    return entity_id.lower().startswith("deleted:")


def main() -> int:
    args = parse_args()

    # ============================================================
    # 3) Source de vérité: tfvars
    # ============================================================
    tfvars = load_tfvars(args.env)

    # Ici tu récupères les noms EXACTS de tes variables terraform.tfvars
    project_id = tfvars.get("project_id")
    location = tfvars.get("location") or tfvars.get("region")

    if not project_id:
        raise ValueError(
            "Impossible de trouver project_id dans terraform.tfvars. "
            "Vérifie envs/<env>/terraform.tfvars"
        )
    if not location:
        raise ValueError(
            "Impossible de trouver location (ou region) dans terraform.tfvars. "
            "Vérifie envs/<env>/terraform.tfvars"
        )

    print("==========================================")
    print("BigQuery Dataset Access Sanitizer")
    print("==========================================")
    print(f"ENV     : {args.env}")
    print(f"Project : {project_id}")
    print(f"Region  : {location}")
    print(f"Dataset : {args.dataset}")
    print(f"Dry run : {args.dry_run}")
    print("")

    # ============================================================
    # 4) Client BigQuery (ADC)
    # ============================================================
    client = bigquery.Client(project=project_id, location=location)

    # ============================================================
    # 5) Charger le dataset
    # ============================================================
    dataset_ref = bigquery.DatasetReference(project_id, args.dataset)
    dataset = client.get_dataset(dataset_ref)

    entries: List[bigquery.AccessEntry] = list(dataset.access_entries or [])

    print(f"ℹ️  Access entries (avant) : {len(entries)}")

    invalid = [e for e in entries if is_invalid_access_entry(e)]
    valid = [e for e in entries if not is_invalid_access_entry(e)]

    print(f"⚠️  Entrées invalides : {len(invalid)}")
    print(f"✅ Entrées valides   : {len(valid)}")
    print("")

    if not invalid:
        print("✅ Rien à nettoyer. Tu peux relancer Terraform.")
        return 0

    print("---- Entrées supprimées ----")
    for e in invalid:
        print(f"- role={getattr(e,'role',None)} | type={getattr(e,'entity_type',None)} | id={getattr(e,'entity_id',None)}")
    print("----------------------------\n")

    if args.dry_run:
        print("🟡 Dry-run: aucune modification envoyée.")
        return 0

    # ============================================================
    # 6) Patch dataset (seulement access_entries)
    # ============================================================
    dataset.access_entries = valid
    client.update_dataset(dataset, ["access_entries"])

    print("✅ Nettoyage appliqué.")
    print(f"➡️ Relance maintenant : make tf-apply ENV={args.env}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())