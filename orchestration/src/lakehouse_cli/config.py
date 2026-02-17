from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import yaml


# =============================================================================
# Types (alignés sur tes YAML actuels, sans les changer)
# =============================================================================

from typing import Optional
from pydantic import BaseModel

class BucketsConfig(BaseModel):
    scripts: str
    iceberg: str
    dataproc_temp: Optional[str] = None  # buckets.dataproc_temp (dans ton YAML)

class IcebergConfig(BaseModel):
    warehouse_uri: str
    catalog_name: str
    db: str
    table: str
    raw_table: str

class DataprocConfig(BaseModel):
    runtime_version: str
    service_account: str
    iceberg_package: str
    temp_bucket: Optional[str] = None  # dataproc.temp_bucket (optionnel si tu préfères)

class EnvConfig(BaseModel):
    project_id: str
    region: str
    env: str

    buckets: BucketsConfig
    iceberg: IcebergConfig
    dataproc: DataprocConfig

    @property
    def dataproc_temp_bucket(self) -> Optional[str]:
        # Priorité: buckets.dataproc_temp, sinon dataproc.temp_bucket
        return self.buckets.dataproc_temp or self.dataproc.temp_bucket

    @property
    def raw_table(self) -> str:
        return self.iceberg.raw_table

    @property
    def iceberg_catalog_name(self) -> str:
        return self.iceberg.catalog_name

    @property
    def iceberg_db(self) -> str:
        return self.iceberg.db

    @property
    def iceberg_table(self) -> str:
        return self.iceberg.table
@dataclass(frozen=True)
class DataprocProfile:
    """
    Profil de sizing Spark (venant de profiles.yaml).

    Tu gardes exactement tes champs actuels :
      spark.driver.cores, spark.driver.memory, spark.executor.instances, etc.
    """
    name: str
    # champs "obligatoires" attendus
    driver_cores: int
    driver_memory: str
    executor_instances: int
    executor_cores: int
    executor_memory: str

    # overrides/tuning optionnels (ex: dynamicAllocation.executorAllocationRatio)
    extra_spark_properties: Dict[str, str]


# =============================================================================
# IO YAML
# =============================================================================

def _read_yaml(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"YAML introuvable: {path.resolve()}")
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"YAML invalide (doit être un mapping): {path}")
    return data


# =============================================================================
# Loaders publics (ceux que ton CLI importe)
# =============================================================================

def load_env_config(env_file: str | Path) -> EnvConfig:
    """
    Charge env.dev.yaml (ta structure actuelle).

    Attendu (extrait) :
    project_id, region, env
    buckets: {scripts, iceberg}
    iceberg: {warehouse_uri, catalog_name, db, table, raw_table}
    dataproc: {runtime_version, service_account, iceberg_package}
    """
    path = Path(env_file)
    raw = _read_yaml(path)

    # champs racine
    project_id = raw["project_id"]
    region = raw["region"]
    env = raw["env"]

    # buckets
    buckets = raw["buckets"]
    scripts_bucket = buckets["scripts"]
    iceberg_bucket = buckets["iceberg"]

    # iceberg
    iceberg = raw["iceberg"]
    warehouse_uri = iceberg["warehouse_uri"]
    catalog_name = iceberg["catalog_name"]
    db = iceberg["db"]
    table = iceberg["table"]
    raw_table = iceberg["raw_table"]

    # dataproc
    dp = raw["dataproc"]
    runtime_version = dp["runtime_version"]
    service_account = dp["service_account"]
    iceberg_package = dp["iceberg_package"]

    # buckets (avec dataproc_temp optionnel)
    buckets_cfg = BucketsConfig(
        scripts=scripts_bucket,
        iceberg=iceberg_bucket,
        dataproc_temp=buckets.get("dataproc_temp"),
    )

    # iceberg
    iceberg_cfg = IcebergConfig(
        warehouse_uri=warehouse_uri,
        catalog_name=catalog_name,
        db=db,
        table=table,
        raw_table=raw_table,
    )

    # dataproc (avec temp_bucket optionnel)
    dataproc_cfg = DataprocConfig(
        runtime_version=runtime_version,
        service_account=service_account,
        iceberg_package=iceberg_package,
        temp_bucket=dp.get("temp_bucket"),
    )

    return EnvConfig(
        project_id=project_id,
        region=region,
        env=env,
        buckets=buckets_cfg,
        iceberg=iceberg_cfg,
        dataproc=dataproc_cfg,
    )

def load_profile_properties(
    profiles_file: str | Path,
    profile_name: str,
) -> DataprocProfile:
    """
    Charge profiles.yaml (ta structure actuelle) et retourne un DataprocProfile.

    Attendu :
    profiles:
      dev_small:
        properties:
          spark.driver.cores: "2"
          spark.driver.memory: "4g"
          spark.executor.instances: "2"
          spark.executor.cores: "2"
          spark.executor.memory: "4g"
          spark.dynamicAllocation.executorAllocationRatio: "0.2"
    """
    path = Path(profiles_file)
    raw = _read_yaml(path)

    profiles = raw.get("profiles")
    if not isinstance(profiles, dict):
        raise ValueError("profiles.yaml invalide: clé 'profiles' manquante ou incorrecte")

    p = profiles.get(profile_name)
    if not isinstance(p, dict):
        available = ", ".join(sorted(profiles.keys()))
        raise KeyError(f"Profile '{profile_name}' introuvable. Disponibles: {available}")

    props = p.get("properties")
    if not isinstance(props, dict):
        raise ValueError(f"Profile '{profile_name}' invalide: 'properties' manquant")

    # --- champs obligatoires ---
    def req(key: str) -> str:
        if key not in props:
            raise KeyError(f"Profile '{profile_name}': propriété manquante: {key}")
        return str(props[key])

    driver_cores = int(req("spark.driver.cores"))
    driver_memory = req("spark.driver.memory")
    executor_instances = int(req("spark.executor.instances"))
    executor_cores = int(req("spark.executor.cores"))
    executor_memory = req("spark.executor.memory")

    # --- extras = le reste ---
    base_keys = {
        "spark.driver.cores",
        "spark.driver.memory",
        "spark.executor.instances",
        "spark.executor.cores",
        "spark.executor.memory",
    }
    extra: Dict[str, str] = {k: str(v) for k, v in props.items() if k not in base_keys}

    return DataprocProfile(
        name=profile_name,
        driver_cores=driver_cores,
        driver_memory=driver_memory,
        executor_instances=executor_instances,
        executor_cores=executor_cores,
        executor_memory=executor_memory,
        extra_spark_properties=extra,
    )