#!/usr/bin/env python3
"""
create_tf_backend_bucket.py
===========================

Objectif
--------
Terraform utilise un "backend" pour stocker son état (tfstate).
Dans ton cas, le backend est sur GCS, et `terraform init` échoue avec :
    "storage: bucket doesn't exist"

Ce script :
- lit le fichier backend.hcl d'un environnement (dev/staging/prod)
- récupère automatiquement le nom du bucket (et optionnellement prefix)
- crée le bucket GCS s'il n'existe pas
- active le versioning (recommandé pour sécuriser le tfstate)

Pré-requis
----------
1) gcloud installé et authentifié :
   gcloud auth login
   gcloud auth application-default login
2) Avoir les droits sur le projet (Storage Admin ou équivalent)

Usage
-----
python scripts/create_tf_backend_bucket.py --env staging --project lakehouse-stg-486419 --location europe-west1

Notes
-----
- Le nom du bucket doit être globalement unique sur GCS.
- Le bucket doit être dans le BON projet (staging/prod/dev).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str]) -> str:
    """Exécute une commande et renvoie stdout. Raise si erreur."""
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        raise RuntimeError(
            f"Command failed: {' '.join(cmd)}\n"
            f"STDOUT:\n{p.stdout}\n"
            f"STDERR:\n{p.stderr}\n"
        )
    return p.stdout.strip()


def parse_backend_hcl(backend_path: Path) -> dict:
    """
    Parse tolérant de backend.hcl.

    Supporte :
    - commentaires en fin de ligne :  bucket="x"  # comment
    - lignes commentées : # ...  ou // ...
    - espaces, tabulations

    Format attendu (au minimum) :
        bucket = "..."
        prefix = "..."   (optionnel)
    """
    if not backend_path.exists():
        raise FileNotFoundError(f"backend.hcl introuvable: {backend_path}")

    content = backend_path.read_text(encoding="utf-8")

    # 1) On supprime les commentaires inline (tout ce qui suit # ou //)
    #    Attention : ce parsing est "pragmatique" (suffisant pour backend.hcl simple).
    cleaned_lines = []
    for line in content.splitlines():
        # enlève // commentaires
        line = re.sub(r"\s//.*$", "", line)
        # enlève # commentaires
        line = re.sub(r"\s#.*$", "", line)
        line = line.strip()
        if not line:
            continue
        cleaned_lines.append(line)

    cleaned = "\n".join(cleaned_lines)

    # 2) Parse key = "value"
    pattern = re.compile(r'^\s*([a-zA-Z0-9_]+)\s*=\s*"([^"]+)"\s*$', re.MULTILINE)
    kv = {k: v for k, v in pattern.findall(cleaned)}

    if "bucket" not in kv:
        raise ValueError(
            f"Impossible de trouver 'bucket = \"...\"' dans {backend_path}.\n"
            f"Contenu nettoyé (sans commentaires):\n{cleaned}\n"
            f"Contenu original:\n{content}"
        )

    return kv


def bucket_exists(bucket_name: str) -> bool:
    """
    Vérifie si un bucket existe via gcloud.
    - Si tu n'as pas les droits de lecture sur un bucket existant, ça peut aussi échouer.
    """
    try:
        run(["gcloud", "storage", "buckets", "describe", f"gs://{bucket_name}"])
        return True
    except Exception:
        return False


def create_bucket(project_id: str, location: str, bucket_name: str) -> None:
    """
    Crée le bucket GCS via gcloud storage.
    """
    run(["gcloud", "config", "set", "project", project_id])

    # Création bucket
    run([
        "gcloud", "storage", "buckets", "create",
        f"gs://{bucket_name}",
        "--project", project_id,
        "--location", location,
        "--uniform-bucket-level-access",
    ])

    # Active versioning (très utile pour restaurer un tfstate supprimé/corrompu)
    run([
        "gcloud", "storage", "buckets", "update",
        f"gs://{bucket_name}",
        "--versioning",
    ])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", required=True, choices=["dev", "staging", "prod"], help="Environnement")
    parser.add_argument("--project", required=True, help="Project ID GCP (ex: lakehouse-stg-486419)")
    parser.add_argument("--location", default="europe-west1", help="Location du bucket (default: europe-west1)")
    args = parser.parse_args()

    backend_path = Path("terraform") / "envs" / args.env / "backend.hcl"
    kv = parse_backend_hcl(backend_path)

    bucket_name = kv["bucket"]
    prefix = kv.get("prefix", "(non défini)")

    print("==========================================")
    print("Terraform backend bucket bootstrap (Python)")
    print("==========================================")
    print(f"ENV            : {args.env}")
    print(f"Backend file   : {backend_path}")
    print(f"Bucket (GCS)   : {bucket_name}")
    print(f"Prefix         : {prefix}")
    print(f"Project        : {args.project}")
    print(f"Location       : {args.location}")
    print("")

    if bucket_exists(bucket_name):
        print(f"✅ Bucket existe déjà : gs://{bucket_name}")
        print("➡️ Tu peux relancer : make tf-plan ENV=staging")
        return 0

    print(f"⚠️ Bucket absent, création en cours : gs://{bucket_name}")
    try:
        create_bucket(args.project, args.location, bucket_name)
    except Exception as e:
        print("❌ Échec création bucket.")
        print(str(e))
        return 1

    print(f"✅ Bucket créé + versioning activé : gs://{bucket_name}")
    print("➡️ Relance maintenant :")
    print(f"   make tf-plan ENV={args.env}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())