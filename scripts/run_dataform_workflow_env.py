# scripts/run_dataform_workflow_env.py
#!/usr/bin/env python3
"""
==========================================================
Dataform Workflow Runner (ENV aware) - ENTERPRISE MODE
==========================================================

But :
- Lancer un Dataform WorkflowConfig (wf-dev-on-demand / wf-prod-weekdays)
- De manière robuste en "enterprise mode" :
  - si la ReleaseConfig associée n'a pas encore de releaseCompilationResult
    -> on compile automatiquement et on patch la ReleaseConfig.

Pourquoi c'est important ?
- En entreprise / CI/CD, un workflow ne doit pas échouer juste parce que
  personne n'a "cliqué compile" dans l'UI Dataform.

----------------------------------------------------------
USAGE
----------------------------------------------------------
Depuis le Makefile (recommandé) :
  make dataform-run ENV=dev
  make dataform-run ENV=prod
  make dataform-run ENV=dev WORKFLOW=wf-prod-weekdays  # force

Ou en direct :
  python -m scripts.run_dataform_workflow_env --env dev --workflow wf-dev-on-demand

----------------------------------------------------------
PRÉ-REQUIS
----------------------------------------------------------
- Auth ADC (local) :
    gcloud auth application-default login
- Dépendances :
    pip install google-auth requests pyyaml

----------------------------------------------------------
NOTES
----------------------------------------------------------
- Le script lit ton fichier configs/env.<env>.yaml via scripts._env
- Il utilise l'API REST Dataform v1beta1
"""

from __future__ import annotations

import argparse
import json
import time
from datetime import datetime
from typing import Any, Dict, Optional, List

import requests
import google.auth
from google.auth.transport.requests import Request as GoogleAuthRequest

# Loader interne de ta conf ENV
from scripts._env import load_env_config, get_required

# -----------------------------
# Constantes API Dataform
# -----------------------------
DATAFORM_API = "https://dataform.googleapis.com/v1beta1"
DEFAULT_SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]

# États considérés terminaux (API Dataform)
TERMINAL_STATES = {"SUCCEEDED", "FAILED", "CANCELLED"}


# -----------------------------
# Logging helpers (enterprise friendly)
# -----------------------------
def log(msg: str) -> None:
    """Log simple timestampé (parfait pour CI)."""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")


def die(msg: str, code: int = 1) -> None:
    """Stop contrôlé avec code exit."""
    log(f"❌ {msg}")
    raise SystemExit(code)


# -----------------------------
# Auth : récupérer un token OAuth2 via ADC
# -----------------------------
def get_access_token() -> str:
    """
    Récupère un token OAuth2 via Application Default Credentials.
    - Local : gcloud auth application-default login
    - CI/CD : Workload Identity Federation / SA attachée au runner
    """
    creds, _ = google.auth.default(scopes=DEFAULT_SCOPES)
    if not creds.valid:
        creds.refresh(GoogleAuthRequest())
    return creds.token


def headers(token: str) -> Dict[str, str]:
    """Headers standard pour appels REST JSON."""
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


# -----------------------------
# HTTP REST wrappers
# -----------------------------
def http_get(url: str, token: str) -> Dict[str, Any]:
    r = requests.get(url, headers=headers(token), timeout=60)
    if r.status_code >= 300:
        raise RuntimeError(f"GET {url} -> {r.status_code} {r.text}")
    return r.json()


def http_post(url: str, token: str, body: Dict[str, Any]) -> Dict[str, Any]:
    r = requests.post(url, headers=headers(token), data=json.dumps(body), timeout=60)
    if r.status_code >= 300:
        raise RuntimeError(
            f"POST {url} -> {r.status_code}\n"
            f"Body: {json.dumps(body)}\n"
            f"Resp: {r.text}"
        )
    return r.json()


def http_patch(url: str, token: str, body: Dict[str, Any]) -> Dict[str, Any]:
    r = requests.patch(url, headers=headers(token), data=json.dumps(body), timeout=60)
    if r.status_code >= 300:
        raise RuntimeError(
            f"PATCH {url} -> {r.status_code}\n"
            f"Body: {json.dumps(body)}\n"
            f"Resp: {r.text}"
        )
    return r.json()


# -----------------------------
# Helpers Dataform : construire les paths canoniques
# -----------------------------
def repo_path(project: str, location: str, repo: str) -> str:
    """
    Path canonique repo :
      projects/{project}/locations/{location}/repositories/{repo}
    """
    return f"projects/{project}/locations/{location}/repositories/{repo}"


def workflow_config_path(project: str, location: str, repo: str, workflow: str) -> str:
    """
    Path canonique workflowConfig :
      projects/{project}/locations/{location}/repositories/{repo}/workflowConfigs/{workflow}
    """
    return f"{repo_path(project, location, repo)}/workflowConfigs/{workflow}"


# -----------------------------
# Dataform : GET workflow/release
# -----------------------------
def get_workflow_config(token: str, wf_path: str) -> Dict[str, Any]:
    url = f"{DATAFORM_API}/{wf_path}"
    log(f"ℹ️  GET WorkflowConfig: {url}")
    return http_get(url, token)


def get_release_config(token: str, rel_path: str) -> Dict[str, Any]:
    url = f"{DATAFORM_API}/{rel_path}"
    log(f"ℹ️  GET ReleaseConfig: {url}")
    return http_get(url, token)


# -----------------------------
# Dataform : compilation bootstrap (enterprise mode)
# -----------------------------
def create_compilation_result_for_release(
    token: str,
    project: str,
    location: str,
    repo: str,
    release_cfg: Dict[str, Any],
) -> str:
    """
    Crée une CompilationResult à partir du ReleaseConfig :
    - gitCommitish (souvent "main")
    - codeCompilationConfig (defaultDatabase/schema/location + vars)

    Retourne le champ 'name' de la compilationResult créée.
    """
    rel_name = release_cfg.get("name", "")
    git_commitish = release_cfg.get("gitCommitish")
    code_comp_cfg = release_cfg.get("codeCompilationConfig")

    if not git_commitish:
        die(f"ReleaseConfig {rel_name} ne contient pas gitCommitish (champ requis pour compiler).")

    if not isinstance(code_comp_cfg, dict):
        die(
            f"ReleaseConfig {rel_name} ne contient pas codeCompilationConfig (dict). "
            f"Impossible de compiler."
        )

    url = f"{DATAFORM_API}/{repo_path(project, location, repo)}/compilationResults"

    body = {
        "gitCommitish": git_commitish,
        "codeCompilationConfig": code_comp_cfg,
    }

    log("🚀 POST create CompilationResult")
    log(f"  url : {url}")
    log(f"  git : {git_commitish}")
    resp = http_post(url, token, body)

    comp_name = resp.get("name")
    if not comp_name:
        die("CompilationResult créée mais champ 'name' absent de la réponse.")
    log(f"✅ CompilationResult créée: {comp_name}")
    return comp_name


def patch_release_config_set_compilation(
    token: str,
    release_cfg_name: str,
    compilation_result_name: str,
) -> None:
    """
    Patch ReleaseConfig.releaseCompilationResult = <compilationResultName>
    """
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
# Dataform : workflow invocation + monitoring
# -----------------------------
def create_workflow_invocation(token: str, project: str, location: str, repo: str, wf_path: str) -> str:
    """
    Crée une WorkflowInvocation (exécution) pour un WorkflowConfig donné.
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
    url = f"{DATAFORM_API}/{inv_name}"
    return http_get(url, token)


def query_workflow_invocation(token: str, inv_name: str) -> Dict[str, Any]:
    """
    Endpoint :query permet d'obtenir workflowInvocationActions (utile si FAILED)
    """
    url = f"{DATAFORM_API}/{inv_name}:query"
    return http_get(url, token)


def print_failed_actions(token: str, inv_name: str) -> None:
    """
    En cas d'échec, on affiche les actions FAILED avec failureReason.
    C'est exactement ce que tu faisais avec curl+jq, mais intégré au runner.
    """
    try:
        payload = query_workflow_invocation(token, inv_name)
    except Exception as e:
        log(f"⚠️  Impossible de query les erreurs d'actions: {e}")
        return

    actions: List[Dict[str, Any]] = payload.get("workflowInvocationActions") or []
    failed = [a for a in actions if a.get("state") == "FAILED"]

    if not failed:
        log("ℹ️  Aucune action FAILED détaillée trouvée via :query.")
        return

    log("----- FAILED ACTIONS (Dataform) -----")
    for a in failed:
        target = a.get("target", {})
        db = target.get("database")
        schema = target.get("schema")
        name = target.get("name")
        reason = a.get("failureReason")
        log(f"- {db}.{schema}.{name} -> {reason}")
    log("-------------------------------------")


def poll_until_done(token: str, inv_name: str, timeout_sec: int, poll_sec: int) -> None:
    start = time.time()

    while True:
        inv = get_workflow_invocation(token, inv_name)
        state = inv.get("state", "STATE_UNSPECIFIED")

        log(f"⏳ state={state}")

        # Si état terminal
        if state in TERMINAL_STATES:
            if state == "SUCCEEDED":
                log("✅ Workflow SUCCEEDED")
                return

            # Si FAILED/CANCELLED : on imprime un détail action-level
            print_failed_actions(token, inv_name)
            die(f"Workflow terminé en état {state}", code=3)

        if time.time() - start > timeout_sec:
            die(f"Timeout atteint ({timeout_sec}s) en attendant la fin du workflow.", code=4)

        time.sleep(poll_sec)


# -----------------------------
# CLI args
# -----------------------------
def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--env", required=True, choices=["dev", "staging", "prod"])

    # IMPORTANT : c'est ce que ton Makefile passe désormais
    p.add_argument(
        "--workflow",
        required=True,
        help="Nom du WorkflowConfig Dataform (ex: wf-dev-on-demand, wf-prod-weekdays).",
    )

    p.add_argument("--timeout-sec", type=int, default=1800)
    p.add_argument("--poll-sec", type=int, default=10)
    return p.parse_args()


def main() -> int:
    args = parse_args()

    # 1) Charger conf env.<env>.yaml
    cfg = load_env_config(args.env)

    # 2) Lire les champs nécessaires dans la conf
    project = get_required(cfg, "project_id")
    location = get_required(cfg, "location")
    repo = get_required(cfg, "dataform.repo")

    # 3) Construire le path canonique du workflow à exécuter
    wf_path = workflow_config_path(project, location, repo, args.workflow)

    print("==========================================")
    print("Dataform Workflow Runner (ENV aware) - ENTERPRISE")
    print("==========================================")
    print(f"ENV     : {args.env}")
    print(f"Project : {project}")
    print(f"Location: {location}")
    print(f"Repo    : {repo}")
    print(f"Workflow: {args.workflow}")
    print(f"Timeout : {args.timeout_sec}s | Poll: {args.poll_sec}s")
    print("")
    log(f"ℹ️  WorkflowConfig path: {wf_path}")

    # 4) Auth
    token = get_access_token()

    # 5) GET WorkflowConfig -> récupérer ReleaseConfig
    wf = get_workflow_config(token, wf_path)

    release_cfg_name = wf.get("releaseConfig")
    if not release_cfg_name:
        die("WorkflowConfig ne contient pas 'releaseConfig'. Vérifie ton workflow terraform.")

    log(f"ℹ️  ReleaseConfig liée: {release_cfg_name}")

    # 6) GET ReleaseConfig -> si pas compilée, bootstrap compilation
    rel = get_release_config(token, release_cfg_name)
    release_comp = rel.get("releaseCompilationResult")

    if not release_comp:
        log("⚠️  ReleaseConfig.releaseCompilationResult vide → bootstrap compilation...")
        comp_name = create_compilation_result_for_release(token, project, location, repo, rel)
        patch_release_config_set_compilation(token, release_cfg_name, comp_name)
    else:
        log(f"✅ ReleaseConfig déjà compilée: {release_comp}")

    # 7) Create invocation + poll
    inv_name = create_workflow_invocation(token, project, location, repo, wf_path)
    poll_until_done(token, inv_name, args.timeout_sec, args.poll_sec)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())