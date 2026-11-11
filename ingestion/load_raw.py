"""Load one landed snapshot from S3 into the Snowflake RAW (Bronze) tables.

    make load-raw SNAPSHOT_DATE=2026-06-19

For each of LISTINGS, CALENDAR, REVIEWS:
  1. header guard: read the CSV header from the S3 file (first 64 KB only)
     and compare it with the RAW table's columns; stop on any difference,
     because COPY INTO maps columns by POSITION;
  2. COPY INTO with explicit columns plus metadata (_source_file,
     _source_row, _snapshot_date); ON_ERROR = ABORT_STATEMENT;
  3. reconcile: rows in the table for this snapshot must equal the
     row-count stored on the S3 object at landing.

Rerunning is safe: Snowflake's load metadata skips files it already loaded.
Credentials come from .env (key-pair login); nothing secret is printed.
Exit code 0 = every table reconciled, 1 = a check failed.
"""

from __future__ import annotations

import argparse
import csv
import io
import os
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
TABLES = ("listings", "calendar", "reviews")  # table name = file name stem
METADATA_COLUMNS = ("_source_file", "_source_row", "_snapshot_date")
STAGE = "AIRBNB.RAW.LONDON_STAGE"
FILE_FORMAT = "AIRBNB.RAW.FF_INSIDE_AIRBNB_CSV"


@dataclass
class TableResult:
    table: str
    copy_status: str
    rows_loaded_now: int
    rows_in_table: int
    rows_expected: int

    @property
    def ok(self) -> bool:
        return self.rows_in_table == self.rows_expected


def header_from_gzip_prefix(data: bytes) -> list[str]:
    """Parse the CSV header row from the first bytes of a gzip file."""
    text = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(data).decode("utf-8", "replace")
    return next(csv.reader(io.StringIO(text)))


def header_differences(file_header: list[str], table_columns: list[str]) -> list[str]:
    """Human-readable differences between file header and table columns (case-insensitive)."""
    file_cols = [c.lower() for c in file_header]
    table_cols = [c.lower() for c in table_columns]
    if file_cols == table_cols:
        return []
    problems = []
    if len(file_cols) != len(table_cols):
        problems.append(f"file has {len(file_cols)} columns, table has {len(table_cols)}")
    for position, (f, t) in enumerate(zip(file_cols, table_cols, strict=False), start=1):
        if f != t:
            problems.append(f"position {position}: file '{f}' vs table '{t}'")
            break
    missing = [c for c in table_cols if c not in file_cols]
    extra = [c for c in file_cols if c not in table_cols]
    if missing:
        problems.append(f"in table, not in file: {missing}")
    if extra:
        problems.append(f"in file, not in table: {extra}")
    return problems


def build_copy_sql(table: str, columns: list[str], snapshot_date: str) -> str:
    """COPY INTO with positional source columns plus metadata columns."""
    target_cols = ",\n    ".join([*columns, *METADATA_COLUMNS])
    source_cols = ",\n        ".join(
        [f"t.${i}" for i in range(1, len(columns) + 1)]
        + ["metadata$filename", "metadata$file_row_number", f"'{snapshot_date}'::date"]
    )
    return (
        f"COPY INTO AIRBNB.RAW.{table.upper()} (\n    {target_cols}\n)\n"
        f"FROM (\n    SELECT\n        {source_cols}\n"
        f"    FROM @{STAGE}/snapshot_date={snapshot_date}/ AS t\n)\n"
        f"FILES = ('{table}.csv.gz')\n"
        f"FILE_FORMAT = (FORMAT_NAME = '{FILE_FORMAT}')\n"
        f"ON_ERROR = ABORT_STATEMENT"
    )


def connect():
    import snowflake.connector

    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ.get("SNOWFLAKE_USER", "DBT_SVC"),
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        private_key_file_pwd=os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None,
        role=os.environ.get("SNOWFLAKE_ROLE", "TRANSFORMER"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "AIRBNB_WH"),
        database=os.environ.get("SNOWFLAKE_DATABASE", "AIRBNB"),
        schema="RAW",
        session_parameters={"QUERY_TAG": "airbnb_elt_load_raw"},
    )


def load_snapshot(city: str, snapshot_date: str, bucket: str) -> list[TableResult]:
    import boto3

    s3 = boto3.client("s3")
    results = []
    with connect() as conn, conn.cursor() as cur:
        for table in TABLES:
            key = f"raw/{city}/snapshot_date={snapshot_date}/{table}.csv.gz"
            print(f"{table.upper()} <- s3://{bucket}/{key}")

            head = s3.get_object(Bucket=bucket, Key=key, Range="bytes=0-65535")["Body"].read()
            cur.execute(
                "SELECT column_name FROM AIRBNB.INFORMATION_SCHEMA.COLUMNS "
                "WHERE table_schema = 'RAW' AND table_name = %s ORDER BY ordinal_position",
                (table.upper(),),
            )
            columns = [row[0].lower() for row in cur.fetchall() if not row[0].startswith("_")]
            problems = header_differences(header_from_gzip_prefix(head), columns)
            if problems:
                print("  header guard FAILED, not loading:\n   - " + "\n   - ".join(problems))
                raise SystemExit(1)
            print(f"  header guard ok ({len(columns)} columns)")

            expected = int(s3.head_object(Bucket=bucket, Key=key)["Metadata"]["row-count"])
            cur.execute(build_copy_sql(table, columns, snapshot_date))
            names = [d[0].lower() for d in cur.description]
            rows = [dict(zip(names, r, strict=True)) for r in cur.fetchall()]
            if rows and "rows_loaded" in rows[0]:
                status = rows[0]["status"]
                loaded_now = sum(int(r["rows_loaded"]) for r in rows)
            else:  # "Copy executed with 0 files processed."
                status = "SKIPPED (already loaded)"
                loaded_now = 0
            print(f"  COPY: {status}, {loaded_now:,} rows loaded now")

            cur.execute(
                f"SELECT COUNT(*) FROM AIRBNB.RAW.{table.upper()} WHERE _snapshot_date = %s",
                (snapshot_date,),
            )
            in_table = cur.fetchone()[0]
            results.append(TableResult(table.upper(), status, loaded_now, in_table, expected))
    return results


def main(argv: list[str] | None = None) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from land_files import validate_date

    parser = argparse.ArgumentParser(description="COPY one landed snapshot into Snowflake RAW.")
    parser.add_argument("--snapshot-date", required=True, type=validate_date)
    parser.add_argument("--city", default=os.environ.get("CITY", "london"))
    args = parser.parse_args(argv)

    from dotenv import load_dotenv

    load_dotenv(REPO_ROOT / ".env", override=False)
    results = load_snapshot(args.city, args.snapshot_date, os.environ["S3_BUCKET"])

    print("\nReconciliation (rows in table for this snapshot vs row-count at landing)")
    print(f"{'table':<10} {'copy status':<26} {'loaded now':>12} {'in table':>12} {'expected':>12}  check")
    for r in results:
        print(
            f"{r.table:<10} {r.copy_status:<26} {r.rows_loaded_now:>12,} {r.rows_in_table:>12,} "
            f"{r.rows_expected:>12,}  {'OK' if r.ok else 'MISMATCH'}"
        )
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
