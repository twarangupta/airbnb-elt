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


def data_sha256(table) -> str:
    """Fingerprint of a table's DATA (not of the Parquet bytes).

    Parquet writers do not always produce identical bytes for identical data,
    so change detection uses the rows themselves, serialised deterministically.
    """
    rows = json.dumps(table.to_pylist(), default=str, sort_keys=True)
    return hashlib.sha256(rows.encode("utf-8")).hexdigest()


def manifest_entry(mart: str, query: str, rows: int, columns: list[str], path: Path, data_hash: str) -> dict:
    return {
        "table": f"AIRBNB.GOLD.{mart.upper()}",
        "file": path.relative_to(REPO_ROOT).as_posix(),
        "rows": rows,
        "columns": columns,
        "bytes": path.stat().st_size,
        "sha256": sha256_of(path),
        "data_sha256": data_hash,
        "source_query": query,
    }


def unchanged(data_hashes: dict[str, str], manifest_path: Path) -> bool:
    """True if every mart's data fingerprint matches the existing manifest.

    Then nothing is written (no files, no new exported_at), so rerunning the
    pipeline with no new data changes nothing in the repo.
    """
    if not manifest_path.exists():
        return False
    old = json.loads(manifest_path.read_text(encoding="utf-8"))
    old_hashes = {t["table"]: t.get("data_sha256") for t in old.get("tables", [])}
    return old_hashes == data_hashes


def suspend_warehouse(cur, name: str = "AIRBNB_WH") -> None:
    """Suspend the warehouse; 'already suspended' is fine, not an error.

    Snowflake raises error 090064 ("Invalid state ... cannot be suspended") when
    the warehouse is already asleep, e.g. when every query was answered from
    the result cache without waking it.
    """
    from snowflake.connector.errors import ProgrammingError

    try:
        cur.execute(f"ALTER WAREHOUSE {name} SUSPEND")
    except ProgrammingError as exc:
        if exc.errno != 90064:
            raise


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
    tables = {}
    try:
        cur = conn.cursor()
        for mart, order_by in MARTS.items():
            query = source_query(mart, order_by)
            table = cur.execute(query).fetch_arrow_all()
            if table is None or table.num_rows > MAX_ROWS:
                print(f"{mart}: refusing to export ({0 if table is None else table.num_rows} rows)", file=sys.stderr)
                return 1
            tables[mart] = (query, table.rename_columns([c.lower() for c in table.column_names]))
        suspend_warehouse(cur)
    finally:
        conn.close()

    data_hashes = {f"AIRBNB.GOLD.{m.upper()}": data_sha256(t) for m, (_, t) in tables.items()}
    if unchanged(data_hashes, EXPORT_DIR / "manifest.json"):
        print("export: Gold data unchanged since the last export; no files written")
        return 0

    entries = []
    for mart, (query, table) in tables.items():
        path = EXPORT_DIR / f"{mart}.parquet"
        pq.write_table(table, path, compression="zstd")
        data_hash = data_hashes[f"AIRBNB.GOLD.{mart.upper()}"]
        entries.append(manifest_entry(mart, query, table.num_rows, table.column_names, path, data_hash))
        relative = path.relative_to(REPO_ROOT).as_posix()
        print(f"{mart}: {table.num_rows} rows -> {relative} ({path.stat().st_size:,} bytes)")

    manifest = {
        "exported_at": dt.datetime.now(dt.UTC).isoformat(timespec="seconds"),
        "attribution": ATTRIBUTION,
        "source": "Snowflake AIRBNB.GOLD (dbt Gold layer)",
        "tables": entries,
    }
    manifest_text = json.dumps(manifest, indent=2, default=str) + "\n"
    (EXPORT_DIR / "manifest.json").write_text(manifest_text, encoding="utf-8")
    total = sum(e["bytes"] for e in entries)
    print(f"manifest: exports/gold/manifest.json ({len(entries)} tables, {total:,} bytes in Parquet)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
