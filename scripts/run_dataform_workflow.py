#!/usr/bin/env python3
"""
Exécution d'un workflow Dataform en "mode entreprise" :
- On ne passe pas repo/workflow en dur
- On les lit depuis configs/env.<env>.yaml
- On lance le workflow et on "poll" jusqu'au succès/échec

Usage:
  python scripts/run_dataform_workflow_env.py --env dev
  python scripts/run_dataform_workflow_env.py --env staging
  python scripts/run_dataform_workflow_env.py --env prod

Pré-requis:
  pip install pyyaml google-cloud-dataform
  gcloud auth application-default login
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path
from typing import Any, Dict

import yaml
from google.cloud import dataform_v1beta1


# --------------------------------------------------------------------
# Helpers de config
# --------------------------------------------------------------------
def load_env_config(env: str) -> Dict[str, Any]:
    """
    Charge configs/env.<env>.yaml

    Pourquoi:
      - En entreprise, le code ne change pas entre DEV/STG/PROD.
      - Seule la config d'environnement change.
    """
    cfg_path = Path("configs") / f"env.{env}.yaml"
    if not cfg_path.exists():
        raise FileNotFoundError(f"Config introuvable: {cfg_path}")

    with cfg_path.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}

    # Petites validations "friendly"
    if "gcp" not in cfg or "project_id" not in cfg["gcp"] or "region" not in cfg["gcp"]:
        raise ValueError(
            "Config invalide: attendu gcp.project_id et gcp.region "
            f"dans {cfg_path}"
        )

    if "dataform" not in cfg or "repo" not in cfg["dataform"] or "workflow" not in cfg["dataform"]:
        raise ValueError(
            "Config invalide: attendu dataform.repo et dataform.workflow "
            f"dans {cfg_path}"
        )

    return cfg


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run Dataform workflow from env config.")
    p.add_argument("--env", required=True, choices=["dev", "staging", "prod"], help="Environnement cible")
    p.add_argument("--timeout-sec", type=int, default=1800, help="Timeout global (secondes)")
    p.add_argument("--poll-sec", type=int, default=10, help="Fréquence de polling (secondes)")
    return p.parse_args()


# --------------------------------------------------------------------
# Main "run workflow"
# --------------------------------------------------------------------
def main() -> int:
    args = parse_args()
    cfg = load_env_config(args.env)

    project = cfg["gcp"]["project_id"]
    region = cfg["gcp"]["region"]
    repo = cfg["dataform"]["repo"]
    workflow = cfg["dataform"]["workflow"]

    # Clients Dataform (API)
    client = dataform_v1beta1.DataformClient()

    # ----------------------------------------------------------------
    # 1) Construire le nom complet des ressources (format Google)
    # ----------------------------------------------------------------
    # Repo: projects/<project>/locations/<region>/repositories/<repo>
    repository = f"projects/{project}/locations/{region}/repositories/{repo}"

    # WorkflowConfig: .../workflowConfigs/<workflow>
    workflow_config = f"{repository}/workflowConfigs/{workflow}"

    print("==========================================")
    print("Dataform Workflow Runner (env-config)")
    print("==========================================")
    print(f"ENV      : {args.env}")
    print(f"Project  : {project}")
    print(f"Region   : {region}")
    print(f"Repo     : {repo}")
    print(f"Workflow : {workflow}")
    print("")

    # ----------------------------------------------------------------
    # 2) Déclencher une exécution
    # ----------------------------------------------------------------
    # Dataform crée un "workflow invocation" à partir du workflow config
    invocation = dataform_v1beta1.WorkflowInvocation(
        workflow_config=workflow_config
    )

    created = client.create_workflow_invocation(
        parent=repository,
        workflow_invocation=invocation,
    )

    invocation_name = created.name
    print(f"✅ Invocation créée : {invocation_name}")

    # ----------------------------------------------------------------
    # 3) Polling: on attend la fin (SUCCEEDED / FAILED / CANCELLED)
    # ----------------------------------------------------------------
    deadline = time.time() + args.timeout_sec

    while True:
        if time.time() > deadline:
            raise TimeoutError(
                f"Timeout dépassé ({args.timeout_sec}s) en attendant {invocation_name}"
            )

        inv = client.get_workflow_invocation(name=invocation_name)

        # Les states peuvent évoluer selon la version d'API, mais l'idée est:
        # - RUNNING / SUCCEEDED / FAILED / CANCELLED
        state = dataform_v1beta1.WorkflowInvocation.State(inv.state).name

        print(f"⏳ State={state} ...")
        if state in {"SUCCEEDED"}:
            print("✅ Workflow terminé avec succès.")
            return 0
        if state in {"FAILED", "CANCELLED"}:
            print("❌ Workflow en échec ou annulé.")
            print(f"Details: {inv}")
            return 2

        time.sleep(args.poll_sec)


if __name__ == "__main__":
    raise SystemExit(main())