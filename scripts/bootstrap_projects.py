#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
scripts/bootstrap_projects.py
============================

BOOTSTRAP MULTI-PROJET GCP (Enterprise)
--------------------------------------

But :
- Créer / vérifier les projets GCP (dev / staging / prod)
- Lier la facturation
- Activer les APIs nécessaires
- (Optionnel) Appliquer des labels projet en "best effort" (ne bloque jamais)

Principes "grand groupe" :
1) NON-INTERACTIF :
   - aucun prompt ne doit bloquer (gcloud peut attendre un input silencieusement)
   - => CLOUDSDK_CORE_DISABLE_PROMPTS=1 + --quiet

2) IDÉMPOTENT :
   - relancer 20 fois => "SKIP" si déjà OK
   - créer seulement si absent, activer seulement si manquant

3) ROBUSTE :
   - timeouts partout (sinon un appel réseau peut "freeze")
   - erreurs non critiques => WARN + continue (ex: labels)

4) SOURCE OF TRUTH = YAML :
   - configs/projects.yaml

Usage :
  python scripts/bootstrap_projects.py --config configs/projects.yaml --confirm YES

Exécution via Makefile :
  make bootstrap-projects CONFIRM=YES
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# PyYAML (à installer dans le venv du repo)
#   python -m pip install PyYAML
import yaml


# =============================================================================
# Logging minimaliste (pro & lisible)
# =============================================================================

def info(msg: str) -> None:
    print(msg, flush=True)


def step(msg: str) -> None:
    print(f"[STEP] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[WARN] {msg}", flush=True)


def fatal(msg: str) -> None:
    print(f"❌ {msg}", file=sys.stderr, flush=True)


# =============================================================================
# Modèles de données (normalisation YAML)
# =============================================================================

@dataclass(frozen=True)
class EnvProject:
    """
    Représente 1 environnement (dev/staging/prod) dans un format UNIQUE.
    Pourquoi ?
    - Ton YAML peut être "simple" (string) ou "riche" (dict).
    - Le code interne ne doit jamais gérer 2 formats.
    => On normalise tout en EnvProject.
    """
    env_name: str           # clé YAML : dev | staging | prod
    project_id: str         # ex : lakehouse-dev-486419
    environment_label: str  # ex : dev | stg | prd (utile pour labels / naming)


@dataclass
class CmdResult:
    """
    Résultat d'exécution d'une commande système.
    On encapsule returncode/stdout/stderr pour logs & décisions.
    """
    returncode: int
    stdout: str
    stderr: str


# =============================================================================
# Exécution de commandes (ENTERPRISE : non-interactif + timeout)
# =============================================================================

def run_cmd(
    cmd: List[str],
    *,
    capture: bool = True,
    check: bool = True,
    timeout_s: int = 120,
) -> CmdResult:
    """
    Exécute une commande de manière robuste.

    Points critiques :
    - CLOUDSDK_CORE_DISABLE_PROMPTS=1 :
        Empêche gcloud d'ouvrir un prompt qui "freeze" le script.
    - timeout :
        Évite les blocages silencieux (réseau, auth, CLI qui attend).
    - capture_output :
        Permet d'afficher stderr proprement si besoin.
    - check :
        Si True -> raise si returncode != 0 (pour étapes critiques)
        Si False -> on renvoie le résultat (best effort).
    """
    # ---- Environnement "no prompt" pour gcloud ----
    env = os.environ.copy()
    env.setdefault("CLOUDSDK_CORE_DISABLE_PROMPTS", "1")

    # ---- Log de commande (pro) ----
    info(f"\n[RUN] {' '.join(cmd)}")

    try:
        p = subprocess.run(
            cmd,
            text=True,
            env=env,
            capture_output=capture,
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired as e:
        # Code 124 = convention "timeout"
        return CmdResult(
            returncode=124,
            stdout=(e.stdout or ""),
            stderr=f"TIMEOUT after {timeout_s}s: {' '.join(cmd)}",
        )

    if check and p.returncode != 0:
        raise RuntimeError(
            f"Command failed (exit={p.returncode}): {' '.join(cmd)}\n"
            f"STDERR:\n{p.stderr}"
        )

    return CmdResult(returncode=p.returncode, stdout=p.stdout, stderr=p.stderr)


# =============================================================================
# Lecture YAML + validation "Enterprise"
# =============================================================================

def _read_yaml_file(path: str | Path) -> Dict[str, Any]:
    """Lecture YAML robuste : fichier existe + YAML = dict."""
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Config YAML introuvable: {p.resolve()}")

    with p.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    if not isinstance(data, dict):
        raise ValueError(f"YAML invalide: doit être un mapping (dict). File={p}")
    return data


def _default_env_label(env_name: str) -> str:
    """Convention entreprise : staging->stg, prod->prd, dev->dev."""
    env = env_name.strip().lower()
    if env == "staging":
        return "stg"
    if env == "prod":
        return "prd"
    if env == "dev":
        return "dev"
    return env


def _parse_projects(projects_raw: Any) -> List[EnvProject]:
    """
    Supporte 2 formats YAML :

    A) SIMPLE :
      projects:
        dev: "lakehouse-dev-486419"

    B) RICHE :
      projects:
        dev:
          project_id: "lakehouse-dev-486419"
          environment_label: "dev"
    """
    if not isinstance(projects_raw, dict):
        raise ValueError("`projects` doit être un mapping: dev/staging/prod -> (string|object)")

    out: List[EnvProject] = []
    for env_name, value in projects_raw.items():
        if not isinstance(env_name, str) or not env_name.strip():
            raise ValueError("Clé d'environnement invalide (string non vide requise)")

        env_clean = env_name.strip().lower()

        # --- Format A : string ---
        if isinstance(value, str):
            project_id = value.strip()
            if not project_id:
                raise ValueError(f"projects.{env_name}: project_id vide")
            out.append(
                EnvProject(
                    env_name=env_clean,
                    project_id=project_id,
                    environment_label=_default_env_label(env_clean),
                )
            )
            continue

        # --- Format B : dict riche ---
        if isinstance(value, dict):
            project_id = value.get("project_id")
            environment_label = value.get("environment_label")

            if not isinstance(project_id, str) or not project_id.strip():
                raise ValueError(f"projects.{env_name}.project_id est obligatoire (string non vide)")

            if not isinstance(environment_label, str) or not environment_label.strip():
                environment_label = _default_env_label(env_clean)
            else:
                environment_label = environment_label.strip().lower()

            out.append(
                EnvProject(
                    env_name=env_clean,
                    project_id=project_id.strip(),
                    environment_label=environment_label,
                )
            )
            continue

        raise ValueError(f"projects.{env_name} doit être str ou dict, pas {type(value).__name__}")

    # Tri stable (propre pour logs)
    order = {"dev": 0, "staging": 1, "prod": 2}
    out.sort(key=lambda x: order.get(x.env_name, 99))
    return out


def load_bootstrap_config(config_path: str | Path) -> Tuple[str, List[EnvProject], Dict[str, str], List[str]]:
    """
    Charge configs/projects.yaml (source-of-truth).

    Retourne :
    - billing_account_id
    - env_projects (normalisé)
    - labels (optionnel)
    - apis (optionnel)
    """
    cfg = _read_yaml_file(config_path)

    # ---- billing_account_id ----
    billing = cfg.get("billing_account_id")
    if not isinstance(billing, str) or not billing.strip():
        raise ValueError("billing_account_id est obligatoire (string non vide)")
    if billing.strip() == "REPLACE-ME":
        raise ValueError("billing_account_id est encore 'REPLACE-ME' — mets le vrai ID")
    billing = billing.strip()

    # ---- projects ----
    projects_raw = cfg.get("projects")
    env_projects = _parse_projects(projects_raw)
    if not env_projects:
        raise ValueError("Aucun projet trouvé dans `projects:`")

    # ---- labels (optionnel) ----
    labels_raw = cfg.get("labels", {}) or {}
    if not isinstance(labels_raw, dict):
        raise ValueError("`labels` doit être un mapping (dict) si présent")

    labels: Dict[str, str] = {}
    for k, v in labels_raw.items():
        ks = str(k).strip()
        if not ks:
            continue
        labels[ks] = str(v).strip()

    # ---- apis (optionnel) ----
    default_apis = [
        "cloudresourcemanager.googleapis.com",
        "iam.googleapis.com",
        "compute.googleapis.com",
        "bigquery.googleapis.com",
        "dataproc.googleapis.com",
        "dataplex.googleapis.com",
        "dataform.googleapis.com",
        "secretmanager.googleapis.com",
    ]
    apis_raw = cfg.get("apis", default_apis) or default_apis
    if not isinstance(apis_raw, list) or not all(isinstance(x, str) for x in apis_raw):
        raise ValueError("`apis` doit être une liste de strings si présent")

    apis = [a.strip() for a in apis_raw if a.strip()]

    return billing, env_projects, labels, apis


# =============================================================================
# GCloud helpers : existence projet / billing / apis
# =============================================================================

def project_exists(project_id: str) -> bool:
    """
    Idempotence :
    - gcloud projects describe => returncode 0 => existe
    - sinon => n'existe pas
    """
    p = run_cmd(
        ["gcloud", "projects", "describe", project_id, "--format=json", "--quiet"],
        check=False,
        capture=True,
        timeout_s=60,
    )
    return p.returncode == 0


def create_project(project_id: str) -> None:
    """
    Création de projet (étape critique).
    Si ça échoue => on stop (car tout le reste dépend du projet).
    """
    step(f"Create project: {project_id}")
    run_cmd(
        ["gcloud", "projects", "create", project_id, "--quiet"],
        check=True,
        capture=True,
        timeout_s=180,
    )


def billing_is_linked(project_id: str) -> bool:
    """
    Vérifie si le billing est déjà lié.
    """
    p = run_cmd(
        ["gcloud", "billing", "projects", "describe", project_id, "--format=json", "--quiet"],
        check=False,
        capture=True,
        timeout_s=60,
    )
    if p.returncode != 0:
        return False

    try:
        data = json.loads(p.stdout or "{}")
    except json.JSONDecodeError:
        return False

    # Dans la réponse gcloud, billingEnabled = true si lié
    return bool(data.get("billingEnabled"))


def link_billing(project_id: str, billing_account_id: str) -> None:
    """
    Lie la facturation si nécessaire (étape critique).
    """
    step(f"Link billing: {project_id} -> {billing_account_id}")
    run_cmd(
        ["gcloud", "billing", "projects", "link", project_id, "--billing-account", billing_account_id, "--quiet"],
        check=True,
        capture=True,
        timeout_s=180,
    )


def list_enabled_services(project_id: str) -> List[str]:
    """
    Liste des APIs activées.
    On capture une liste de "config.name".
    """
    p = run_cmd(
        ["gcloud", "services", "list", "--enabled", "--project", project_id, "--format=value(config.name)", "--quiet"],
        check=False,
        capture=True,
        timeout_s=120,
    )
    if p.returncode != 0:
        # Si la commande échoue, on retourne [] (best effort)
        return []

    lines = [ln.strip() for ln in (p.stdout or "").splitlines() if ln.strip()]
    return lines


def enable_apis(project_id: str, apis: List[str]) -> None:
    """
    Active les APIs manquantes uniquement (idempotent).
    """
    step("Enable APIs")

    enabled = set(list_enabled_services(project_id))
    missing = [a for a in apis if a not in enabled]

    if not missing:
        info("[SKIP] All APIs already enabled ✅")
        return

    # Commande unique avec toutes les APIs manquantes (plus rapide & pro)
    run_cmd(
        ["gcloud", "services", "enable", *missing, "--project", project_id, "--quiet"],
        check=True,
        capture=True,
        timeout_s=600,  # peut être long selon le compte
    )
    info(f"[OK] Enabled APIs: {', '.join(missing)} ✅")


# =============================================================================
# Labels : BEST EFFORT + NON-INTERACTIF + TIMEOUT
# =============================================================================

def set_project_labels_best_effort(project_id: str, labels: Dict[str, str], env_label: str) -> None:
    """
    Applique des labels au projet (best effort).

    IMPORTANT :
    - Les labels sont utiles (FinOps, gouvernance) MAIS ne doivent PAS bloquer.
    - Certaines versions de gcloud n'ont pas --update-labels sur le track stable.
      => On essaie plusieurs tracks (standard, beta, alpha).
    - On force le mode non interactif (--quiet + disable prompts) + timeout.
    """
    if not labels:
        info("[SKIP] No labels configured (optional).")
        return

    step("Set project labels (optional)")

    # Injecter/forcer environment=... si absent (pro, utile pour filtres)
    merged = dict(labels)
    merged.setdefault("environment", env_label)

    # gcloud attend des "k=v" séparés par virgules
    labels_csv = ",".join(f"{k}={v}" for k, v in merged.items())

    # On teste plusieurs tracks "proprement"
    candidates = [
        (
            "standard",
            ["gcloud", "projects", "update", project_id, f"--update-labels={labels_csv}", "--quiet", "--format=json"],
        ),
        (
            "beta",
            ["gcloud", "beta", "projects", "update", project_id, f"--update-labels={labels_csv}", "--quiet", "--format=json"],
        ),
        (
            "alpha",
            ["gcloud", "alpha", "projects", "update", project_id, f"--update-labels={labels_csv}", "--quiet", "--format=json"],
        ),
    ]

    last_errs: List[str] = []

    for track, cmd in candidates:
        info(f"[RUN] ({track}) {' '.join(cmd)}")
        p = run_cmd(cmd, check=False, capture=True, timeout_s=120)

        if p.returncode == 0:
            info(f"[OK] Labels applied via {track} ✅")
            return

        # On mémorise l'erreur pour la sortir en WARN (utile debug)
        if p.stderr:
            last_errs.append(f"{track}: {p.stderr.strip()}")
        elif p.stdout:
            last_errs.append(f"{track}: {p.stdout.strip()}")
        else:
            last_errs.append(f"{track}: exit={p.returncode}")

    # Si on est ici => aucun track n'a fonctionné, mais c'est NON BLOQUANT.
    warn("Unable to set project labels (continuing).")
    for e in last_errs[:3]:
        warn(e)


# =============================================================================
# Bootstrap d'un environnement
# =============================================================================

def bootstrap_env(envp: EnvProject, billing_account_id: str, apis: List[str], labels: Dict[str, str]) -> None:
    """
    Exécute toutes les étapes pour 1 environnement.
    Ordre pro :
    1) projet existe ? sinon create
    2) billing lié ? sinon link
    3) enable apis
    4) labels best effort
    """
    info(f"\n==================== {envp.env_name.upper()} ====================")
    info(f"[INFO] project_id = {envp.project_id}")

    # 1) Project
    if project_exists(envp.project_id):
        info("[SKIP] Project already exists ✅")
    else:
        create_project(envp.project_id)
        info("[OK] Project created ✅")

    # 2) Billing
    if billing_is_linked(envp.project_id):
        info("[SKIP] Billing already linked ✅")
    else:
        link_billing(envp.project_id, billing_account_id)
        info("[OK] Billing linked ✅")

    # 3) APIs
    enable_apis(envp.project_id, apis)

    # 4) Labels (best effort)
    set_project_labels_best_effort(envp.project_id, labels, envp.environment_label)

    info(f"[OK] {envp.env_name} bootstrap done ✅")


# =============================================================================
# CLI
# =============================================================================

def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Enterprise multi-project bootstrap for GCP.")
    parser.add_argument("--config", required=True, help="Path to YAML config (ex: configs/projects.yaml)")
    parser.add_argument("--confirm", default="NO", help="Must be YES to run destructive/creating actions")
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)

    if str(args.confirm).strip().upper() != "YES":
        fatal("Aborted: you must pass --confirm YES (or via Makefile CONFIRM=YES).")
        return 2

    billing_account_id, env_projects, labels, apis = load_bootstrap_config(args.config)

    info("\n============================================================")
    info(" GCP Multi-project Bootstrap (Enterprise)")
    info("============================================================")
    info(f"Config file        : {args.config}")
    info(f"Billing Account ID : {billing_account_id}")
    for e in env_projects:
        info(f"{e.env_name.upper():<16} : {e.project_id} (env_label={e.environment_label})")
    info("============================================================\n")

    # Exécute dev -> staging -> prod
    for envp in env_projects:
        try:
            bootstrap_env(envp, billing_account_id, apis, labels)
        except Exception as ex:
            # En entreprise : on stop sur erreur critique
            # (évite de faire "moitié ok" sur envs)
            fatal(f"Bootstrap failed for {envp.env_name}: {ex}")
            return 1

    info("\n✅ Bootstrap completed for all environments.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())