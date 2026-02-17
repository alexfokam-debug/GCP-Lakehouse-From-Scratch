# scripts/run_dataform_workflow_env.py
#!/usr/bin/env python3
"""
==========================================================
Dataform Workflow Runner (ENV aware) - ENTERPRISE MODE
==========================================================

Ce script exécute un WorkflowConfig Dataform de manière robuste.

Pourquoi "enterprise mode" ?
- Parce qu'en prod, un runner ne doit pas "échouer bêtement"
  si la ReleaseConfig associée au WorkflowConfig n'a pas encore de compilation result.
- L'erreur typique:
  FAILED_PRECONDITION: releaseCompilationResult non renseigné dans la ReleaseConfig.

Stratégie (robuste / idempotente) :
1) Charger config/env.yaml pour un ENV (dev/staging/prod)
2) Construire le nom du WorkflowConfig
3) GET WorkflowConfig → récupérer son ReleaseConfig
4) GET ReleaseConfig → vérifier releaseCompilationResult
   - si vide: créer une CompilationResult (POST) puis patcher la ReleaseConfig (PATCH)
5) Créer une WorkflowInvocation (POST /workflowInvocations) en pointant sur le WorkflowConfig
6) Poll jusqu'à terminal state (SUCCEEDED / FAILED / CANCELLED / ...)

Pré-requis (local) :
- gcloud auth application-default login
- python -m pip install google-auth requests pyyaml

Usage:
  python -m scripts.run_dataform_workflow_env --env dev --timeout-sec 1800 --poll-sec 10
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from typing import Any, Dict, Optional, Tuple

import requests
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account
import google.auth

# Import interne : ton loader ENV centralisé
from scripts._env import load_env_config, get_required

# -----------------------------
# Constantes API Dataform
# -----------------------------
DATAFORM_API = "https://dataform.googleapis.com/v1beta1"
# Scope standard pour appeler des APIs GCP via OAuth2
DEFAULT_SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]


# -----------------------------
# Helpers généraux (log)
# -----------------------------
def log(msg: str) -> None:
    """Log simple avec timestamp (utile en CI)."""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")


def die(msg: str, code: int = 1) -> None:
    """Sortie contrôlée."""
    log(f"❌ {msg}")
    raise SystemExit(code)


# -----------------------------
# Auth : récupérer un token OAuth2
# -----------------------------
def get_access_token() -> str:
    """
    Récupère un access token via Application Default Credentials (ADC).
    - En local: gcloud auth application-default login
    - En CI: Workload Identity / Service Account
    """
    creds, _ = google.auth.default(scopes=DEFAULT_SCOPES)
    # Si le token n'est pas (ou plus) valide → refresh
    if not creds.valid:
        creds.refresh(GoogleAuthRequest())
    return creds.token


def headers(token: str) -> Dict[str, str]:
    """Headers standard pour REST JSON."""
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


# -----------------------------
# HTTP REST wrappers (GET/POST/PATCH)
# -----------------------------
def http_get(url: str, token: str) -> Dict[str, Any]:
    """GET JSON avec gestion d'erreurs lisible."""
    r = requests.get(url, headers=headers(token), timeout=60)
    if r.status_code >= 300:
        raise RuntimeError(f"GET {url} -> {r.status_code} {r.text}")
    return r.json()


def http_post(url: str, token: str, body: Dict[str, Any]) -> Dict[str, Any]:
    """POST JSON avec gestion d'erreurs lisible."""
    r = requests.post(url, headers=headers(token), data=json.dumps(body), timeout=60)
    if r.status_code >= 300:
        raise RuntimeError(
            f"POST {url} -> {r.status_code}\n"
            f"Body: {json.dumps(body)}\n"
            f"Resp: {r.text}"
        )
    return r.json()


def http_patch(url: str, token: str, body: Dict[str, Any]) -> Dict[str, Any]:
    """PATCH JSON avec gestion d'erreurs lisible."""
    r = requests.patch(url, headers=headers(token), data=json.dumps(body), timeout=60)
    if r.status_code >= 300:
        raise RuntimeError(
            f"PATCH {url} -> {r.status_code}\n"
            f"Body: {json.dumps(body)}\n"
            f"Resp: {r.text}"
        )
    return r.json()


# -----------------------------
# Dataform : construire les noms de ressources
# -----------------------------
def repo_path(project: str, location: str, repo: str) -> str:
    """
    Nom canonique repo :
    projects/{project}/locations/{location}/repositories/{repo}
    """
    return f"projects/{project}/locations/{location}/repositories/{repo}"


def workflow_config_path(project: str, location: str, repo: str, workflow: str) -> str:
    """
    Nom canonique workflowConfig :
    projects/{project}/locations/{location}/repositories/{repo}/workflowConfigs/{workflow}
    """
    return f"{repo_path(project, location, repo)}/workflowConfigs/{workflow}"


# -----------------------------
# Dataform : GET WorkflowConfig + ReleaseConfig
# -----------------------------
def get_workflow_config(token: str, wf_path: str) -> Dict[str, Any]:
    """
    Récupère le WorkflowConfig.
    Important: la plupart des erreurs de "mauvais path" viennent d'ici.
    """
    url = f"{DATAFORM_API}/{wf_path}"
    log(f"ℹ️  GET WorkflowConfig: {url}")
    return http_get(url, token)


def get_release_config(token: str, rel_path: str) -> Dict[str, Any]:
    """
    Récupère le ReleaseConfig (pointé par le workflowConfig.releaseConfig).
    """
    url = f"{DATAFORM_API}/{rel_path}"
    log(f"ℹ️  GET ReleaseConfig: {url}")
    return http_get(url, token)


# -----------------------------
# Dataform : créer CompilationResult + patch ReleaseConfig
# -----------------------------
def create_compilation_result_for_release(
    token: str,
    project: str,
    location: str,
    repo: str,
    release_cfg: Dict[str, Any],
) -> str:
    """
    Crée une CompilationResult en utilisant :
    - gitCommitish provenant du ReleaseConfig (souvent "main")
    - codeCompilationConfig provenant du ReleaseConfig (defaultDatabase/schema/location, etc.)

    Ensuite retourne le "name" de la CompilationResult créée
    (ex: projects/.../repositories/.../compilationResults/XYZ)
    """
    rel_name = release_cfg.get("name", "")
    git_commitish = release_cfg.get("gitCommitish")
    code_comp_cfg = release_cfg.get("codeCompilationConfig")

    if not git_commitish:
        die(f"ReleaseConfig {rel_name} ne contient pas gitCommitish (champ requis pour compiler).")

    if not isinstance(code_comp_cfg, dict):
        die(
            f"ReleaseConfig {rel_name} ne contient pas codeCompilationConfig (dict). "
            f"Impossible de compiler proprement."
        )

    # Endpoint create compilationResults :
    # POST .../repositories/{repo}/compilationResults  [oai_citation:3‡Google Cloud Documentation](https://docs.cloud.google.com/dataform/reference/rest/v1/projects.locations.repositories.compilationResults)
    url = f"{DATAFORM_API}/{repo_path(project, location, repo)}/compilationResults"

    body = {
        # Source code à compiler
        "gitCommitish": git_commitish,
        # Paramètres de compilation (très important en entreprise)
        "codeCompilationConfig": code_comp_cfg,
    }

    log("🚀 POST create CompilationResult")
    log(f"  url : {url}")
    log(f"  git : {git_commitish}")
    resp = http_post(url, token, body)

    comp_name = resp.get("name")
    if not comp_name:
        die("CompilationResult créée mais champ 'name' introuvable dans la réponse.")

    log(f"✅ CompilationResult créée: {comp_name}")
    return comp_name


def patch_release_config_set_compilation(
    token: str,
    release_cfg_name: str,
    compilation_result_name: str,
) -> None:
    """
    Patch ReleaseConfig.releaseCompilationResult = compilation_result_name.

    Le champ existe bien dans ReleaseConfig  [oai_citation:4‡Google Cloud Documentation](https://docs.cloud.google.com/nodejs/docs/reference/dataform/latest/dataform/protos.google.cloud.dataform.v1beta1.releaseconfig-class?utm_source=chatgpt.com)
    et on patch via releaseConfigs.patch  [oai_citation:5‡Google Cloud Documentation](https://docs.cloud.google.com/dataform/reference/rest/v1beta1/projects.locations.repositories.releaseConfigs/patch)
    """
    # PATCH endpoint:
    # PATCH https://dataform.googleapis.com/v1beta1/{releaseConfigName}?updateMask=releaseCompilationResult
    url = f"{DATAFORM_API}/{release_cfg_name}?updateMask=releaseCompilationResult"

    body = {
        "name": release_cfg_name,
        "releaseCompilationResult": compilation_result_name,
    }

    log("🧩 PATCH ReleaseConfig.releaseCompilationResult")
    log(f"  url : {url}")
    log(f"  comp: {compilation_result_name}")
    http_patch(url, token, body)
    log("✅ ReleaseConfig patchée.")


# -----------------------------
# Dataform : créer WorkflowInvocation + poll status
# -----------------------------
def create_workflow_invocation(token: str, project: str, location: str, repo: str, wf_path: str) -> str:
    """
    Crée une WorkflowInvocation en pointant sur le WorkflowConfig.

    Endpoint:
      POST .../repositories/{repo}/workflowInvocations  [oai_citation:6‡Google Cloud Documentation](https://docs.cloud.google.com/dataform/reference/rest/v1beta1/projects.locations.repositories.workflowInvocations)
    Body:
      {"workflowConfig": "<full workflow config name>"}
    """
    url = f"{DATAFORM_API}/{repo_path(project, location, repo)}/workflowInvocations"
    body = {"workflowConfig": wf_path}

    log("🚀 POST create WorkflowInvocation")
    log(f"  url : {url}")
    log(f"  body: {body}")
    resp = http_post(url, token, body)

    inv_name = resp.get("name")
    if not inv_name:
        die("WorkflowInvocation créée mais champ 'name' absent de la réponse.")
    log(f"✅ WorkflowInvocation créée: {inv_name}")
    return inv_name


def get_workflow_invocation(token: str, inv_name: str) -> Dict[str, Any]:
    """GET l'invocation pour lire son state."""
    url = f"{DATAFORM_API}/{inv_name}"
    return http_get(url, token)


def poll_until_done(
    token: str,
    inv_name: str,
    timeout_sec: int,
    poll_sec: int,
) -> None:
    """
    Poll l'invocation jusqu'à un état terminal.
    On reste volontairement "simple" (pas de threads).
    """
    start = time.time()

    while True:
        inv = get_workflow_invocation(token, inv_name)
        state = inv.get("state", "STATE_UNSPECIFIED")

        log(f"⏳ state={state}")

        # États terminaux usuels (selon API/versions)
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            if state == "SUCCEEDED":
                log("✅ Workflow SUCCEEDED")
                return
            die(f"Workflow terminé en état {state}", code=3)

        if time.time() - start > timeout_sec:
            die(f"Timeout atteint ({timeout_sec}s) en attendant la fin du workflow.", code=4)

        time.sleep(poll_sec)


# -----------------------------
# Main
# -----------------------------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--env", required=True, choices=["dev", "staging", "prod"])
    p.add_argument("--timeout-sec", type=int, default=1800)
    p.add_argument("--poll-sec", type=int, default=10)
    return p.parse_args()


def main() -> int:
    args = parse_args()

    # 1) Charger env.yaml
    cfg = load_env_config(args.env)

    # 2) Extraire champs requis (convention: clés en dotted path)
    project = get_required(cfg, "project_id")
    location = get_required(cfg, "location")
    repo = get_required(cfg, "dataform.repo")
    workflow = get_required(cfg, "dataform.workflow")

    wf_path = workflow_config_path(project, location, repo, workflow)

    print("==========================================")
    print("Dataform Workflow Runner (ENV aware) - ENTERPRISE")
    print("==========================================")
    print(f"ENV     : {args.env}")
    print(f"Project : {project}")
    print(f"Location: {location}")
    print(f"Repo    : {repo}")
    print(f"Workflow: {workflow}")
    print(f"Timeout : {args.timeout_sec}s | Poll: {args.poll_sec}s")
    print("")
    log(f"ℹ️  WorkflowConfig path: {wf_path}")

    # 3) Auth
    token = get_access_token()

    # 4) GET WorkflowConfig → trouver ReleaseConfig
    wf = get_workflow_config(token, wf_path)

    # IMPORTANT: WorkflowConfig contient un champ "releaseConfig" (nom complet)
    # Exemple: projects/.../releaseConfigs/release-prod
    release_cfg_name = wf.get("releaseConfig")
    if not release_cfg_name:
        die(
            "WorkflowConfig ne contient pas de champ 'releaseConfig'. "
            "Vérifie que ton workflowConfig a bien été créé avec une release config."
        )

    log(f"ℹ️  ReleaseConfig liée: {release_cfg_name}")

    # 5) GET ReleaseConfig → vérifier releaseCompilationResult
    rel = get_release_config(token, release_cfg_name)
    release_comp = rel.get("releaseCompilationResult")

    if not release_comp:
        log("⚠️  ReleaseConfig.releaseCompilationResult est vide → bootstrap compilation...")
        comp_name = create_compilation_result_for_release(token, project, location, repo, rel)
        patch_release_config_set_compilation(token, release_cfg_name, comp_name)
    else:
        log(f"✅ ReleaseConfig déjà compilée: {release_comp}")

    # 6) Créer invocation + poll
    inv_name = create_workflow_invocation(token, project, location, repo, wf_path)
    poll_until_done(token, inv_name, args.timeout_sec, args.poll_sec)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())