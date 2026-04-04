"""
===============================================================================
FICHIER : config_loader.py
===============================================================================

OBJECTIF
-------------------------------------------------------------------------------
Ce fichier centralise le chargement de la configuration YAML d'environnement.

Pourquoi c'est important ?
-------------------------------------------------------------------------------
Dans une architecture data propre, on ne veut pas écrire partout en dur :
- le project_id
- les buckets GCS
- les datasets BigQuery
- les chemins landing / raw / prepared
- les objets source à copier

On préfère une seule source de vérité :
    configs/env.dev.yaml
    configs/env.staging.yaml
    configs/env.prod.yaml

Ce fichier permet donc à tous les scripts Python de lire la même config.

UTILISATION
-------------------------------------------------------------------------------
Depuis un autre script :

    from scripts.config_loader import load_env_config

    config = load_env_config("dev")
    project_id = config["project_id"]

BÉNÉFICES
-------------------------------------------------------------------------------
- cohérence entre les scripts
- facilité de changement d'environnement
- meilleure lisibilité
- moins de duplication
- plus simple pour CI/CD et Composer plus tard
===============================================================================
"""

# =============================================================================
# IMPORTS
# =============================================================================

# Path sert à manipuler proprement les chemins de fichiers et dossiers.
# C'est plus robuste que concaténer des strings à la main.
from pathlib import Path

# Dict et Any servent au typage Python.
# - Dict[str, Any] signifie "un dictionnaire avec clés string et valeurs diverses"
from typing import Any, Dict

# yaml.safe_load permet de lire un fichier YAML et de le convertir en dict Python.
import yaml


# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================
def load_env_config(env: str = "dev") -> Dict[str, Any]:
    """
    Charge le fichier de configuration YAML correspondant à un environnement.

    PARAMÈTRES
    ---------------------------------------------------------------------------
    env : str
        Nom de l'environnement à charger.
        Exemples :
        - "dev"
        - "staging"
        - "prod"

    FONCTIONNEMENT
    ---------------------------------------------------------------------------
    1. On remonte à la racine du repo
    2. On construit le chemin du fichier YAML
    3. On vérifie que le fichier existe
    4. On l'ouvre
    5. On parse le YAML en dictionnaire Python

    RETOUR
    ---------------------------------------------------------------------------
    Dict[str, Any]
        Le contenu du YAML transformé en dictionnaire Python.

    EXEMPLE
    ---------------------------------------------------------------------------
    Si env = "dev", on charge :
        configs/env.dev.yaml

    Puis on peut accéder à :
        config["project_id"]
        config["buckets"]["raw"]
        config["pipelines"]["arco_era5"]["landing_prefix"]

    ERREUR POSSIBLE
    ---------------------------------------------------------------------------
    FileNotFoundError
        Si le fichier YAML demandé n'existe pas.
    """

    # -------------------------------------------------------------------------
    # 1) Déterminer la racine du repo
    # -------------------------------------------------------------------------
    # __file__ = chemin absolu du fichier courant (config_loader.py)
    # .resolve() = normalise en chemin absolu
    # .parent = dossier contenant ce fichier, donc "scripts/"
    # .parent.parent = dossier parent de "scripts/", donc racine du repo
    repo_root = Path(__file__).resolve().parent.parent

    # -------------------------------------------------------------------------
    # 2) Construire dynamiquement le chemin du fichier de config
    # -------------------------------------------------------------------------
    # Exemple si env="dev" :
    # repo_root / "configs" / "env.dev.yaml"
    #
    # Cela donne quelque chose comme :
    # /Users/.../GCP-Lakehouse-From-Scratch/configs/env.dev.yaml
    config_path = repo_root / "configs" / f"env.{env}.yaml"

    # -------------------------------------------------------------------------
    # 3) Vérifier que le fichier existe avant de l'ouvrir
    # -------------------------------------------------------------------------
    # Cela évite des erreurs plus floues plus tard.
    if not config_path.exists():
        raise FileNotFoundError(f"Configuration introuvable : {config_path}")

    # -------------------------------------------------------------------------
    # 4) Ouvrir le fichier en lecture
    # -------------------------------------------------------------------------
    # encoding="utf-8" : bonne pratique standard pour lire un fichier texte
    with open(config_path, "r", encoding="utf-8") as f:

        # ---------------------------------------------------------------------
        # 5) Parser le YAML
        # ---------------------------------------------------------------------
        # yaml.safe_load() lit le contenu YAML et le transforme en dict Python.
        #
        # Pourquoi safe_load et pas load ?
        # - safe_load est plus sûr
        # - il évite l'exécution d'objets arbitraires
        return yaml.safe_load(f)