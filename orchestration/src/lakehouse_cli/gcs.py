from __future__ import annotations

from pathlib import Path

from .utils import run_cmd


def gsutil_cp(local_file: Path, gcs_uri: str) -> None:
    if not local_file.exists():
        raise FileNotFoundError(f"Local file not found: {local_file}")
    run_cmd(["gsutil", "cp", str(local_file), gcs_uri], check=True)