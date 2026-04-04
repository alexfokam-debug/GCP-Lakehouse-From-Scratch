# =============================================================================
# transform_arco_grib2_to_prepared.py
# -----------------------------------------------------------------------------
# OBJECTIF
# -----------------------------------------------------------------------------
# Ce script constitue la première vraie brique de transformation du pipeline
# météo ARCO / ERA5 dans le lakehouse.
#
# Il lit un fichier GRIB2 stocké en zone RAW, l'ouvre avec xarray/cfgrib,
# sélectionne une variable scientifique cible, calcule une agrégation simple
# mais très utile, puis écrit le résultat en zone PREPARED au format Parquet.
#
# -----------------------------------------------------------------------------
# POURQUOI CETTE PREMIÈRE VERSION EST IMPORTANTE ?
# -----------------------------------------------------------------------------
# Les fichiers GRIB2 météo peuvent être extrêmement volumineux.
# Si on essaye dès le départ de "tout aplatir" en table complète
# (time x niveaux x grille spatiale), on risque :
# - des volumes énormes
# - des coûts élevés
# - des temps de traitement longs
# - des difficultés à exposer les données proprement
#
# Cette version choisit donc une stratégie INTELLIGENTE et PRAGMATIQUE :
# - on lit un vrai fichier GRIB2
# - on valide les dépendances scientifiques
# - on transforme la donnée en un résultat tabulaire léger
# - on écrit un artefact PREPARED facilement exploitable
#
# -----------------------------------------------------------------------------
# TRANSFORMATION EFFECTUÉE
# -----------------------------------------------------------------------------
# Input :
#   vo(time, hybrid, values)
#
# Calcul :
#   moyenne spatiale sur la dimension "values"
#
# Output tabulaire :
#   - time
#   - hybrid
#   - vo_mean
#   - source_file
#   - ingestion_ts
#
# Cela donne typiquement :
#   24 heures x 137 niveaux = 3288 lignes
#
# -----------------------------------------------------------------------------
# USAGE TYPIQUE
# -----------------------------------------------------------------------------
# gcloud dataproc batches submit pyspark \
#   gs://lakehouse-486419-scripts-dev/jobs/weather/transform_arco_grib2_to_prepared.py \
#   --region=europe-west1 \
#   --project=lakehouse-486419 \
#   --version=2.2 \
#   --deps-bucket=lakehouse-486419-dataproc-temp-dev \
#   --service-account=sa-dataproc-dev@lakehouse-486419.iam.gserviceaccount.com \
#   --files=configs/env.dev.yaml \
#   --container-image=europe-west1-docker.pkg.dev/lakehouse-486419/dataproc-custom/dataproc-grib:latest \
#   --properties="^#^spark.executor.memory=4g#spark.executor.cores=4"
# =============================================================================

from __future__ import annotations

# =============================================================================
# 1) IMPORTS STANDARD
# =============================================================================
import os
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Tuple

# =============================================================================
# 2) IMPORTS TIERS
# -----------------------------------------------------------------------------
# Ces librairies doivent être présentes dans le custom container Dataproc.
# =============================================================================
import yaml
import pandas as pd
import xarray as xr
from google.cloud import storage

# =============================================================================
# 3) CONSTANTES
# -----------------------------------------------------------------------------
# On utilise ici des constantes pour éviter les valeurs en dur dispersées.
# =============================================================================
DEFAULT_ENV_FILE_NAME = "env.dev.yaml"
DEFAULT_LOCAL_TMP_DIR = "/tmp"
DEFAULT_PIPELINE_KEY = "arco_era5"
DEFAULT_TARGET_VARIABLE = "vo"

# =============================================================================
# 4) HELPERS D'AFFICHAGE
# -----------------------------------------------------------------------------
# Petites fonctions pour rendre les logs plus lisibles.
# =============================================================================
def print_section(title: str) -> None:
    """Affiche un titre de section visuel dans les logs."""
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


def print_info(message: str) -> None:
    """Affiche un message d'information standardisé."""
    print(f"[INFO] {message}")


def print_ok(message: str) -> None:
    """Affiche un message de succès standardisé."""
    print(f"[OK] {message}")


def print_ko(message: str) -> None:
    """Affiche un message d'erreur standardisé."""
    print(f"[KO] {message}")


# =============================================================================
# 5) CHARGEMENT DE LA CONFIGURATION
# -----------------------------------------------------------------------------
# Le job Dataproc reçoit le fichier via --files=configs/env.dev.yaml.
# Dans le runtime, le fichier est généralement disponible sous son nom simple :
#   env.dev.yaml
# =============================================================================
def resolve_config_path(expected_file_name: str = DEFAULT_ENV_FILE_NAME) -> Path:
    """
    Résout le chemin du fichier de config dans le runtime Dataproc.

    On commence par chercher :
    - le nom simple du fichier dans le répertoire courant
    - puis /tmp si besoin

    Raises:
        FileNotFoundError: si le fichier n'est pas trouvé
    """
    candidates = [
        Path(expected_file_name),
        Path(DEFAULT_LOCAL_TMP_DIR) / expected_file_name,
    ]

    print_info(f"Vérification existence config : {expected_file_name}")

    for candidate in candidates:
        if candidate.exists():
            print_ok(f"Fichier de config trouvé : {candidate}")
            return candidate

    raise FileNotFoundError(
        f"Fichier de config introuvable dans le runtime Dataproc. "
        f"Nom attendu : {expected_file_name}"
    )


def load_env_config() -> Dict[str, Any]:
    """
    Charge le YAML de configuration environnement.

    Returns:
        dict: contenu YAML parsé
    """
    config_path = resolve_config_path()
    with config_path.open("r", encoding="utf-8") as file:
        return yaml.safe_load(file)


# =============================================================================
# 6) HELPERS CONFIG
# -----------------------------------------------------------------------------
# Ici on centralise tous les accès à la config YAML pour éviter de répéter
# partout des chemins du type config["pipelines"]["arco_era5"]["raw_prefix"].
# =============================================================================
def get_pipeline_config(config: Dict[str, Any], pipeline_key: str = DEFAULT_PIPELINE_KEY) -> Dict[str, Any]:
    """
    Retourne la sous-configuration d'un pipeline.

    Raises:
        KeyError: si la clé pipeline n'existe pas
    """
    pipelines = config.get("pipelines", {})
    if pipeline_key not in pipelines:
        raise KeyError(f"Pipeline '{pipeline_key}' introuvable dans config['pipelines']")
    return pipelines[pipeline_key]


def get_bucket_name(config: Dict[str, Any], bucket_key: str) -> str:
    """
    Retourne le nom d'un bucket depuis la section buckets.

    Exemple:
        get_bucket_name(config, "raw") -> lakehouse-486419-raw-dev
    """
    buckets = config.get("buckets", {})
    if bucket_key not in buckets or not buckets[bucket_key]:
        raise KeyError(f"Bucket introuvable dans config['buckets']['{bucket_key}']")
    return buckets[bucket_key]


def get_raw_bucket_name(config: Dict[str, Any]) -> str:
    """Retourne le bucket RAW."""
    return get_bucket_name(config, "raw")


def get_curated_bucket_name(config: Dict[str, Any]) -> str:
    """Retourne le bucket CURATED."""
    return get_bucket_name(config, "curated")


def get_sample_file_name(config: Dict[str, Any]) -> str:
    """
    Retourne le fichier d'exemple configuré pour le pipeline ARCO.
    """
    pipeline_cfg = get_pipeline_config(config)
    sample_file = pipeline_cfg.get("sample_file")
    if not sample_file:
        raise KeyError("Clé manquante : pipelines.arco_era5.sample_file")
    return sample_file


def get_raw_prefix(config: Dict[str, Any]) -> str:
    """
    Retourne le préfixe RAW du pipeline ARCO.

    Exemple:
        domain=weather/dataset=arco_era5/raw/
    """
    pipeline_cfg = get_pipeline_config(config)
    raw_prefix = pipeline_cfg.get("raw_prefix")
    if not raw_prefix:
        raise KeyError("Clé manquante : pipelines.arco_era5.raw_prefix")
    return raw_prefix


def get_prepared_prefix(config: Dict[str, Any]) -> str:
    """
    Retourne le préfixe PREPARED du pipeline ARCO.

    Exemple:
        domain=weather/dataset=arco_era5/prepared/
    """
    pipeline_cfg = get_pipeline_config(config)
    prepared_prefix = pipeline_cfg.get("prepared_prefix")
    if not prepared_prefix:
        raise KeyError("Clé manquante : pipelines.arco_era5.prepared_prefix")
    return prepared_prefix


def build_raw_gcs_uri(config: Dict[str, Any]) -> str:
    """
    Construit l'URI GCS complet du fichier RAW à lire.

    Exemple:
        gs://lakehouse-486419-raw-dev/domain=weather/dataset=arco_era5/raw/19400101_hres_dve.grb2
    """
    raw_bucket = get_raw_bucket_name(config)
    raw_prefix = get_raw_prefix(config)
    sample_file = get_sample_file_name(config)

    return f"gs://{raw_bucket}/{raw_prefix}{sample_file}"


def build_prepared_object_name(config: Dict[str, Any], variable_name: str) -> str:
    """
    Construit le nom de l'objet GCS de sortie dans PREPARED.

    Convention proposée :
      domain=weather/dataset=arco_era5/prepared/
      daily_vertical_profile_vo/19400101_hres_dve.parquet

    Cette convention est lisible et extensible.
    """
    prepared_prefix = get_prepared_prefix(config)
    sample_file = get_sample_file_name(config)

    # On retire l'extension .grb2 pour produire un nom propre en sortie.
    base_name = sample_file.replace(".grb2", "")

    return (
        f"{prepared_prefix}"
        f"daily_vertical_profile_{variable_name}/"
        f"{base_name}.parquet"
    )


# =============================================================================
# 7) GCS HELPERS
# -----------------------------------------------------------------------------
# Ici on remplace complètement gsutil par le SDK Python officiel.
# C'est plus robuste dans un container custom.
# =============================================================================
def parse_gcs_uri(gcs_uri: str) -> Tuple[str, str]:
    """
    Décompose une URI GCS en (bucket_name, object_name).

    Exemple:
        gs://my-bucket/path/file.parquet
        -> ("my-bucket", "path/file.parquet")
    """
    if not gcs_uri.startswith("gs://"):
        raise ValueError(f"URI GCS invalide : {gcs_uri}")

    without_scheme = gcs_uri.replace("gs://", "", 1)
    parts = without_scheme.split("/", 1)

    bucket_name = parts[0]
    object_name = parts[1] if len(parts) > 1 else ""

    if not bucket_name or not object_name:
        raise ValueError(f"URI GCS invalide ou incomplète : {gcs_uri}")

    return bucket_name, object_name


def download_gcs_file_to_local(gcs_uri: str, local_path: str) -> str:
    """
    Télécharge un objet GCS vers un chemin local.

    Returns:
        str: chemin local final
    """
    bucket_name, object_name = parse_gcs_uri(gcs_uri)

    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_name)

    print_info(f"Téléchargement GCS -> local : {gcs_uri} -> {local_path}")
    blob.download_to_filename(local_path)
    print_ok(f"Téléchargement terminé : {local_path}")

    return local_path


def upload_local_file_to_gcs(local_path: str, bucket_name: str, object_name: str) -> str:
    """
    Upload un fichier local vers GCS.

    Returns:
        str: URI GCS finale
    """
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_name)

    print_info(f"Upload local -> GCS : {local_path} -> gs://{bucket_name}/{object_name}")
    blob.upload_from_filename(local_path)
    print_ok("Upload GCS terminé")

    return f"gs://{bucket_name}/{object_name}"


# =============================================================================
# 8) LECTURE SCIENTIFIQUE DU FICHIER GRIB2
# -----------------------------------------------------------------------------
# On lit le fichier avec xarray + moteur cfgrib.
# =============================================================================
def open_grib_dataset(local_grib_path: str) -> xr.Dataset:
    """
    Ouvre un fichier GRIB2 avec xarray/cfgrib.

    Raises:
        RuntimeError: si l'ouverture échoue
    """
    try:
        dataset = xr.open_dataset(
            local_grib_path,
            engine="cfgrib",
        )
        return dataset
    except Exception as exc:
        raise RuntimeError(f"Echec ouverture GRIB2 avec xarray/cfgrib : {exc}") from exc


def validate_target_variable(dataset: xr.Dataset, variable_name: str) -> None:
    """
    Vérifie que la variable cible existe bien dans le dataset.
    """
    if variable_name not in dataset.data_vars:
        available_vars = list(dataset.data_vars)
        raise KeyError(
            f"Variable '{variable_name}' absente du dataset. "
            f"Variables disponibles : {available_vars}"
        )


# =============================================================================
# 9) TRANSFORMATION PREPARED
# -----------------------------------------------------------------------------
# On calcule ici une sortie tabulaire légère :
# moyenne spatiale de la variable par heure et niveau hybride.
# =============================================================================
def build_vertical_profile_dataframe(
    dataset: xr.Dataset,
    variable_name: str,
    source_file_name: str,
) -> pd.DataFrame:
    """
    Construit un DataFrame prepared à partir du dataset GRIB2
    en traitant le fichier par tranche de temps pour éviter
    une explosion mémoire sur le driver.

    Stratégie :
    - on ne fait PAS la moyenne sur tout le cube d'un coup
    - on boucle heure par heure
    - chaque slice temporelle est beaucoup plus petite
    - on concatène les petits résultats à la fin
    """
    validate_target_variable(dataset, variable_name)

    data_array = dataset[variable_name]

    print_info(f"Variable sélectionnée : {variable_name}")
    print_info(f"Dimensions de la variable : {tuple(data_array.dims)}")

    if "values" not in data_array.dims:
        raise KeyError(
            f"La dimension 'values' est absente de la variable '{variable_name}'. "
            f"Dimensions trouvées : {tuple(data_array.dims)}"
        )

    if "time" not in data_array.dims:
        raise KeyError(
            f"La dimension 'time' est absente de la variable '{variable_name}'. "
            f"Dimensions trouvées : {tuple(data_array.dims)}"
        )

    # -------------------------------------------------------------------------
    # IMPORTANT
    # -------------------------------------------------------------------------
    # Au lieu de faire :
    #   data_array.mean(dim="values")
    # sur tout le dataset d'un coup,
    # on traite time par time pour réduire la pression mémoire.
    # -------------------------------------------------------------------------
    nb_times = data_array.sizes["time"]
    partial_frames = []

    ingestion_ts = datetime.now(timezone.utc).isoformat()

    for i in range(nb_times):
        print_info(f"Traitement slice temporelle {i + 1}/{nb_times}")

        # On isole une seule heure :
        # dimensions attendues après isel(time=i) :
        #   hybrid x values
        one_time_slice = data_array.isel(time=i)

        # Réduction mémoire :
        # - cast explicite float32
        # - moyenne spatiale sur "values"
        reduced_slice = one_time_slice.astype("float32").mean(dim="values", skipna=True)

        # Conversion en petit DataFrame
        slice_df = reduced_slice.to_dataframe(name=f"{variable_name}_mean").reset_index()

        # On réinjecte explicitement la coordonnée time
        # car après isel(time=i), elle n'apparaît pas toujours comme colonne.
        time_value = pd.Timestamp(data_array["time"].values[i])
        slice_df["time"] = time_value

        # Métadonnées de traçabilité
        slice_df["source_file"] = source_file_name
        slice_df["ingestion_ts"] = ingestion_ts

        # Ordre lisible
        ordered_columns = [
            "time",
            "hybrid",
            f"{variable_name}_mean",
            "source_file",
            "ingestion_ts",
        ]
        existing_columns = [col for col in ordered_columns if col in slice_df.columns]
        remaining_columns = [col for col in slice_df.columns if col not in existing_columns]
        slice_df = slice_df[existing_columns + remaining_columns]

        partial_frames.append(slice_df)

        # Petit log utile
        print_info(f"Slice {i + 1}/{nb_times} terminée - {len(slice_df)} lignes")

    final_df = pd.concat(partial_frames, ignore_index=True)

    return final_df

# =============================================================================
# 10) ECRITURE LOCALE PARQUET
# -----------------------------------------------------------------------------
# On écrit d'abord localement dans /tmp, puis on upload dans GCS.
# =============================================================================
def write_dataframe_to_local_parquet(df: pd.DataFrame, local_output_path: str) -> str:
    """
    Ecrit un DataFrame pandas au format Parquet local.

    Returns:
        str: chemin du parquet local
    """
    parent_dir = Path(local_output_path).parent
    parent_dir.mkdir(parents=True, exist_ok=True)

    df.to_parquet(local_output_path, index=False)
    print_ok(f"Parquet local écrit : {local_output_path}")

    return local_output_path


# =============================================================================
# 11) PIPELINE PRINCIPAL
# =============================================================================
def main() -> None:
    """
    Exécution principale du pipeline.

    Etapes :
    1. charger la config
    2. construire URI input/output
    3. télécharger le GRIB2 localement
    4. lire le dataset
    5. transformer en DataFrame léger
    6. écrire parquet local
    7. uploader vers GCS prepared
    """
    print_section("TRANSFORMATION GRIB2 ARCO -> PREPARED")

    config = load_env_config()

    variable_name = DEFAULT_TARGET_VARIABLE
    source_file_name = get_sample_file_name(config)

    # -------------------------------------------------------------------------
    # 1) INPUT RAW
    # -------------------------------------------------------------------------
    raw_gcs_uri = build_raw_gcs_uri(config)
    local_grib_path = os.path.join(DEFAULT_LOCAL_TMP_DIR, source_file_name)

    print_section("1) TELECHARGEMENT RAW DEPUIS GCS")
    download_gcs_file_to_local(raw_gcs_uri, local_grib_path)

    print_info(f"Local file exists: {os.path.exists(local_grib_path)}")
    print_info(f"Local file size: {os.path.getsize(local_grib_path)} bytes")

    # -------------------------------------------------------------------------
    # 2) OUVERTURE SCIENTIFIQUE
    # -------------------------------------------------------------------------
    print_section("2) OUVERTURE DU FICHIER GRIB2")
    dataset = open_grib_dataset(local_grib_path)
    dataset = dataset[[variable_name]]

    print_ok("Ouverture GRIB2 réussie avec xarray/cfgrib")
    print_info(f"Variables détectées : {list(dataset.data_vars)}")
    print_info(f"Coordonnées détectées : {list(dataset.coords)}")
    print_info(f"Dimensions détectées : {dict(dataset.sizes)}")

    # -------------------------------------------------------------------------
    # 3) TRANSFORMATION PREPARED
    # -------------------------------------------------------------------------
    print_section("3) TRANSFORMATION EN PROFIL VERTICAL MOYEN")
    prepared_df = build_vertical_profile_dataframe(
        dataset=dataset,
        variable_name=variable_name,
        source_file_name=source_file_name,
    )

    print_ok("Transformation tabulaire terminée")
    print_info(f"Nombre de lignes prepared : {len(prepared_df)}")
    print_info(f"Colonnes : {list(prepared_df.columns)}")

    # Affichage d'un échantillon utile pour debug
    print_info("Aperçu des 10 premières lignes :")
    print(prepared_df.head(10).to_string(index=False))

    # -------------------------------------------------------------------------
    # 4) ECRITURE PARQUET LOCALE
    # -------------------------------------------------------------------------
    print_section("4) ECRITURE PARQUET LOCALE")
    local_output_path = os.path.join(
        DEFAULT_LOCAL_TMP_DIR,
        f"{source_file_name.replace('.grb2', '')}_{variable_name}_vertical_profile.parquet",
    )
    write_dataframe_to_local_parquet(prepared_df, local_output_path)

    # -------------------------------------------------------------------------
    # 5) UPLOAD VERS GCS PREPARED
    # -------------------------------------------------------------------------
    print_section("5) UPLOAD VERS GCS PREPARED")
    prepared_bucket = get_curated_bucket_name(config)
    prepared_object_name = build_prepared_object_name(config, variable_name)

    final_gcs_uri = upload_local_file_to_gcs(
        local_path=local_output_path,
        bucket_name=prepared_bucket,
        object_name=prepared_object_name,
    )

    print_ok(f"Artefact prepared disponible : {final_gcs_uri}")

    # -------------------------------------------------------------------------
    # 6) FIN
    # -------------------------------------------------------------------------
    dataset.close()
    print_section("SUCCES")
    print_ok("Transformation GRIB2 -> PREPARED terminée avec succès.")


# =============================================================================
# 12) POINT D'ENTREE
# =============================================================================
if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print_section("ECHEC GLOBAL DU SCRIPT")
        print_ko(f"{type(exc).__name__}: {exc}")
        print("\n[TRACEBACK COMPLET]")
        print(traceback.format_exc())
        sys.exit(1)