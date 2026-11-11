"""Land one Inside Airbnb snapshot in S3, untouched.

For each of listings.csv.gz, calendar.csv.gz and reviews.csv.gz:
  1. skip it if it is already in S3 (raw files are immutable; reruns are safe),
  2. download it once to data/<city>/<snapshot_date>/ (gitignored),
  3. count its CSV rows (so Phase 2 can check COPY INTO loaded every row),
  4. upload it byte-for-byte to
     s3://<bucket>/raw/<city>/snapshot_date=<YYYY-MM-DD>/<file>
     with the row count, sha256 and source URL as S3 object metadata.

Usage (from the repo root):
    make land SNAPSHOT_DATE=2026-06-19
    python ingestion/land_files.py --snapshot-date 2026-06-19 [--city london] [--dry-run]

Credentials: boto3 reads AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY /
AWS_DEFAULT_REGION from the environment (.env, loaded below). This script
never reads, prints or logs them.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import hashlib
import os
import sys
from dataclasses import dataclass
from pathlib import Path

import requests

REPO_ROOT = Path(__file__).resolve().parents[1]
FILES = ("listings.csv.gz", "calendar.csv.gz", "reviews.csv.gz")
BASE_URL = "https://data.insideairbnb.com"

# Inside Airbnb publishes each city under country/region/city.
CITY_SOURCES = {
    "london": "united-kingdom/england/london",
}

# Review text can be very long; raise the csv module's per-field limit
# (2**31 - 1 is the largest value Windows accepts).
csv.field_size_limit(2**31 - 1)


@dataclass
class LandedFile:
    name: str
    s3_key: str
    status: str  # "uploaded", "already in S3", or "dry run"
    size_bytes: int | None = None
    row_count: int | None = None


def source_url(city: str, snapshot_date: str, file_name: str) -> str:
    """Public download URL of one Inside Airbnb file."""
    return f"{BASE_URL}/{CITY_SOURCES[city]}/{snapshot_date}/data/{file_name}"


def s3_key(city: str, snapshot_date: str, file_name: str) -> str:
    """Where the file lives in our bucket: Hive-style folder per snapshot."""
    return f"raw/{city}/snapshot_date={snapshot_date}/{file_name}"


def validate_date(value: str) -> str:
    """argparse type: accept only YYYY-MM-DD."""
    try:
        dt.date.fromisoformat(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"not a YYYY-MM-DD date: {value}") from exc
    return value


def count_csv_rows(path: Path) -> int:
    """Data rows in a gzipped CSV, excluding the header.

    Uses the csv module, not a line count, because review comments contain
    newlines inside quoted fields: one review can span several lines.
    """
    with gzip.open(path, "rt", encoding="utf-8", newline="") as handle:
        rows = sum(1 for _ in csv.reader(handle))
    return max(rows - 1, 0)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, target: Path) -> None:
    """Stream a file to disk once; reuse it if the same size is already there."""
    target.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(url, stream=True, timeout=60) as response:
        response.raise_for_status()
        expected = int(response.headers.get("Content-Length", 0)) or None
        if target.exists() and expected and target.stat().st_size == expected:
            print(f"  reuse local copy {target.relative_to(REPO_ROOT)}")
            return
        partial = target.with_suffix(target.suffix + ".part")
        with partial.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                handle.write(chunk)
        if expected and partial.stat().st_size != expected:
            raise RuntimeError(f"incomplete download of {url}")
        partial.replace(target)


def object_exists(s3, bucket: str, key: str) -> bool:
    """True if the exact key is already in the bucket.

    Uses ListObjectsV2 with the key as prefix (allowed by our IAM policy)
    rather than HeadObject, which returns 403 instead of 404 for missing
    keys when list permission is limited by prefix.
    """
    response = s3.list_objects_v2(Bucket=bucket, Prefix=key, MaxKeys=1)
    return any(obj["Key"] == key for obj in response.get("Contents", []))


def land_snapshot(city: str, snapshot_date: str, bucket: str, dry_run: bool) -> list[LandedFile]:
    import boto3  # imported here so unit tests do not need AWS libraries loaded

    s3 = boto3.client("s3")
    results: list[LandedFile] = []
    for name in FILES:
        key = s3_key(city, snapshot_date, name)
        print(f"{name}: s3://{bucket}/{key}")
        if object_exists(s3, bucket, key):
            print("  already in S3, skipped (raw files are never overwritten)")
            results.append(LandedFile(name, key, "already in S3"))
            continue
        if dry_run:
            results.append(LandedFile(name, key, "dry run"))
            continue

        url = source_url(city, snapshot_date, name)
        local = REPO_ROOT / "data" / city / snapshot_date / name
        download(url, local)
        rows = count_csv_rows(local)
        size = local.stat().st_size
        print(f"  {size:,} bytes, {rows:,} rows; uploading")
        s3.upload_file(
            str(local),
            bucket,
            key,
            ExtraArgs={
                "ContentType": "application/gzip",
                "Metadata": {
                    "source-url": url,
                    "snapshot-date": snapshot_date,
                    "row-count": str(rows),
                    "sha256": sha256_of(local),
                    "landed-at": dt.datetime.now(dt.UTC).isoformat(timespec="seconds"),
                },
            },
        )
        results.append(LandedFile(name, key, "uploaded", size, rows))
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Land one Inside Airbnb snapshot in S3.")
    parser.add_argument("--snapshot-date", required=True, type=validate_date, help="YYYY-MM-DD")
    parser.add_argument("--city", default=os.environ.get("CITY", "london"), choices=sorted(CITY_SOURCES))
    parser.add_argument("--dry-run", action="store_true", help="only check what is already in S3")
    args = parser.parse_args(argv)

    from dotenv import load_dotenv

    load_dotenv(REPO_ROOT / ".env", override=False)  # no-op for values make already exported
    bucket = os.environ.get("S3_BUCKET")
    if not bucket:
        print("S3_BUCKET is not set (add it to .env)", file=sys.stderr)
        return 2

    results = land_snapshot(args.city, args.snapshot_date, bucket, args.dry_run)

    print("\nSummary")
    print(f"{'file':<17} {'status':<14} {'bytes':>13} {'rows':>12}")
    for item in results:
        size = f"{item.size_bytes:,}" if item.size_bytes is not None else "-"
        rows = f"{item.row_count:,}" if item.row_count is not None else "-"
        print(f"{item.name:<17} {item.status:<14} {size:>13} {rows:>12}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
