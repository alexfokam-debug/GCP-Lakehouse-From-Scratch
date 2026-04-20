"""
===============================================================================
FICHIER : promote_landing_to_raw.py
===============================================================================

OBJECTIF
-------------------------------------------------------------------------------
Promouvoir les objets présents dans la zone landing vers la zone raw/bronze
du lakehouse.

RAPPEL ARCHITECTURAL
-------------------------------------------------------------------------------
Landing :
- zone d'arrivée technique
- zone tampon
- réception initiale des objets

Raw / Bronze :
- zone officielle d'entrée dans le lakehouse
- structure stable
- point de départ des traitements Dataproc

POURQUOI UNE PROMOTION ?
-------------------------------------------------------------------------------
On pourrait écrire directement en raw, mais la séparation landing/raw apporte :
- plus de clarté
- plus de contrôle
- plus de traçabilité
- un design plus "enterprise-grade"

NOTE
-------------------------------------------------------------------------------
Ici on réalise une copie interne au même bucket :
    landing -> raw
C'est donc une promotion logique de la donnée dans le cycle de vie du lakehouse.
===============================================================================
"""

# =============================================================================
# IMPORTS
# =============================================================================

from google.cloud import storage
from scripts.config_loader import load_env_config


# =============================================================================
# CHARGEMENT DE LA CONFIG
# =============================================================================
config = load_env_config("dev")

PROJECT_ID = config["project_id"]
BUCKET_NAME = config["buckets"]["raw"]

LANDING_PREFIX = config["pipelines"]["arco_era5"]["landing_prefix"]
RAW_PREFIX = config["pipelines"]["arco_era5"]["raw_prefix"]


# =============================================================================
# OUTIL D'AFFICHAGE
# =============================================================================
def print_header(title: str) -> None:
    """
    Affiche un titre visible dans les logs.

    Cette fonction améliore simplement la lisibilité de l'exécution.
    """
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================
def promote() -> None:
    """
    Copie tous les objets présents dans landing vers raw.

    DÉROULÉ
    ---------------------------------------------------------------------------
    1. Créer le client GCS
    2. Obtenir une référence au bucket raw
    3. Lister les objets présents sous le préfixe landing
    4. Pour chaque objet :
       - ignorer les pseudo-dossiers
       - récupérer son nom final
       - construire le chemin raw cible
       - copier l'objet dans raw

    REMARQUE
    ---------------------------------------------------------------------------
    On ne supprime pas ici les objets landing.
    On fait une promotion par copie.
    Plus tard, si besoin, on pourra ajouter :
    - archivage
    - nettoyage landing
    - idempotence plus avancée
    """
    print_header("PROMOTION LANDING -> RAW")

    # -------------------------------------------------------------------------
    # 1) Client GCS
    # -------------------------------------------------------------------------
    client = storage.Client(project=PROJECT_ID)

    # -------------------------------------------------------------------------
    # 2) Référence au bucket
    # -------------------------------------------------------------------------
    bucket = client.bucket(BUCKET_NAME)

    # -------------------------------------------------------------------------
    # 3) Liste des objets landing
    # -------------------------------------------------------------------------
    # list_blobs(...) parcourt les objets dont le nom commence par LANDING_PREFIX
    blobs = client.list_blobs(BUCKET_NAME, prefix=LANDING_PREFIX)

    # -------------------------------------------------------------------------
    # 4) Boucle sur les objets à promouvoir
    # -------------------------------------------------------------------------
    for blob in blobs:

        # ---------------------------------------------------------------------
        # 4.1) Ignorer les pseudo-dossiers
        # ---------------------------------------------------------------------
        # Dans GCS, les "dossiers" ne sont pas de vrais dossiers comme sur un
        # système de fichiers classique. On peut parfois rencontrer des objets
        # se terminant par "/" qu'on préfère ignorer ici.
        if blob.name.endswith("/"):
            continue

        # ---------------------------------------------------------------------
        # 4.2) Extraire le nom final du fichier
        # ---------------------------------------------------------------------
        filename = blob.name.split("/")[-1]

        # ---------------------------------------------------------------------
        # 4.3) Construire le chemin cible raw
        # ---------------------------------------------------------------------
        target_path = f"{RAW_PREFIX}{filename}"

        print(f"Promote {blob.name} -> {target_path}")

        # ---------------------------------------------------------------------
        # 4.4) Copier l'objet dans raw
        # ---------------------------------------------------------------------
        # Ici, source et destination sont dans le même bucket,
        # mais avec des préfixes différents.
        bucket.copy_blob(blob, bucket, target_path)

    print("Promotion landing -> raw terminée")


# =============================================================================
# POINT D'ENTRÉE
# =============================================================================
if __name__ == "__main__":
    promote()