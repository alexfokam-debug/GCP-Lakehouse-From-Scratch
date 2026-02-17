# scripts/_env.py
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict
import yaml


ENV_FILE = Path("config/env.yaml")


def load_env_config(env: str) -> Dict[str, Any]:
    if not ENV_FILE.exists():
        raise FileNotFoundError(
            f"Config introuvable: {ENV_FILE}. Crée-le (ex: config/env.yaml) et relance."
        )

    data = yaml.safe_load(ENV_FILE.read_text(encoding="utf-8")) or {}
    if env not in data:
        raise KeyError(f"ENV '{env}' introuvable dans {ENV_FILE}. Clés dispo: {list(data.keys())}")

    # On renvoie seulement le bloc de l'env (dev/staging/prod)
    cfg = data[env] or {}
    if not isinstance(cfg, dict):
        raise TypeError(f"Le bloc '{env}' doit être un mapping YAML.")
    return cfg


def get_required(cfg: Dict[str, Any], key: str) -> Any:
    """
    Récupère une valeur dans cfg via:
    - clé simple: "project_id"
    - clé imbriquée: "bq.raw_dataset" ou "dataform.repo"

    Si absent → KeyError claire.
    """
    if "." not in key:
        if key not in cfg:
            raise KeyError(f"Clé requise manquante dans env config: '{key}'")
        return cfg[key]

    cur: Any = cfg
    for part in key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            raise KeyError(f"Clé requise manquante dans env config: '{key}'")
        cur = cur[part]
    return cur