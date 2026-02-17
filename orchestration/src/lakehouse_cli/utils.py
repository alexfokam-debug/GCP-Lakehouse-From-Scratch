from __future__ import annotations

from pathlib import Path
from typing import Iterable
from typing import Iterable
import logging
import shlex
import subprocess

REPO_MARKERS = (
    ".git",
    "terraform",
    "configs",
    "jobs",
)


def find_repo_root(start: Path | None = None, markers: Iterable[str] = REPO_MARKERS) -> Path:
    """
    Trouve la racine du repository à partir du répertoire courant (ou `start`).

    Pourquoi c'est important en entreprise ?
    - On veut lancer le CLI depuis n'importe quel dossier (orchestration/, terraform/, etc.)
    - Les chemins dans les configs restent stables : configs/..., jobs/...

    Stratégie :
    - On remonte les parents jusqu'à trouver au moins 1 marqueur de repo.
    - Si on ne trouve rien, on fallback sur le dossier courant.
    """
    start = (start or Path.cwd()).resolve()

    for p in [start, *start.parents]:
        if any((p / m).exists() for m in markers):
            return p

    # fallback : pas de marqueur détecté
    return start


def resolve_from_repo_root(path: Path, repo_root: Path) -> Path:
    """
    Résout un path:
    - si absolu -> inchangé
    - si relatif -> interprété comme relatif à la racine du repo

    Exemple :
    - "configs/env.dev.yaml" devient "<repo>/configs/env.dev.yaml"
    """
    if path.is_absolute():
        return path.resolve()
    return (repo_root / path).resolve()


def must_exist(file_path: Path, what: str = "file") -> None:
    """
    Validation explicite (fail-fast) : en entreprise on préfère
    échouer vite avec un message clair plutôt que laisser l'erreur
    se propager plus tard.
    """
    if not file_path.exists():
        raise FileNotFoundError(f"{what.capitalize()} introuvable: {file_path}")


def run_cmd(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """
    Wrapper subprocess standard "enterprise":
    - log la commande
    - check=True => lève une exception si exit != 0
    """
    printable = " ".join(shlex.quote(x) for x in cmd)
    logging.log.info("RUN: %s", printable)
    return subprocess.run(cmd, check=check, text=True)