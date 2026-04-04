"""
===============================================================================
FICHIER : copy_arco_to_landing.py
===============================================================================

OBJECTIF
-------------------------------------------------------------------------------
Copier un petit sous-ensemble de fichiers ARCO ERA5 depuis le bucket public GCS
vers la zone LANDING de notre lakehouse.

POURQUOI UNE ZONE LANDING ?
-------------------------------------------------------------------------------
Dans une architecture data propre, on distingue souvent :
- la source publique / externe
- la zone landing (arrivée technique)
- la zone raw / bronze (entrée officielle du lakehouse)

Donc ici :
    bucket public GCS
        ↓
    landing
        ↓
    raw

Pourquoi ne pas copier directement dans raw ?
-------------------------------------------------------------------------------
On pourrait, mais landing permet :
- de distinguer l'arrivée technique de la donnée
- de garder une étape tampon
- de mieux orchestrer / contrôler / versionner plus tard

IMPORTANT
-------------------------------------------------------------------------------
On utilise la méthode "rewrite" et non "copy_blob", car certains objets GCS
volumineux ou inter-buckets / inter-zones peuvent échouer avec copy_blob.

ARCHITECTURE
-------------------------------------------------------------------------------
Dataset public GCS
    ↓
copy_arco_to_landing.py
    ↓
GCS Landing
===============================================================================
"""

# =============================================================================
# IMPORTS
# =============================================================================

# Client officiel Google Cloud Storage
from google.cloud import storage

# Chargeur de configuration centralisé
from scripts.config_loader import load_env_config


# =============================================================================
# CHARGEMENT DE LA CONFIG
# =============================================================================

# On charge la config DEV.
# Plus tard, on pourra rendre l'environnement paramétrable via argparse ou CLI.
config = load_env_config("dev")

# -----------------------------------------------------------------------------
# Valeurs globales récupérées depuis le YAML
# -----------------------------------------------------------------------------
PROJECT_ID = config["project_id"]

# Bucket public source ARCO ERA5
SOURCE_BUCKET_NAME = config["pipelines"]["arco_era5"]["source_bucket"]

# Bucket raw du lakehouse ; on y place la zone landing
TARGET_BUCKET_NAME = config["buckets"]["raw"]

# Liste des objets source qu'on veut copier depuis le bucket public
SOURCE_OBJECTS = config["pipelines"]["arco_era5"]["source_objects"]

# Préfixe landing dans le bucket cible
LANDING_PREFIX = config["pipelines"]["arco_era5"]["landing_prefix"]


# =============================================================================
# OUTIL D'AFFICHAGE
# =============================================================================
def print_header(title: str) -> None:
    """
    Affiche un titre bien visible dans les logs.

    PARAMÈTRES
    ---------------------------------------------------------------------------
    title : str
        Le texte du titre à afficher.

    POURQUOI CETTE FONCTION ?
    ---------------------------------------------------------------------------
    Dans les scripts data, avoir des logs lisibles est très important.
    Cette fonction améliore la lisibilité pendant les exécutions.
    """
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


# =============================================================================
# FONCTION DE COPIE ROBUSTE GCS -> GCS
# =============================================================================
def rewrite_blob(source_blob, destination_blob) -> None:
    """
    Copie robuste d'un objet GCS vers un autre objet GCS via la méthode rewrite.

    POURQUOI UTILISER rewrite() ?
    ---------------------------------------------------------------------------
    La méthode copy_blob() peut échouer si :
    - la copie est volumineuse
    - la copie traverse différents emplacements
    - la copie implique des classes de stockage différentes
    - la copie ne peut pas se terminer rapidement

    rewrite() fonctionne de manière incrémentale :
    - GCS copie une partie de l'objet
    - renvoie un token
    - on relance avec ce token
    - jusqu'à la fin complète

    PARAMÈTRES
    ---------------------------------------------------------------------------
    source_blob :
        Référence vers l'objet source dans le bucket public.

    destination_blob :
        Référence vers l'objet destination dans le bucket landing.

    RETOUR
    ---------------------------------------------------------------------------
    Aucun.
    La fonction se termine seulement quand la copie est entièrement complétée.
    """
    # -------------------------------------------------------------------------
    # token = état intermédiaire de la copie
    # -------------------------------------------------------------------------
    # Tant que token n'est pas None, cela signifie que la copie n'est pas finie.
    token = None

    while True:
        # ---------------------------------------------------------------------
        # rewrite() renvoie 3 éléments :
        # - token : à réutiliser si la copie n'est pas terminée
        # - bytes_rewritten : nombre d'octets déjà copiés
        # - total_bytes : taille totale de l'objet
        # ---------------------------------------------------------------------
        token, bytes_rewritten, total_bytes = destination_blob.rewrite(
            source=source_blob,
            token=token,
        )

        # ---------------------------------------------------------------------
        # Log de progression : très utile pour les gros objets
        # ---------------------------------------------------------------------
        print(
            f"    Progression copie: {bytes_rewritten}/{total_bytes} octets"
        )

        # ---------------------------------------------------------------------
        # Fin de copie
        # ---------------------------------------------------------------------
        # Quand token devient None, GCS indique que la copie est terminée.
        if token is None:
            break


# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================
def copy_sample_to_landing() -> None:
    """
    Copie un échantillon de fichiers ARCO ERA5 vers la zone landing du lakehouse.

    DÉROULÉ
    ---------------------------------------------------------------------------
    1. Créer le client GCS
    2. Ouvrir les buckets source et cible
    3. Parcourir les objets source à copier
    4. Construire le chemin destination landing
    5. Copier avec rewrite()

    RETOUR
    ---------------------------------------------------------------------------
    Aucun. Affiche simplement les logs de progression.
    """
    print_header("COPIE ARCO ERA5 -> LANDING")

    # -------------------------------------------------------------------------
    # 1) Création du client GCS
    # -------------------------------------------------------------------------
    # Ce client utilise tes credentials locaux ou ceux du runtime GCP.
    client = storage.Client(project=PROJECT_ID)

    # -------------------------------------------------------------------------
    # 2) Références de bucket
    # -------------------------------------------------------------------------
    # bucket() crée une référence logique au bucket, sans forcément faire
    # tout de suite un appel réseau.
    source_bucket = client.bucket(SOURCE_BUCKET_NAME)
    target_bucket = client.bucket(TARGET_BUCKET_NAME)

    # -------------------------------------------------------------------------
    # 3) Boucle sur la liste des objets source
    # -------------------------------------------------------------------------
    # SOURCE_OBJECTS est une liste de chemins GCS internes au bucket source.
    #
    # Exemple :
    # "raw/ERA5GRIB/HRES/Daily/1940/19400101_hres_dve.grb2"
    #
    # On va itérer objet par objet pour faire une copie contrôlée.
    for source_object in SOURCE_OBJECTS:

        # ---------------------------------------------------------------------
        # 3.1) Extraire le nom final du fichier
        # ---------------------------------------------------------------------
        # split("/") découpe le chemin par segments
        # [-1] récupère le dernier segment
        #
        # Exemple :
        # raw/.../19400101_hres_dve.grb2
        # devient :
        # 19400101_hres_dve.grb2
        filename = source_object.split("/")[-1]

        # ---------------------------------------------------------------------
        # 3.2) Construire le chemin cible dans landing
        # ---------------------------------------------------------------------
        # Exemple :
        # domain=weather/dataset=arco_era5/landing/19400101_hres_dve.grb2
        target_object = f"{LANDING_PREFIX}{filename}"

        print(
            f"Copy gs://{SOURCE_BUCKET_NAME}/{source_object} "
            f"-> gs://{TARGET_BUCKET_NAME}/{target_object}"
        )

        # ---------------------------------------------------------------------
        # 3.3) Références source et destination
        # ---------------------------------------------------------------------
        source_blob = source_bucket.blob(source_object)
        destination_blob = target_bucket.blob(target_object)

        # ---------------------------------------------------------------------
        # 3.4) Copie robuste via rewrite
        # ---------------------------------------------------------------------
        rewrite_blob(source_blob, destination_blob)

        print("    ✅ Copie terminée")

    print("✅ Copie vers landing terminée pour tout l'échantillon")


# =============================================================================
# POINT D'ENTRÉE
# =============================================================================
if __name__ == "__main__":
    copy_sample_to_landing()