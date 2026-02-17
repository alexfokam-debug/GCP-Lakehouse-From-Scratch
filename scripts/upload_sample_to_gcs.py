#!/usr/bin/env python3
"""
=========================================================
Upload d'un fichier local vers GCS (RAW) - mode entreprise
=========================================================

But
---
Uploader `data/sample.parquet` dans un bucket GCS au chemin attendu
par ta table externe BigQuery (sinon erreur: "matched no files").

✅ Compatible avec ta commande actuelle (avec --dst).

Usage (identique à ton script actuel)
-------------------------------------
python scripts/upload_sample_to_gcs.py \
  --project lakehouse-stg-486419 \
  --bucket lakehouse-stg-486419-raw-staging \
  --src data/sample.parquet \
  --dst domain=sales/dataset=sample/sample.parquet

Bonnes pratiques (entreprise)
-----------------------------
- Validations: fichier local existe, bucket accessible
- Logs explicites
- Erreurs actionnables (NotFound / Forbidden)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from google.cloud import storage
from google.api_core.exceptions import NotFound, Forbidden


def parse_args() -> argparse.Namespace:
    """
    Parse des arguments CLI.
    On isole ça pour garder main() lisible.
    """
    p = argparse.ArgumentParser(description="Upload sample parquet to GCS for external table.")
    p.add_argument("--project", required=True, help="GCP project id (ex: lakehouse-stg-486419)")
    p.add_argument("--bucket", required=True, help="GCS bucket name (ex: lakehouse-stg-486419-raw-staging)")
    p.add_argument("--src", required=True, help="Local file path (ex: data/sample.parquet)")
    p.add_argument("--dst", required=True, help="Object path inside bucket (ex: domain=sales/dataset=sample/sample.parquet)")
    return p.parse_args()


def ensure_local_file(src: Path) -> None:
    """
    Vérifie que le fichier local existe et est un fichier.
    """
    if not src.exists():
        raise FileNotFoundError(
            f"[ERREUR] Fichier introuvable: {src}\n"
            f"👉 Vérifie le chemin --src et que le fichier existe bien."
        )
    if not src.is_file():
        raise ValueError(
            f"[ERREUR] Le chemin --src n'est pas un fichier: {src}\n"
            f"👉 Donne un fichier .parquet valide."
        )


def ensure_bucket_access(client: storage.Client, bucket_name: str) -> storage.Bucket:
    """
    Vérifie que le bucket existe + que tu as les droits.
    """
    try:
        bucket = client.bucket(bucket_name)
        bucket.reload()  # force un call API
        return bucket
    except NotFound as e:
        raise RuntimeError(
            f"[ERREUR] Bucket inexistant: gs://{bucket_name}\n"
            f"👉 Terraform a peut-être ciblé un autre projet/env ou tu as un mauvais nom de bucket.\n"
            f"Détail: {e}"
        ) from e
    except Forbidden as e:
        raise RuntimeError(
            f"[ERREUR] Accès interdit au bucket: gs://{bucket_name}\n"
            f"👉 Vérifie ton auth (gcloud ADC) et tes rôles IAM.\n"
            f"Détail: {e}"
        ) from e


def upload(bucket: storage.Bucket, src: Path, dst: str) -> None:
    """
    Upload du fichier local vers GCS.
    """
    blob = bucket.blob(dst)

    print("=====================================")
    print("Upload parquet -> GCS (RAW)")
    print("=====================================")
    print(f"Bucket : gs://{bucket.name}")
    print(f"Source : {src}")
    print(f"Dest   : gs://{bucket.name}/{dst}")
    print("-------------------------------------")

    blob.upload_from_filename(str(src))

    # Vérif post-upload (taille, génération) = pratique en mode entreprise
    blob.reload()
    print(f"✅ Upload terminé | size={blob.size} bytes | generation={blob.generation}")


def main() -> int:
    args = parse_args()

    src = Path(args.src)

    # 1) Validation fichier local
    ensure_local_file(src)

    # 2) Client GCS (ADC: gcloud auth application-default login)
    client = storage.Client(project=args.project)

    # 3) Validation bucket (existe + droits OK)
    bucket = ensure_bucket_access(client, args.bucket)

    # 4) Upload
    upload(bucket, src, args.dst)

    # 5) Commande utile pour vérifier rapidement
    print("-------------------------------------")
    print("➡️ Vérifie avec :")
    print(f"   gsutil ls -r gs://{args.bucket}/{args.dst.rsplit('/', 1)[0]}/")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"\n🔥 Échec: {e}", file=sys.stderr)
        raise SystemExit(1)