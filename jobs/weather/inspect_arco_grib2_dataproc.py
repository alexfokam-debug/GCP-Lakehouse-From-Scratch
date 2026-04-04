#!/usr/bin/env python3
# -*- coding: utf-8 -*-

################################################################################
# inspect_arco_grib2_dataproc.py
# ------------------------------------------------------------------------------
# OBJECTIF
# ------------------------------------------------------------------------------
# Ce script est conçu pour être exécuté dans Dataproc Serverless afin de :
#
# 1. Charger un fichier de configuration YAML embarqué dans le batch Dataproc
# 2. Vérifier que le runtime contient bien les bons binaires / bons modules
# 3. Télécharger localement un fichier GRIB2 depuis GCS vers /tmp
#    SANS dépendre de gsutil
# 4. Tester l’ouverture du fichier avec xarray + cfgrib
# 5. Afficher des informations de diagnostic très détaillées
#
# POURQUOI CE SCRIPT ?
# ------------------------------------------------------------------------------
# Dans ton projet lakehouse, tu veux industrialiser une chaîne d’ingestion de
# données météo ARCO / ERA5, et valider que ton runtime Dataproc custom est
# capable de :
# - accéder à GCS
# - manipuler les dépendances Python nécessaires
# - lire des fichiers GRIB2
#
# PROBLÈME INITIAL CORRIGÉ ICI
# ------------------------------------------------------------------------------
# Ton ancienne version utilisait "gsutil cp" pour récupérer le fichier brut.
# Or, dans ton conteneur Dataproc custom, gsutil n’est pas disponible.
#
# Cette version remplace donc complètement cette dépendance shell par :
#   google.cloud.storage
#
# AVANTAGES
# ------------------------------------------------------------------------------
# - plus propre
# - 100% Python
# - portable
# - moins fragile
# - mieux adapté à un runtime custom
################################################################################

from __future__ import annotations

################################################################################
# IMPORTS STANDARD LIBRARY
################################################################################

import importlib
import os
import shutil
import sys
import traceback
from pathlib import Path
from typing import Any

################################################################################
# IMPORTS TIERS
################################################################################

# PyYAML est nécessaire pour lire le fichier env.dev.yaml transmis via --files
import yaml

# Client Python GCS utilisé à la place de gsutil
from google.cloud import storage

################################################################################
# CONSTANTES
################################################################################

# Nom du fichier YAML tel qu’il est attendu dans le runtime Dataproc.
# Avec :
#   --files=configs/env.dev.yaml
# le fichier est généralement disponible localement sous :
#   ./env.dev.yaml
#
# On ne dépend donc plus d’un chemin forcé type /tmp/config_env.yaml.
DEFAULT_CONFIG_BASENAME = "env.dev.yaml"

# Dossier local technique pour déposer les gros fichiers téléchargés.
LOCAL_TMP_DIR = "/tmp"

################################################################################
# OUTILS D'AFFICHAGE / LOG
################################################################################


def print_header(title: str) -> None:
    """
    Affiche un titre de section très lisible dans les logs.

    Pourquoi ?
    ----------
    Dans Dataproc Serverless, les logs peuvent vite devenir longs.
    On structure donc fortement l’affichage pour faciliter :
    - le debug manuel
    - la lecture dans la console GCP
    - l’analyse après coup
    """
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


def print_kv(label: str, value: Any) -> None:
    """
    Affiche une paire clé/valeur simple.

    Exemple :
        [INFO] Python version: 3.11.8
    """
    print(f"[INFO] {label}: {value}")


################################################################################
# OUTILS GÉNÉRAUX
################################################################################


def binary_exists(binary_name: str) -> bool:
    """
    Vérifie si un binaire shell est présent dans le PATH du conteneur.

    Exemple :
    ---------
    - python
    - pip
    - gsutil
    - grib_ls
    - wgrib2

    Remarque :
    ----------
    Même si certains binaires sont absents, cela ne veut pas forcément dire
    que le job doit échouer. Le but ici est d’établir un diagnostic.
    """
    return shutil.which(binary_name) is not None


def safe_import(module_name: str) -> tuple[bool, str]:
    """
    Essaie d'importer dynamiquement un module Python.

    Retourne :
    ----------
    (True, "OK") si le module peut être importé
    (False, "<message d'erreur>") sinon

    Pourquoi cette forme ?
    ----------------------
    Cela permet de :
    - ne pas faire planter immédiatement le script
    - produire un rapport de diagnostic complet
    """
    try:
        importlib.import_module(module_name)
        return True, "OK"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


################################################################################
# CONFIG YAML
################################################################################


def resolve_config_path(config_basename: str = DEFAULT_CONFIG_BASENAME) -> str:
    """
    Résout le chemin du fichier de config transmis au job Dataproc.

    Dans Dataproc Serverless, un fichier transmis avec :
        --files=configs/env.dev.yaml

    devient généralement disponible dans le répertoire de travail sous :
        ./env.dev.yaml

    On teste donc plusieurs emplacements probables pour rendre le script robuste.
    """
    candidate_paths = [
        config_basename,
        f"./{config_basename}",
        f"/tmp/{config_basename}",
        os.path.join(os.getcwd(), config_basename),
    ]

    print(f"[INFO] Vérification existence config : {config_basename}")

    for candidate in candidate_paths:
        if os.path.exists(candidate):
            print(f"[OK] Fichier de config trouvé : {candidate}")
            return candidate

    raise FileNotFoundError(
        "Fichier de config introuvable dans le runtime Dataproc. "
        f"Chemins testés : {candidate_paths}"
    )


def load_env_config(config_basename: str = DEFAULT_CONFIG_BASENAME) -> dict[str, Any]:
    """
    Charge le YAML de configuration.

    Cette fonction attend un fichier de type :
        env.dev.yaml

    et retourne un dictionnaire Python.

    On reste volontairement permissif côté structure,
    car ton YAML a légèrement évolué pendant le projet.
    """
    config_path = resolve_config_path(config_basename)

    with open(config_path, "r", encoding="utf-8") as file:
        config = yaml.safe_load(file)

    if not isinstance(config, dict):
        raise ValueError(
            f"Le fichier YAML chargé ne contient pas un mapping valide : {config_path}"
        )

    return config


################################################################################
# EXTRACTION ROBUSTE DE PARAMÈTRES DE CONFIG
################################################################################


def get_project_id(config: dict[str, Any]) -> str:
    """
    Récupère le project_id depuis différentes structures possibles.

    On supporte plusieurs variantes observées dans ton projet :
    - config["project_id"]
    - config["gcp"]["project_id"]
    """
    if isinstance(config.get("project_id"), str) and config["project_id"].strip():
        return config["project_id"]

    gcp_block = config.get("gcp")
    if isinstance(gcp_block, dict):
        project_id = gcp_block.get("project_id")
        if isinstance(project_id, str) and project_id.strip():
            return project_id

    raise KeyError(
        "Impossible de trouver project_id dans la config. "
        "Clés attendues : project_id ou gcp.project_id"
    )


def get_raw_bucket_name(config: dict[str, Any]) -> str:
    """
    Récupère le nom du bucket RAW depuis la config.

    Variantes supportées :
    - config["gcs"]["raw_bucket"]
    """
    gcs_block = config.get("gcs")
    if isinstance(gcs_block, dict):
        raw_bucket = gcs_block.get("raw_bucket")
        if isinstance(raw_bucket, str) and raw_bucket.strip():
            return raw_bucket

    raise KeyError(
        "Impossible de trouver le bucket RAW dans la config. "
        "Clé attendue : gcs.raw_bucket"
    )


################################################################################
# GCS HELPERS
################################################################################


def parse_gcs_uri(gcs_uri: str) -> tuple[str, str]:
    """
    Découpe une URI GCS de type :
        gs://bucket/path/to/object

    Retourne :
        (bucket_name, object_name)

    Exemple :
        gs://my-bucket/folder/file.parquet
    ->  ("my-bucket", "folder/file.parquet")
    """
    if not gcs_uri.startswith("gs://"):
        raise ValueError(f"URI GCS invalide : {gcs_uri}")

    path_without_scheme = gcs_uri[len("gs://"):]
    parts = path_without_scheme.split("/", 1)

    if len(parts) != 2:
        raise ValueError(
            "URI GCS incomplète. Format attendu : gs://bucket/object ; "
            f"reçu : {gcs_uri}"
        )

    bucket_name = parts[0]
    object_name = parts[1]
    return bucket_name, object_name


def build_default_arco_raw_gcs_uri(config: dict[str, Any]) -> str:
    """
    Construit l’URI GCS du fichier brut à inspecter.

    Dans ton cas actuel, tu as déjà copié / promu le fichier dans :
        gs://lakehouse-486419-raw-dev/domain=weather/dataset=arco_era5/raw/...

    Ici on garde un comportement simple et explicite :
    - on utilise le bucket RAW depuis la config
    - on pointe vers un fichier de test connu

    Si plus tard tu veux rendre cela paramétrable dans le YAML,
    tu pourras facilement remplacer cette logique.
    """
    raw_bucket = get_raw_bucket_name(config)

    object_name = (
        "domain=weather/dataset=arco_era5/raw/19400101_hres_dve.grb2"
    )

    return f"gs://{raw_bucket}/{object_name}"


def download_gcs_blob_to_local(
    project_id: str,
    gcs_uri: str,
    local_path: str,
) -> None:
    """
    Télécharge un objet GCS vers un fichier local.

    Cette fonction remplace totalement :
        gsutil cp gs://... /tmp/...

    Pourquoi c'est mieux ici ?
    --------------------------
    - pas besoin de binaire gsutil dans le conteneur
    - cohérent avec un runtime Python
    - plus simple à contrôler depuis le code
    """
    bucket_name, object_name = parse_gcs_uri(gcs_uri)

    client = storage.Client(project=project_id)
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_name)

    if not blob.exists():
        raise FileNotFoundError(f"Objet GCS introuvable : {gcs_uri}")

    local_dir = os.path.dirname(local_path)
    if local_dir:
        os.makedirs(local_dir, exist_ok=True)

    print(f"[INFO] Téléchargement GCS -> local : {gcs_uri} -> {local_path}")
    blob.download_to_filename(local_path)
    print(f"[OK] Téléchargement terminé : {local_path}")


################################################################################
# DIAGNOSTICS RUNTIME
################################################################################


def diagnostic_runtime_binaries() -> None:
    """
    Affiche la présence ou l'absence des binaires utiles.

    Important :
    -----------
    L’absence de gsutil ne doit plus être bloquante.
    Ce diagnostic est informatif.
    """
    print_header("1) DIAGNOSTIC RUNTIME / BINAIRES")

    binaries_to_check = [
        "python",
        "pip",
        "gsutil",
        "grib_ls",
        "grib_dump",
        "wgrib2",
    ]

    for binary in binaries_to_check:
        binary_path = shutil.which(binary)
        if binary_path:
            print(f"[OK] binary found: {binary} -> {binary_path}")
        else:
            print(f"[KO] binary missing: {binary}")


def diagnostic_python_modules() -> None:
    """
    Vérifie les imports Python stratégiques pour le traitement GRIB2.
    """
    print_header("2) DIAGNOSTIC MODULES PYTHON")

    modules_to_check = [
        "xarray",
        "cfgrib",
        "eccodes",
        "pygrib",
        "google.cloud.storage",
        "pandas",
        "pyarrow",
    ]

    for module_name in modules_to_check:
        ok, message = safe_import(module_name)
        if ok:
            print(f"[OK] import Python module: {module_name}")
        else:
            print(f"[KO] import Python module: {module_name} -> {message}")


################################################################################
# TÉLÉCHARGEMENT LOCAL DU FICHIER RAW
################################################################################


def download_raw_file_for_inspection(config: dict[str, Any]) -> str:
    """
    Télécharge le fichier GRIB2 cible en local et retourne son chemin local.

    Cette fonction constitue la version corrigée de ta section 3.
    Elle n’utilise PAS gsutil.
    """
    print_header("3) TÉLÉCHARGEMENT LOCAL DU FICHIER RAW")

    project_id = get_project_id(config)
    raw_file_gcs_uri = build_default_arco_raw_gcs_uri(config)

    local_file_name = os.path.basename(parse_gcs_uri(raw_file_gcs_uri)[1])
    local_file_path = os.path.join(LOCAL_TMP_DIR, local_file_name)

    try:
        download_gcs_blob_to_local(
            project_id=project_id,
            gcs_uri=raw_file_gcs_uri,
            local_path=local_file_path,
        )

        print(f"[INFO] Local file exists: {os.path.exists(local_file_path)}")
        if os.path.exists(local_file_path):
            print(f"[INFO] Local file size: {os.path.getsize(local_file_path)} bytes")

        return local_file_path

    except Exception as exc:  # noqa: BLE001
        print(f"[KO] Échec du téléchargement GCS -> local : {exc}")
        print("[STOP] Le fichier raw n'a pas pu être téléchargé localement.")
        raise


################################################################################
# LECTURE / INSPECTION GRIB2
################################################################################


def try_open_grib_with_xarray_cfgrib(local_file_path: str) -> None:
    """
    Tente d’ouvrir le fichier GRIB2 avec xarray + cfgrib.

    Cette méthode est la plus naturelle dans ton futur pipeline Python / Spark
    pour l’exploration des données météo.
    """
    print_header("4) TENTATIVE D'OUVERTURE AVEC XARRAY + CFGRIB")

    try:
        import xarray as xr
    except Exception as exc:  # noqa: BLE001
        print(f"[KO] xarray indisponible: {exc}")
        raise

    try:
        dataset = xr.open_dataset(
            local_file_path,
            engine="cfgrib",
        )

        print("[OK] Ouverture GRIB2 réussie avec xarray/cfgrib")

        # Affichage de quelques infos structurantes
        print("\n[INFO] Représentation dataset :")
        print(dataset)

        print("\n[INFO] Variables détectées :")
        print(list(dataset.data_vars))

        print("\n[INFO] Coordonnées détectées :")
        print(list(dataset.coords))

        print("\n[INFO] Dimensions :")
        print(dict(dataset.dims))

        # Affiche un petit extrait si possible
        if dataset.data_vars:
            first_var_name = list(dataset.data_vars)[0]
            print(f"\n[INFO] Première variable détectée : {first_var_name}")
            print(dataset[first_var_name])

        dataset.close()

    except Exception as exc:  # noqa: BLE001
        print(f"[KO] Échec ouverture GRIB2 avec xarray/cfgrib : {exc}")
        raise


################################################################################
# MAIN
################################################################################


def main() -> None:
    """
    Point d’entrée principal du script.
    """
    print_header("INSPECTION GRIB2 ARCO / DATAPROC SERVERLESS")

    # -------------------------------------------------------------------------
    # Étape 0 — Chargement config
    # -------------------------------------------------------------------------
    config = load_env_config(DEFAULT_CONFIG_BASENAME)

    # -------------------------------------------------------------------------
    # Étape 1 — Diagnostics runtime
    # -------------------------------------------------------------------------
    diagnostic_runtime_binaries()

    # -------------------------------------------------------------------------
    # Étape 2 — Diagnostics modules Python
    # -------------------------------------------------------------------------
    diagnostic_python_modules()

    # -------------------------------------------------------------------------
    # Étape 3 — Téléchargement local du fichier brut
    # -------------------------------------------------------------------------
    local_file_path = download_raw_file_for_inspection(config)

    # -------------------------------------------------------------------------
    # Étape 4 — Test de lecture GRIB2
    # -------------------------------------------------------------------------
    try_open_grib_with_xarray_cfgrib(local_file_path)

    print_header("SUCCÈS")
    print("[OK] Inspection GRIB2 terminée avec succès.")


################################################################################
# EXÉCUTION
################################################################################

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print_header("ECHEC GLOBAL DU SCRIPT")
        print(f"[KO] {type(exc).__name__}: {exc}")
        print("\n[TRACEBACK COMPLET]")
        traceback.print_exc()
        sys.exit(1)