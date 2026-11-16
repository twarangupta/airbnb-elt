"""Export the small Gold marts to Parquet so results outlive the Snowflake trial.

    make export-gold

Writes exports/gold/<mart>.parquet (one file per mart) and
exports/gold/manifest.json (row counts, columns, file size, sha256, export
time, the exact source query, snapshot dates and the data attribution).
Only small, aggregated marts are exported: no review text, no host or
reviewer names, nothing large. The files are committed to the repo and read
by the public dashboard, which never needs warehouse credentials.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
EXPORT_DIR = REPO_ROOT / "exports" / "gold"
ATTRIBUTION = "Data: Inside Airbnb (CC BY 4.0), London snapshots 2026-06-19 and 2026-09-17"

# mart name -> ORDER BY, so every export is deterministic
MARTS = {
    "mart_city_kpis": "snapshot_date",
    "mart_neighbourhood_summary": "neighbourhood",
    "mart_reviews_monthly": "month_start_date",
    "mart_price_by_room_type": "snapshot_date, room_type",
    "mart_scd_changes": "entity_type, metric_name",
}

# Refuse to export a table bigger than this (the point is small files).
MAX_ROWS = 10_000


def source_query(mart: str, order_by: str) -> str:
    return f"SELECT * FROM AIRBNB.GOLD.{mart.upper()} ORDER BY {order_by}"


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest_entry(mart: str, query: str, rows: int, columns: list[str], path: Path) -> dict:
    return {
        "table": f"AIRBNB.GOLD.{mart.upper()}",
        "file": path.relative_to(REPO_ROOT).as_posix(),
        "rows": rows,
        "columns": columns,
        "bytes": path.stat().st_size,
        "sha256": sha256_of(path),
        "source_query": query,
    }


def main() -> int:
    import pyarrow.parquet as pq
    import snowflake.connector
    from dotenv import load_dotenv

    load_dotenv(REPO_ROOT / ".env", override=False)
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ.get("SNOWFLAKE_USER", "DBT_SVC"),
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        private_key_file_pwd=os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None,
        role=os.environ.get("SNOWFLAKE_ROLE", "TRANSFORMER"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "AIRBNB_WH"),
        session_parameters={"QUERY_TAG": "airbnb_elt_export"},
    )
    entries = []
    try:
        cur = conn.cursor()
        for mart, order_by in MARTS.items():
            query = source_query(mart, order_by)
            table = cur.execute(query).fetch_arrow_all()
            if table is None or table.num_rows > MAX_ROWS:
                print(f"{mart}: refusing to export ({0 if table is None else table.num_rows} rows)", file=sys.stderr)
                return 1
            table = table.rename_columns([c.lower() for c in table.column_names])
            path = EXPORT_DIR / f"{mart}.parquet"
            pq.write_table(table, path, compression="zstd")
            entries.append(manifest_entry(mart, query, table.num_rows, table.column_names, path))
            relative = path.relative_to(REPO_ROOT).as_posix()
            print(f"{mart}: {table.num_rows} rows -> {relative} ({path.stat().st_size:,} bytes)")
        cur.execute("ALTER WAREHOUSE AIRBNB_WH SUSPEND")
    finally:
        conn.close()

    manifest = {
        "exported_at": dt.datetime.now(dt.UTC).isoformat(timespec="seconds"),
        "attribution": ATTRIBUTION,
        "source": "Snowflake AIRBNB.GOLD (dbt Gold layer)",
        "tables": entries,
    }
    (EXPORT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2, default=str) + "\n", encoding="utf-8")
    total = sum(e["bytes"] for e in entries)
    print(f"manifest: exports/gold/manifest.json ({len(entries)} tables, {total:,} bytes in Parquet)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
