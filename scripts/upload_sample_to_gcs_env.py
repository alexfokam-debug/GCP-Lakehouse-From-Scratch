#!/usr/bin/env python3
"""
Upload "entreprise" du fichier sample.parquet vers le bucket RAW
du bon environnement (dev/staging/prod), en se basant sur configs/env.<env>.yaml.

Pourquoi ?
- Terraform crée une table externe BigQuery qui pointe sur un chemin GCS.
- Si aucun fichier ne matche le pattern GCS, Terraform plante avec :
  "matched no files"

Usage:
  python scripts/upload_sample_to_gcs_env.py --env dev

Pré-requis:
- gcloud auth application-default login
- pip install google-cloud-storage pyyaml

Chemins importants:
- Fichier local: data/sample.parquet
- Destination GCS (convention): domain=sales/dataset=sample/sample.parquet
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import yaml
from google.cloud import storage


# -----------------------------
# Parsing des arguments CLI
# -----------------------------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Upload sample parquet to GCS based on environment config.")
    p.add_argument("--env", required=True, choices=["dev", "staging", "prod"], help="Target environment")
    return p.parse_args()


# -----------------------------
# Chargement du fichier YAML d'environnement
# -----------------------------
def load_env_config(env: str) -> dict:
    """
    Charge configs/env.<env>.yaml

    Ce fichier doit contenir au minimum:
      gcp:
        project_id: ...
        region: ...
      gcs:
        raw_bucket: ...
    """
    path = Path("configs") / f"env.{env}.yaml"
    if not path.exists():
        raise FileNotFoundError(f"Config introuvable: {path}")

    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def main() -> int:
    args = parse_args()

    # 1) Lire la config de l'environnement
    cfg = load_env_config(args.env)

    # 2) Récupérer infos GCP/GCS depuis la config
    project_id = cfg["gcp"]["project_id"]
    raw_bucket = cfg["gcs"]["raw_bucket"]

    # 3) Définir source locale et destination GCS (chemin "entreprise")
    src = Path("data") / "sample.parquet"
    dst = "domain=sales/dataset=sample/sample.parquet"

    # 4) Vérifier que le fichier local existe
    if not src.exists():
        raise FileNotFoundError(f"Fichier local absent: {src}")

    # 5) Initialiser le client GCS
    #    Utilise Application Default Credentials (ADC)
    client = storage.Client(project=project_id)

    # 6) Récupérer bucket + objet
    bucket = client.bucket(raw_bucket)
    blob = bucket.blob(dst)

    # 7) Upload
    print("=====================================")
    print("Upload sample parquet (ENV aware)")
    print("=====================================")
    print(f"ENV     : {args.env}")
    print(f"Project : {project_id}")
    print(f"Bucket  : gs://{raw_bucket}")
    print(f"Source  : {src}")
    print(f"Dest    : gs://{raw_bucket}/{dst}")
    print("")

    blob.upload_from_filename(str(src))

    print("✅ Upload terminé. Terraform peut créer la table externe sans erreur.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())