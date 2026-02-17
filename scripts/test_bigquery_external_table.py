#!/usr/bin/env python3
"""
Test BigQuery automatisé (mode entreprise) pour valider une table externe.

Objectif :
- Vérifier que le dataset existe
- Vérifier que la table existe
- Lire un échantillon (SELECT * LIMIT N) pour valider que BigQuery peut accéder aux fichiers GCS
- (Optionnel) Afficher des infos de partition / schéma si besoin

Pourquoi c’est "entreprise" ?
- Script paramétrable (env, dataset, table)
- Erreurs explicites (exit code != 0 si KO -> parfait pour CI/CD)
- Logs clairs
- Test minimal mais fiable

Exemples d'usage :
  python scripts/test_bigquery_external_table.py \
    --project lakehouse-stg-486419 \
    --dataset raw_ext_staging \
    --table sample_ext \
    --limit 5

Si tu veux tester un autre environnement :
  python scripts/test_bigquery_external_table.py \
    --project lakehouse-dev-XXXX \
    --dataset raw_ext_dev \
    --table sample_ext
"""

from __future__ import annotations

import argparse
import sys
from typing import Optional

# Client officiel BigQuery (Python SDK)
from google.cloud import bigquery

# Exceptions utiles pour rendre les erreurs lisibles
from google.api_core.exceptions import NotFound, Forbidden, BadRequest


# -----------------------------
# 1) Parsing des arguments CLI
# -----------------------------
def build_parser() -> argparse.ArgumentParser:
    """
    Construit le parser CLI.

    On sépare cette logique pour garder main() lisible,
    comme dans des projets "prod".
    """
    p = argparse.ArgumentParser(
        description="Test BigQuery automatisé : dataset + table externe + query LIMIT."
    )
    p.add_argument("--project", required=True, help="GCP project id (ex: lakehouse-stg-486419)")
    p.add_argument("--dataset", required=True, help="BigQuery dataset id (ex: raw_ext_staging)")
    p.add_argument("--table", required=True, help="BigQuery table id (ex: sample_ext)")
    p.add_argument("--limit", type=int, default=5, help="Nombre de lignes à lire (default: 5)")
    p.add_argument(
        "--region",
        default=None,
        help=(
            "Optionnel: région BigQuery pour les jobs (ex: europe-west1). "
            "Si None, BigQuery choisit selon le dataset."
        ),
    )
    return p


# -----------------------------
# 2) Helpers de log
# -----------------------------
def log_info(msg: str) -> None:
    print(f"ℹ️  {msg}")


def log_ok(msg: str) -> None:
    print(f"✅ {msg}")


def log_warn(msg: str) -> None:
    print(f"⚠️  {msg}")


def log_err(msg: str) -> None:
    print(f"❌ {msg}", file=sys.stderr)


# -----------------------------
# 3) Vérifications BigQuery
# -----------------------------
def check_dataset_exists(client: bigquery.Client, project: str, dataset_id: str) -> None:
    """
    Vérifie que le dataset existe.

    - Si dataset absent -> NotFound
    - Si pas de droits -> Forbidden
    """
    dataset_ref = bigquery.DatasetReference(project, dataset_id)

    log_info(f"Vérification dataset : {project}.{dataset_id}")
    ds = client.get_dataset(dataset_ref)  # -> lève NotFound/Forbidden
    log_ok(f"Dataset trouvé : {ds.full_dataset_id}")


def check_table_exists(client: bigquery.Client, project: str, dataset_id: str, table_id: str) -> bigquery.Table:
    """
    Vérifie que la table existe et renvoie l'objet Table.
    """
    table_ref = bigquery.TableReference(
        bigquery.DatasetReference(project, dataset_id),
        table_id,
    )

    log_info(f"Vérification table : {project}.{dataset_id}.{table_id}")
    tbl = client.get_table(table_ref)  # -> lève NotFound/Forbidden
    log_ok(f"Table trouvée : {tbl.full_table_id}")

    # Un petit bonus : afficher le type (EXTERNAL vs TABLE)
    # Pour une table externe, tbl.table_type vaut souvent "EXTERNAL"
    log_info(f"Type table : {tbl.table_type}")

    # Bonus entreprise : afficher le nombre de colonnes détectées (si schema dispo)
    if tbl.schema:
        log_info(f"Schéma : {len(tbl.schema)} colonnes détectées")
    else:
        log_warn("Schéma vide/non détecté (possible si table externe autodetect + pas encore lu).")

    return tbl


def run_sample_query(
    client: bigquery.Client,
    project: str,
    dataset_id: str,
    table_id: str,
    limit: int,
    region: Optional[str] = None,
) -> int:
    """
    Lance une requête SELECT * LIMIT N pour valider que BigQuery peut lire les fichiers GCS.

    Retour :
    - 0 si OK
    - 1 si pas OK (on remonte des logs + exit code)
    """
    table_fqn = f"`{project}.{dataset_id}.{table_id}`"

    # Requête volontairement simple :
    # - Si BigQuery ne peut pas lire GCS -> tu auras une erreur explicite
    # - Si tout va bien -> rows récupérées
    query = f"SELECT * FROM {table_fqn} LIMIT {limit}"

    log_info("Lancement requête de test :")
    log_info(query)

    job_config = bigquery.QueryJobConfig()
    # region (location) : si tu veux forcer europe-west1
    # sinon BigQuery s'aligne sur le dataset / projet
    job = client.query(query, job_config=job_config, location=region)

    # Attend la fin du job + récupère les résultats
    rows = list(job.result())

    log_ok(f"Query OK. Lignes récupérées : {len(rows)}")

    # Affiche 1 ligne exemple (sans spammer)
    if rows:
        log_info("Exemple de 1ère ligne (dict) :")
        # row est un Row object -> row.items() possible
        first_row = dict(rows[0].items())
        log_info(str(first_row))

    return 0


# -----------------------------
# 4) main
# -----------------------------
def main() -> int:
    args = build_parser().parse_args()

    print("==========================================")
    print("BigQuery Automated Test (External Table)")
    print("==========================================")
    log_info(f"Project : {args.project}")
    log_info(f"Dataset : {args.dataset}")
    log_info(f"Table   : {args.table}")
    log_info(f"Limit   : {args.limit}")
    log_info(f"Region  : {args.region or '(auto)'}")
    print("")

    # Client BigQuery :
    # Utilise l'auth de ton poste via ADC (Application Default Credentials)
    # Commande si besoin :
    #   gcloud auth application-default login
    client = bigquery.Client(project=args.project)

    try:
        # 1) Dataset OK ?
        check_dataset_exists(client, args.project, args.dataset)

        # 2) Table OK ?
        _tbl = check_table_exists(client, args.project, args.dataset, args.table)

        # 3) Lecture OK ? (c'est la validation la plus "réelle")
        return run_sample_query(client, args.project, args.dataset, args.table, args.limit, args.region)

    except NotFound as e:
        log_err("Ressource introuvable (dataset ou table).")
        log_err(str(e))
        return 2

    except Forbidden as e:
        log_err("Accès refusé (droits IAM insuffisants).")
        log_err(str(e))
        return 3

    except BadRequest as e:
        log_err("Requête invalide ou configuration externe table incorrecte (BadRequest).")
        log_err(str(e))
        return 4

    except Exception as e:
        log_err("Erreur inattendue.")
        log_err(repr(e))
        return 99


if __name__ == "__main__":
    raise SystemExit(main())