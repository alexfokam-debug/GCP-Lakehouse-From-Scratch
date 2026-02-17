from __future__ import annotations

import logging
from pathlib import Path

import typer

from .config import load_env_config, load_profile_properties
from .dataproc import submit_dataproc_serverless_pyspark

# -----------------------------------------------------------------------------
# App racine
# -----------------------------------------------------------------------------
app = typer.Typer(
    no_args_is_help=True,
    add_completion=True,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
log = logging.getLogger("lakehouse")


@app.callback()
def main() -> None:
    """
    Lakehouse CLI (mode entreprise)

    Commandes principales :
    - dataproc-iceberg : soumettre un job PySpark (Iceberg) sur Dataproc Serverless
    """
    # Le callback force Typer à rester un "groupe" (root),
    # même si tu n'as qu'une seule commande.
    return


# -----------------------------------------------------------------------------
# Commande Dataproc Iceberg
# -----------------------------------------------------------------------------
@app.command("dataproc-iceberg")
def dataproc_iceberg(
    local_job: Path = typer.Option(
        ...,
        "--local-job",
        exists=True,          # IMPORTANT : fail fast si le path est faux
        file_okay=True,
        dir_okay=False,
        readable=True,
        help="Chemin local du job PySpark (.py)",
    ),
    env_file: Path = typer.Option(
        ...,
        "--env-file",
        exists=True,
        help="YAML env (ex: ../configs/env.dev.yaml)",
    ),
    profiles_file: Path = typer.Option(
        ...,
        "--profiles-file",
        exists=True,
        help="YAML profiles (ex: ../configs/profiles.yaml)",
    ),
    profile: str = typer.Option(
        "dev_small",
        "--profile",
        help="Nom du profile (ex: dev_small)",
    ),
    gcs_prefix: str = typer.Option(
        "jobs/iceberg_writer",
        "--gcs-prefix",
        help="Prefix GCS dans le bucket scripts",
    ),
) -> None:
    """
    Soumet un job PySpark sur Dataproc Serverless avec :
    - env.dev.yaml : project/region/buckets/iceberg/dataproc
    - profiles.yaml : sizing Spark (driver/executors)
    """
    env = load_env_config(env_file)
    prof = load_profile_properties(profiles_file, profile)

    # Arguments transmis à ton job PySpark (create_iceberg_tables.py)
    job_args = [
        f"--project_id={env.project_id}",
        f"--raw_table={env.iceberg.raw_table}",
        f"--iceberg_catalog={env.iceberg_catalog_name}",
        f"--iceberg_db={env.iceberg_db}",
        f"--iceberg_table={env.iceberg_table}",
        f"--temporary_gcs_bucket={env.dataproc_temp_bucket}",
    ]

    res = submit_dataproc_serverless_pyspark(
        env=env,
        profile=prof,
        local_job=local_job,
        job_args=job_args,
        gcs_prefix=gcs_prefix,
    )

    typer.echo("")
    typer.echo("✅ Dataproc batch submitted")
    typer.echo(f" - batch_id : {res.batch_id}")
    typer.echo(f" - job_gcs  : {res.gcs_job_uri}")


def run() -> None:
    """
    Entry point Python (utile si tu veux lancer via `python -m lakehouse_cli.cli`)
    """
    app()


if __name__ == "__main__":
    run()