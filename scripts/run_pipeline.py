"""Run the whole pipeline in order, stopping at the first failure.

    make run-all                       # snapshots from the Makefile (old, new)
    python scripts/run_pipeline.py --snapshot-dates 2026-06-19 2026-09-17

Steps (every one is safe to rerun):
  1. land      each snapshot's files in S3      (skips files already in S3)
  2. load      each snapshot into RAW           (COPY INTO skips loaded files; counts reconciled)
  3. freshness dbt source freshness             (warns if RAW is old)
  4. silver    dbt build --select silver        (incremental models process only new RAW rows)
  5. snapshot  dbt snapshot per snapshot date   (ONLY dates newer than the history already
                                                 recorded, oldest first; older dates are skipped
                                                 so history can never be written backwards)
  6. gold      dbt build --select gold + no-review-lost test
  7. export    small Gold marts to Parquet      (files rewritten only if the DATA changed;
                                                 then suspends the warehouse)

A rerun with no new Inside Airbnb snapshot therefore adds nothing anywhere.
This is the orchestrator for a pipeline that gets new data about every three
months; see the README for how the same DAG would run in Airflow or dbt Cloud.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable
DBT = str(Path(sys.executable).with_name("dbt.exe" if os.name == "nt" else "dbt"))
DBT_FLAGS = ["--project-dir", "dbt", "--profiles-dir", "dbt"]


def snapshot_dates_to_run(requested: list[str], newest_recorded: dt.date | None) -> list[str]:
    """Dates to snapshot: oldest first, and only those newer than recorded history."""
    ordered = sorted(set(requested))
    if newest_recorded is None:
        return ordered
    return [d for d in ordered if dt.date.fromisoformat(d) > newest_recorded]


def newest_recorded_snapshot() -> dt.date | None:
    """Newest dbt_valid_from in the listings snapshot, or None if it does not exist yet."""
    import snowflake.connector

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ.get("SNOWFLAKE_USER", "DBT_SVC"),
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        private_key_file_pwd=os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None,
        role=os.environ.get("SNOWFLAKE_ROLE", "TRANSFORMER"),
        session_parameters={"QUERY_TAG": "airbnb_elt_run_all"},
    )
    try:
        cur = conn.cursor()
        exists = cur.execute(
            "SELECT COUNT(*) FROM AIRBNB.INFORMATION_SCHEMA.TABLES "
            "WHERE table_schema = 'SNAPSHOTS' AND table_name = 'SNAP_LISTINGS'"
        ).fetchone()[0]
        if not exists:
            return None
        value = cur.execute("SELECT MAX(dbt_valid_from) FROM AIRBNB.SNAPSHOTS.SNAP_LISTINGS").fetchone()[0]
        return value.date() if value else None
    finally:
        conn.close()


def run(label: str, command: list[str], timings: list[tuple[str, float, str]]) -> None:
    print(f"\n=== {label} ===\n$ {' '.join(command)}", flush=True)
    start = time.monotonic()
    result = subprocess.run(command, cwd=REPO_ROOT)
    seconds = time.monotonic() - start
    if result.returncode != 0:
        timings.append((label, seconds, f"FAILED (exit {result.returncode})"))
        print_summary(timings)
        print(f"\nStopped: '{label}' failed. Nothing after it ran.", file=sys.stderr)
        raise SystemExit(result.returncode)
    timings.append((label, seconds, "ok"))


def print_summary(timings: list[tuple[str, float, str]]) -> None:
    print("\nPipeline summary")
    for label, seconds, status in timings:
        print(f"  {label:<38} {seconds:7.1f} s  {status}")
    print(f"  {'total':<38} {sum(t[1] for t in timings):7.1f} s")


def main(argv: list[str] | None = None) -> int:
    sys.path.insert(0, str(REPO_ROOT / "ingestion"))
    from land_files import validate_date

    parser = argparse.ArgumentParser(description="Run the Airbnb ELT pipeline end to end.")
    parser.add_argument("--snapshot-dates", nargs="+", required=True, type=validate_date)
    args = parser.parse_args(argv)

    from dotenv import load_dotenv

    load_dotenv(REPO_ROOT / ".env", override=False)
    dates = sorted(set(args.snapshot_dates))
    timings: list[tuple[str, float, str]] = []

    for d in dates:
        run(f"land {d}", [PY, "ingestion/land_files.py", "--snapshot-date", d], timings)
    for d in dates:
        run(f"load RAW {d}", [PY, "ingestion/load_raw.py", "--snapshot-date", d], timings)
    run("source freshness", [DBT, "source", "freshness", *DBT_FLAGS], timings)
    run("dbt build silver", [DBT, "build", *DBT_FLAGS, "--select", "silver"], timings)

    to_snapshot = snapshot_dates_to_run(dates, newest_recorded_snapshot())
    skipped = [d for d in dates if d not in to_snapshot]
    if skipped:
        print(f"\nSnapshot history already covers {', '.join(skipped)}: skipped (never write history backwards).")
        timings.append((f"snapshot {', '.join(skipped)}", 0.0, "skipped (already recorded)"))
    for d in to_snapshot:
        var = f"snapshot_date: {d}"
        run(f"current views {d}", [DBT, "build", *DBT_FLAGS, "--select",
                                   "stg_listings_current", "stg_hosts_current", "--vars", var], timings)
        run(f"dbt snapshot {d}", [DBT, "snapshot", *DBT_FLAGS, "--vars", var], timings)

    run("dbt build gold", [DBT, "build", *DBT_FLAGS, "--select", "gold", "assert_no_review_lost_in_gold"], timings)
    run("export gold", [PY, "scripts/export_gold.py"], timings)
    print_summary(timings)
    print("Warehouse: suspended by the export step (auto-suspend after 60 s also applies).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
