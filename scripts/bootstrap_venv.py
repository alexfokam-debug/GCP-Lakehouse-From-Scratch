#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
scripts/bootstrap_venv.py
========================

Objectif (enterprise)
---------------------
Assurer que le repo Lakehouse a toujours un environnement Python cohérent.

Pourquoi ?
- Tu as eu le cas classique : pip installé dans un autre venv (FootPrediction)
- => ton script import yaml échoue dans le venv du repo Lakehouse

Ce script :
1) Vérifie que le python utilisé est bien celui du repo (optionnel)
2) Installe / met à jour les dépendances depuis requirements.txt
3) Vérifie que les imports clés fonctionnent (yaml)

Usage :
  python scripts/bootstrap_venv.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REQ_FILE = REPO_ROOT / "requirements.txt"


def run(cmd: list[str]) -> None:
    print(f"[RUN] {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, check=True)


def main() -> int:
    print("============================================================")
    print(" Python Env Bootstrap (Lakehouse repo)")
    print("============================================================")
    print(f"Python executable : {sys.executable}")
    print(f"Repo root         : {REPO_ROOT}")
    print("------------------------------------------------------------")

    # 1) requirements.txt obligatoire en entreprise (source-of-truth dépendances)
    if not REQ_FILE.exists():
        print(f"❌ Missing {REQ_FILE}. Create it (see below).")
        return 1

    # 2) Upgrade pip (propre sur CI / Mac)
    run([sys.executable, "-m", "pip", "install", "--upgrade", "pip"])

    # 3) Install deps
    run([sys.executable, "-m", "pip", "install", "-r", str(REQ_FILE)])

    # 4) Smoke test import (évite les surprises)
    run([sys.executable, "-c", "import yaml; print('PyYAML OK:', yaml.__version__)"])

    print("✅ Python environment ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())