#!/usr/bin/env python3
"""
=========================================================
Upload d'un fichier parquet local vers le bucket RAW (GCS)
=========================================================

Objectif
--------
Uploader le fichier `data/sample.parquet` dans le bucket RAW GCS
en respectant une convention "entreprise" de rangement par domaines/datasets.

Destination choisie
-------------------
gs://<RAW_BUCKET>/domain=<domain>/dataset=<dataset>/<filename>

Exemple staging
---------------
gs://lakehouse-stg-486419-raw-staging/domain=sales/dataset=sample/sample.parquet

Pré-requis
----------
1) Avoir un projet GCP configuré et authentifié :
   - gcloud auth application-default login
     OU
   - export GOOGLE_APPLICATION_CREDENTIALS=/path/key.json

2) Avoir installé google-cloud-storage :
   - pip install google-cloud-storage

Commandes
---------
# Upload en staging
python scripts/upload_sample_to_raw.py \
  --project lakehouse-stg-486419 \
  --bucket lakehouse-stg-486419-raw-staging \
  --src data/sample.parquet \
  --domain sales \
  --dataset sample

# Vérifier dans GCS
gsutil ls -r gs://lakehouse-stg-486419-raw-staging/domain=sales/dataset=sample/

Notes "entreprise"
------------------
- On valide les entrées (fichier existe, bucket accessible)
- On logge chaque étape (utile en CI/CD plus tard)
- On garde un code simple, robuste, maintenable
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Client officiel Google Cloud Storage (Python SDK)
from google.cloud import storage
from google.api_core.exceptions import NotFound, Forbidden


def build_parser() -> argparse.ArgumentParser:
    """
    Construit le parseur d'arguments CLI.
    On sépare cette logique pour garder `main()` lisible.
    """
    parser = argparse.ArgumentParser(
        description="Upload d'un parquet local vers un bucket RAW GCS (convention domain/dataset)."
    )

    # Projet GCP sur lequel le client GCS va opérer
    parser.add_argument(
        "--project",
        required=True,
        help="ID du projet GCP (ex: lakehouse-stg-486419).",
    )

    # Bucket RAW cible (déjà créé par Terraform dans ton flow)
    parser.add_argument(
        "--bucket",
        required=True,
        help="Nom du bucket RAW cible (ex: lakehouse-stg-486419-raw-staging).",
    )

    # Chemin du fichier local à envoyer
    parser.add_argument(
        "--src",
        default="data/sample.parquet",
        help="Chemin local du fichier à uploader (défaut: data/sample.parquet).",
    )

    # Convention de rangement: domain=xxx/dataset=yyy
    parser.add_argument(
        "--domain",
        default="sales",
        help="Nom du domaine (défaut: sales).",
    )
    parser.add_argument(
        "--dataset",
        default="sample",
        help="Nom du dataset logique (défaut: sample).",
    )

    return parser


def check_local_file_exists(src: Path) -> None:
    """
    Valide l'existence du fichier local.
    On fail fast avec un message clair si le fichier n'existe pas.
    """
    if not src.exists():
        raise FileNotFoundError(
            f"[ERREUR] Fichier introuvable: {src}\n"
            f"👉 Vérifie que `data/sample.parquet` existe bien dans ton repo."
        )
    if not src.is_file():
        raise ValueError(
            f"[ERREUR] Le chemin fourni n'est pas un fichier: {src}\n"
            f"👉 Donne un fichier .parquet valide."
        )


def check_bucket_access(client: storage.Client, bucket_name: str) -> storage.Bucket:
    """
    Vérifie que le bucket existe et que tu as les droits d'accès.
    - NotFound: bucket inexistant
    - Forbidden: pas les permissions
    """
    try:
        bucket = client.bucket(bucket_name)

        # `reload()` force un call API -> utile pour confirmer existence + droits
        bucket.reload()

        return bucket

    except NotFound as e:
        raise RuntimeError(
            f"[ERREUR] Bucket GCS introuvable: gs://{bucket_name}\n"
            f"👉 Soit Terraform ne l'a pas créé, soit tu n'es pas dans le bon projet.\n"
            f"Détail: {e}"
        ) from e

    except Forbidden as e:
        raise RuntimeError(
            f"[ERREUR] Accès interdit au bucket: gs://{bucket_name}\n"
            f"👉 Vérifie tes droits IAM et ton auth gcloud.\n"
            f"Détail: {e}"
        ) from e


def upload_file(bucket: storage.Bucket, src: Path, gcs_object_path: str) -> None:
    """
    Upload réellement le fichier vers GCS.

    Paramètres
    ----------
    bucket : storage.Bucket
        Bucket cible, déjà validé (existe + droits OK)
    src : Path
        Fichier local à envoyer
    gcs_object_path : str
        Chemin "objet" dans le bucket (sans le gs://bucket)
    """
    blob = bucket.blob(gcs_object_path)

    # Log entreprise: on affiche exactement ce qu'on fait
    print(f"➡️ Upload: {src}  ->  gs://{bucket.name}/{gcs_object_path}")

    # Upload simple (pour gros volumes, on pourrait gérer chunking / resumable)
    blob.upload_from_filename(str(src))

    # Vérification / log: taille et génération (version)
    blob.reload()
    print(f"✅ Upload OK | size={blob.size} bytes | generation={blob.generation}")


def main() -> int:
    """
    Point d'entrée principal.
    On structure l'exécution en étapes claires (validation -> upload -> vérif).
    """
    parser = build_parser()
    args = parser.parse_args()

    # Convertit le chemin source en Path (plus propre que du string)
    src = Path(args.src)

    print("==============================================")
    print("RAW sample upload (GCS) - mode entreprise")
    print("==============================================")
    print(f"Project  : {args.project}")
    print(f"Bucket   : {args.bucket}")
    print(f"Source   : {src}")
    print(f"Domain   : {args.domain}")
    print(f"Dataset  : {args.dataset}")
    print("----------------------------------------------")

    # 1) Validation fichier local
    check_local_file_exists(src)

    # 2) Construction du chemin cible dans le bucket
    # Convention entreprise: domain=<...>/dataset=<...>/<filename>
    gcs_object_path = f"domain={args.domain}/dataset={args.dataset}/{src.name}"

    # 3) Création client GCS
    # Le client utilisera l'auth par défaut (ADC) configurée sur ta machine
    client = storage.Client(project=args.project)

    # 4) Vérification bucket (existe + droits OK)
    bucket = check_bucket_access(client, args.bucket)

    # 5) Upload
    upload_file(bucket, src, gcs_object_path)

    # 6) Message final actionnable
    print("----------------------------------------------")
    print("➡️ Vérifie maintenant avec :")
    print(f"   gsutil ls -r gs://{args.bucket}/domain={args.domain}/dataset={args.dataset}/")
    print("✅ Étape RAW terminée.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        # Log entreprise: message clair + exit code non-zero
        print(f"\n🔥 Échec: {e}", file=sys.stderr)
        raise SystemExit(1)