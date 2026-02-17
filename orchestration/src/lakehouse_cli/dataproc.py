"""
dataproc.py
===========

Objectif
--------
Soumettre un job PySpark sur **Dataproc Serverless (Batches)**, en mode "entreprise".

Ce module fait (toujours) les mêmes étapes :

1) Valider le fichier local du job PySpark (ex: jobs/iceberg_writer/create_iceberg_tables.py)
2) Uploader ce job sur un bucket GCS "scripts"
3) Construire les Spark properties (Iceberg + sizing + BigQuery connector + staging bucket)
4) Soumettre le batch via `gcloud dataproc batches submit pyspark`
5) (Optionnel) Helpers de debug (describe batch)

Notes importantes (ton contexte)
--------------------------------
- Dataproc Serverless runtime 2.2 => Spark 3.5.x
- Iceberg doit matcher Spark 3.5 :
    ✅ org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:<version>
- `gcloud --properties` est une *valeur de type dict*.
  Problème classique : les valeurs contenant des virgules (ex: spark.jars.packages=...,...)
  sont mal parsées par gcloud si on envoie du "k=v,k=v".

  ✅ Solution robuste : utiliser le *custom delimiter* de gcloud :
      --properties=^|^k=v|k=v|k=v
  Ici:
  - '^|^' signifie : "je change le séparateur du dict"
  - '|' devient le séparateur entre entrées du dict
  - donc tu peux garder des virgules dans les valeurs (parfait pour spark.jars.packages)

Correction ajoutée (ce que tu demandes)
--------------------------------------
On complète automatiquement `spark.jars.packages` avec :
- scala-library (Scala 2.12)
- spark-bigquery-with-dependencies (Scala 2.12)

⚠️ Remarque terrain :
- Sur Dataproc Serverless, le BigQuery connector est souvent déjà présent.
  Ajouter une autre version peut provoquer des conflits.
  => on garde l’ajout par défaut (comme tu veux), mais tu as un switch pour le désactiver
     si nécessaire (voir `include_bigquery_connector`).

"""

from __future__ import annotations

import json
import logging
import shlex
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .config import EnvConfig, DataprocProfile

log = logging.getLogger(__name__)


# =============================================================================
# Types de retour
# =============================================================================

@dataclass(frozen=True)
class SubmitResult:
    """
    Résultat minimal (utile en CI / logs / debug).

    - batch_id: ID Dataproc (sert à "describe", "wait", etc.)
    - gcs_job_uri: l’URI exacte du script uploadé
    - properties_sent: les properties finales réellement envoyées
    """
    batch_id: str
    gcs_job_uri: str
    properties_sent: Dict[str, str]


# =============================================================================
# Subprocess helper (standard enterprise)
# =============================================================================

def run_cmd(
    cmd: List[str],
    *,
    check: bool = True,
    capture: bool = False,
) -> subprocess.CompletedProcess:
    """
    Wrapper standard autour de subprocess.run

    Params:
    - check=True  : lève une exception si exit code != 0 (comportement CI-friendly)
    - capture=False : affiche les logs direct dans ton terminal (excellent en debug)
    - capture=True  : capture stdout/stderr (utile pour parser / tests)

    Idées d’amélioration "full enterprise" (si tu veux pousser) :
    - retries + backoff sur erreurs réseau
    - classification d’erreurs (IAM, quota, not found, etc.)
    - timeouts par commande
    """
    printable = " ".join(shlex.quote(x) for x in cmd)
    log.info("RUN: %s", printable)

    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
    )


# =============================================================================
# Upload GCS (scripts)
# =============================================================================

def gcs_upload(local_file: Path, gcs_uri: str) -> None:
    """
    Upload un fichier local vers GCS via gsutil.

    Pourquoi gsutil ?
    - simple
    - déjà disponible sur la plupart des postes dev
    - suffisamment robuste pour un MVP "enterprise"

    Alternative (plus "SDK/enterprise") :
    - google-cloud-storage en Python + retries/timeouts
    """
    if not local_file.exists():
        raise FileNotFoundError(f"Local job introuvable: {local_file.resolve()}")

    run_cmd(["gsutil", "cp", str(local_file), gcs_uri], check=True)


# =============================================================================
# Spark properties builder (Iceberg + BigQuery + sizing)
# =============================================================================

def _get_dataproc_temp_bucket(env: EnvConfig) -> Optional[str]:
    # 1) champ plat si EnvConfig l'expose
    v = getattr(env, "dataproc_temp_bucket", None)
    if v:
        return v

    # 2) buckets (dict ou objet)
    buckets = getattr(env, "buckets", None)
    if buckets:
        if isinstance(buckets, dict):
            v = buckets.get("dataproc_temp")
            if v:
                return v
        else:
            v = getattr(buckets, "dataproc_temp", None)
            if v:
                return v

    # 3) dataproc.temp_bucket (dict ou objet)
    dp = getattr(env, "dataproc", None)
    if dp:
        if isinstance(dp, dict):
            v = dp.get("temp_bucket")
            if v:
                return v
        else:
            v = getattr(dp, "temp_bucket", None)
            if v:
                return v

    return None

def _split_packages(packages_csv: str) -> List[str]:
    """
    Transforme une string "a,b,c" en liste nettoyée.

    - retire les espaces
    - retire les éléments vides
    - conserve l’ordre
    """
    if not packages_csv:
        return []
    return [p.strip() for p in str(packages_csv).split(",") if p.strip()]


def _dedupe_keep_order(items: List[str]) -> List[str]:
    """
    Déduplication stable (on garde l’ordre initial).
    """
    seen = set()
    out = []
    for it in items:
        if it not in seen:
            out.append(it)
            seen.add(it)
    return out


def _append_required_packages(
    props: Dict[str, Optional[str]],
    *,
    include_bigquery_connector: bool,
    bigquery_pkg: Optional[str] = None,
) -> None:
    """
    === Correction demandée ===
    Complète `spark.jars.packages` avec scala + bigquery connector, sans doublons.

    Contexte Dataproc 2.2 :
    - Spark 3.5 / Scala 2.12
    - Scala lib (2.12.18) et BQ connector (0.36.4) "recommandés" dans ton contexte.

    ⚠️ Attention :
    - Dataproc Serverless embarque souvent déjà le connector BigQuery.
      Si tu vois des erreurs de type "not a subtype" / ServiceConfigurationError,
      désactive l’ajout via `include_bigquery_connector=False`.
    """
    #base_pkg = props.get("spark.jars.packages") or ""

    # Versions cibles (ton choix)
    base_pkg = props.get("spark.jars.packages") or ""
    pkgs = _split_packages(str(base_pkg))

    # Ajout BQ (optionnel, mais par défaut on le met)
    if include_bigquery_connector:
        pkgs.append(bigquery_pkg)

    props["spark.jars.packages"] = ",".join(_dedupe_keep_order(pkgs))


def build_spark_properties(env: EnvConfig, profile: DataprocProfile) -> Dict[str, str]:
    """
    Construit les Spark properties envoyées à Dataproc.

    Sources :
    - env.* : tout ce qui est environnement (project, region, buckets, iceberg, runtime)
    - profile.* : sizing / tuning (driver/executor) venant de profiles.yaml

    Points clés :
    - spark.sql.extensions active Iceberg SQL + writeTo() / createOrReplace
    - spark.sql.catalog.<name> configure le catalog Iceberg
    - spark.bigquery.temporaryGcsBucket fiabilise les reads BigQuery sur gros volumes
    """
    # -------------------------------------------------------------------------
    # 1) Base (Iceberg + Catalog)
    # -------------------------------------------------------------------------
    props: Dict[str, Optional[str]] = {
        # Iceberg runtime jar (doit matcher Spark/Scala du runtime)
        "spark.jars.packages": env.dataproc.iceberg_package,

        # Extensions Iceberg
        "spark.sql.extensions": "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",

        # Catalog Iceberg (HadoopCatalog sur GCS)
        f"spark.sql.catalog.{env.iceberg_catalog_name}": "org.apache.iceberg.spark.SparkCatalog",
        f"spark.sql.catalog.{env.iceberg_catalog_name}.type": "hadoop",
        f"spark.sql.catalog.{env.iceberg_catalog_name}.warehouse": env.iceberg.warehouse_uri,
    }
    # ----------------------------
    # 1bis) jars.packages : compléter avec scala + bigquery connector
    # ----------------------------
    '''base_pkg = props.get("spark.jars.packages") or ""

    # IMPORTANT: Dataproc 2.2 dans tes logs => Scala 2.13.12
    scala_pkg = "org.scala-lang:scala-library:2.13.12"
    bq_pkg = "com.google.cloud.spark:spark-bigquery-with-dependencies_2.13:0.36.4"

    pkgs = [p.strip() for p in str(base_pkg).split(",") if p.strip()]
    for extra in [scala_pkg, bq_pkg]:
        if extra not in pkgs:
            pkgs.append(extra)

    props["spark.jars.packages"] = ",".join(pkgs)'''
    # -------------------------------------------------------------------------
    # 1bis) Correction demandée : compléter jars.packages (scala + bigquery)
    # -------------------------------------------------------------------------
    # Switch de sécurité : si tu veux pouvoir le désactiver sans recoder,
    # tu peux ajouter un champ dans ton profile / env plus tard.
    # Par défaut: True (comme tu le demandes).
    '''include_bigquery_connector = False
    bq_pkg = getattr(env, "bigquery_package", None) or getattr(env, "dataproc_bigquery_package", None)

    _append_required_packages(
        props,
        include_bigquery_connector=include_bigquery_connector,
        bigquery_pkg=bq_pkg,
    )'''
    # -------------------------------------------------------------------------
    # 2) BigQuery staging bucket (recommandé en enterprise)
    # -------------------------------------------------------------------------
    temp_bucket = _get_dataproc_temp_bucket(env)
    if not temp_bucket:
        raise ValueError(
            "Bucket temporaire BigQuery manquant. "
            "Ajoute buckets.dataproc_temp dans env.dev.yaml et mappe-le dans EnvConfig."
        )

    props["spark.bigquery.temporaryGcsBucket"] = temp_bucket
    # -------------------------------------------------------------------------
    # 3) Sizing (profiles.yaml)
    # -------------------------------------------------------------------------
    props.update({
        "spark.driver.cores": str(profile.driver_cores),
        "spark.driver.memory": profile.driver_memory,
        "spark.executor.instances": str(profile.executor_instances),
        "spark.executor.cores": str(profile.executor_cores),
        "spark.executor.memory": profile.executor_memory,
    })

    # -------------------------------------------------------------------------
    # 4) Extra tuning (profile a le dernier mot)
    # -------------------------------------------------------------------------
    if profile.extra_spark_properties:
        props.update(profile.extra_spark_properties)

    # -------------------------------------------------------------------------
    # 5) Nettoyage final (pas de None / string vide)
    # -------------------------------------------------------------------------
    cleaned: Dict[str, str] = {
        k: str(v)
        for k, v in props.items()
        if v is not None and str(v).strip() != ""
    }

    # Guard rails : sans jars.packages, Iceberg extensions va forcément crash
    if "spark.jars.packages" not in cleaned:
        raise ValueError(
            "spark.jars.packages est vide. "
            "Vérifie env.dev.yaml -> dataproc.iceberg_package (ou mapping EnvConfig)."
        )

    return cleaned


def log_properties(props: Dict[str, str]) -> None:
    """
    Log lisible des properties finales.
    Très utile pour reproduire un run / diagnostiquer un mismatch.
    """
    pretty = json.dumps(props, indent=2, sort_keys=True)
    log.info("Spark properties sent to Dataproc:\n%s", pretty)


# =============================================================================
# gcloud --properties : méthode robuste avec custom delimiter
# =============================================================================

def props_to_gcloud_arg(props: Dict[str, str]) -> str:
    """
    Convertit dict -> string attendue par gcloud, en mode robuste.

    Problème:
      gcloud attend un dict. Par défaut c’est "k=v,k=v,k=v"
      MAIS spark.jars.packages contient des virgules => gcloud casse tout.

    Solution:
      Utiliser un séparateur custom (feature gcloud) :
        ^|^k=v|k=v|k=v

      - '^|^' : définit le séparateur des entrées du dict
      - '|'   : devient le séparateur effectif entre entrées
      - Du coup, les virgules dans les valeurs ne posent plus problème.

    Exemple:
      {"spark.jars.packages":"a,b", "x":"y"}
      => "^|^spark.jars.packages=a,b|x=y"
    """
    # On choisit '|' comme séparateur car:
    # - très peu probable dans des values spark
    # - plus lisible que ':', ';', etc.
    sep = "|"
    prefix = "^|^"  # "je change de séparateur => |"
    parts = [f"{k}={v}" for k, v in props.items()]
    return prefix + sep.join(parts)


# =============================================================================
# Submit Dataproc batch
# =============================================================================

def submit_pyspark_batch(
    *,
    project_id: str,
    region: str,
    runtime_version: str,
    batch_id: str,
    service_account: str,
    main_python_gcs: str,
    properties: Dict[str, str],
    args: List[str],
    labels: Optional[Dict[str, str]] = None,
) -> None:
    """
    Soumet un batch PySpark Dataproc Serverless.

    Détails importants :
    - `--` sépare les flags gcloud des arguments de ton script PySpark.
    - `--properties` contient toutes les conf Spark (Iceberg etc.)
    - labels = pratique pour filtrer / cost attribution / audit
    """
    cmd = [
        "gcloud", "dataproc", "batches", "submit", "pyspark", main_python_gcs,
        "--project", project_id,
        "--region", region,
        "--batch", batch_id,
        "--version", runtime_version,
        "--service-account", service_account,
        "--properties", props_to_gcloud_arg(properties),
    ]

    # Labels (optionnel)
    if labels:
        cmd += ["--labels", ",".join(f"{k}={v}" for k, v in labels.items())]

    # Arguments du script PySpark (après --)
    cmd += ["--"] + args

    # capture=False : logs en live dans ton terminal (parfait pour debug)
    run_cmd(cmd, check=True, capture=False)


def submit_dataproc_serverless_pyspark(
    env: EnvConfig,
    profile: DataprocProfile,
    local_job: Path,
    job_args: List[str],
    *,
    gcs_prefix: str = "jobs/iceberg_writer",
    batch_id: Optional[str] = None,
) -> SubmitResult:
    """
    Pipeline complet (upload + build properties + submit).

    Paramètres :
    - local_job : chemin local du script PySpark
    - gcs_prefix : sous-dossier dans le bucket scripts
    - batch_id : si None, on auto-génère un ID unique

    Étapes :
    1) validation du fichier local
    2) upload vers gs://<scripts_bucket>/<gcs_prefix>/<filename>
    3) build properties
    4) submit batch
    5) retourne SubmitResult
    """
    # -------------------------------------------------------------------------
    # 1) Validation du job local
    # -------------------------------------------------------------------------
    local_job = local_job.expanduser()
    if not local_job.exists():
        raise FileNotFoundError(
            f"--local-job invalide. Fichier introuvable:\n  {local_job.resolve()}\n"
            f"Astuce: donne un chemin relatif depuis la racine du projet."
        )

    # -------------------------------------------------------------------------
    # 2) Batch ID + GCS URI
    # -------------------------------------------------------------------------
    ts = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    batch_id_final = batch_id or f"iceberg-{env.env}-{ts}"
    gcs_job_uri = f"gs://{env.buckets.scripts}/{gcs_prefix}/{local_job.name}"
    # -------------------------------------------------------------------------
    # 3) Upload du job
    # -------------------------------------------------------------------------
    log.info("Uploading job: %s -> %s", local_job, gcs_job_uri)
    gcs_upload(local_job, gcs_job_uri)

    # -------------------------------------------------------------------------
    # 4) Build Spark properties
    # -------------------------------------------------------------------------
    properties = build_spark_properties(env, profile)
    log_properties(properties)

    # -------------------------------------------------------------------------
    # 5) Submit
    # -------------------------------------------------------------------------
    labels = {"env": env.env, "component": "iceberg-writer"}

    submit_pyspark_batch(
        project_id=env.project_id,
        region=env.region,
        runtime_version=env.dataproc.runtime_version,
        service_account=env.dataproc.service_account,
        batch_id=batch_id_final,
        main_python_gcs=gcs_job_uri,
        properties=properties,
        args=job_args,
        labels=labels,
    )

    return SubmitResult(
        batch_id=batch_id_final,
        gcs_job_uri=gcs_job_uri,
        properties_sent=properties,
    )


# =============================================================================
# Debug helpers
# =============================================================================

def describe_batch(env: EnvConfig, batch_id: str) -> str:
    """
    Debug helper : affiche la description du batch (état, erreurs, resources, etc.)
    """
    p = run_cmd(
        [
            "gcloud", "dataproc", "batches", "describe", batch_id,
            "--project", env.project_id,
            "--region", env.region,
        ],
        check=True,
        capture=True,
    )
    return p.stdout or ""

