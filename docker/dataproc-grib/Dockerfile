# =============================================================================
# Dockerfile - Custom container Dataproc Serverless pour lecture GRIB2
# -----------------------------------------------------------------------------
# BASE
# La doc officielle Dataproc Serverless recommande Debian 12 pour éviter
# les problèmes de compatibilité.
# =============================================================================

FROM debian:12-slim

# =============================================================================
# 1) Variables d'environnement de base
# -----------------------------------------------------------------------------
# DEBIAN_FRONTEND=noninteractive :
# - évite les prompts interactifs pendant apt install
# =============================================================================
ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# 2) Paquets système requis par Dataproc Serverless
# -----------------------------------------------------------------------------
# La doc officielle impose :
# - procps
# - tini
#
# On ajoute aussi :
# - libjemalloc2 : recommandé dans l'exemple officiel
# - python3 / python3-pip / python3-venv : pour environnement Python
# - libeccodes-dev / python3-dev / build-essential : nécessaires pour GRIB2
# =============================================================================
RUN apt-get update && apt-get install -y \
    procps \
    tini \
    libjemalloc2 \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    gcc \
    g++ \
    libeccodes-dev \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# 3) Activer jemalloc comme allocateur mémoire par défaut
# -----------------------------------------------------------------------------
# Repris de l'exemple officiel Dataproc Serverless.
# =============================================================================
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

# =============================================================================
# 4) Créer l'utilisateur spark
# -----------------------------------------------------------------------------
# La doc officielle Dataproc Serverless dit que les conteneurs sont exécutés
# avec l'utilisateur Linux "spark", UID=1099 et GID=1099.
# On crée donc explicitement cet utilisateur/groupe.
# =============================================================================
RUN groupadd -g 1099 spark && \
    useradd -u 1099 -g 1099 -d /home/spark -m spark

# =============================================================================
# 5) Préparer un environnement Python custom
# -----------------------------------------------------------------------------
# La doc indique qu'on peut fournir son propre Python dans un autre dossier
# (ex: /opt/conda). Ici on choisit un venv simple dans /opt/pyenv.
# =============================================================================
RUN python3 -m venv /opt/pyenv

# Python principal du job PySpark dans ce conteneur
ENV PYSPARK_PYTHON=/opt/pyenv/bin/python
ENV PATH=/opt/pyenv/bin:${PATH}

# =============================================================================
# 6) Copier les dépendances Python
# =============================================================================
COPY requirements.txt /opt/requirements.txt

# =============================================================================
# 7) Installer les packages Python
# -----------------------------------------------------------------------------
# IMPORTANT :
# - On n'installe PAS pyspark (la doc dit de ne pas l'inclure)
# - Dataproc montera pyspark au runtime
# =============================================================================
RUN /opt/pyenv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel && \
    /opt/pyenv/bin/pip install --no-cache-dir -r /opt/requirements.txt

# =============================================================================
# 8) Vérifications minimales au build
# -----------------------------------------------------------------------------
# On échoue tôt si les dépendances critiques ne s'importent pas.
# =============================================================================
RUN /opt/pyenv/bin/python -c "import xarray; print('xarray OK')"
RUN /opt/pyenv/bin/python -c "import cfgrib; print('cfgrib OK')"
RUN /opt/pyenv/bin/python -c "import eccodes; print('eccodes OK')"

# =============================================================================
# 9) Revenir à l'utilisateur spark
# -----------------------------------------------------------------------------
# La directive USER sera ignorée au runtime selon la doc, mais la garder
# améliore la cohérence locale du conteneur.
# =============================================================================
USER spark