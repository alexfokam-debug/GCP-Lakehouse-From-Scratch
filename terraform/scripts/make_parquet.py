from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq


def build_sample_df() -> pd.DataFrame:
    # Dataset de démo (tu peux adapter ensuite à ton vrai schéma)
    now = datetime.now(timezone.utc)
    return pd.DataFrame(
        [
            {"id": 1, "name": "alex", "amount": 10.5, "event_ts": now},
            {"id": 2, "name": "lakehouse", "amount": 20.0, "event_ts": now},
        ]
    )


def write_parquet(df: pd.DataFrame, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)

    table = pa.Table.from_pandas(df, preserve_index=False)
    pq.write_table(table, out_path)

    print("✅ Parquet generated")
    print(f"   path: {out_path.resolve()}")
    print(f"   size: {out_path.stat().st_size} bytes")
    print(f"   rows: {len(df)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        default="data/sample.parquet",
        help="Output parquet path (relative to repo root if not absolute)",
    )
    args = parser.parse_args()

    # IMPORTANT: on écrit TOUJOURS depuis la racine repo,
    # donc on résout le chemin par rapport au CWD actuel.
    out_path = Path(args.out)

    print("ℹ️ Running make_parquet.py")
    print(f"   cwd: {Path.cwd().resolve()}")
    print(f"   out: {out_path}")

    df = build_sample_df()
    write_parquet(df, out_path)


if __name__ == "__main__":
    main()
