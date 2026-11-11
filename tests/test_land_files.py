"""Unit tests for the landing script. No network and no AWS needed."""

import argparse
import gzip
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ingestion"))

import land_files  # noqa: E402


def test_s3_key_uses_hive_style_snapshot_folder():
    key = land_files.s3_key("london", "2026-06-19", "reviews.csv.gz")
    assert key == "raw/london/snapshot_date=2026-06-19/reviews.csv.gz"


def test_s3_key_always_under_city_prefix_not_raw_root():
    # The stage in Phase 2 points at raw/<city>/, so nothing may land directly in raw/.
    key = land_files.s3_key("london", "2026-09-17", "listings.csv.gz")
    assert key.startswith("raw/london/")


def test_source_url():
    url = land_files.source_url("london", "2026-06-19", "calendar.csv.gz")
    assert url == (
        "https://data.insideairbnb.com/united-kingdom/england/london/"
        "2026-06-19/data/calendar.csv.gz"
    )


def test_count_rows_handles_newlines_inside_quoted_fields(tmp_path):
    path = tmp_path / "reviews.csv.gz"
    content = (
        "listing_id,id,comments\n"
        '1,10,"Great stay"\n'
        '1,11,"Line one\nLine two\nLine three"\n'
        '2,12,"He said ""wow"""\n'
    )
    with gzip.open(path, "wt", encoding="utf-8", newline="") as handle:
        handle.write(content)
    # 3 reviews, even though the file has 6 physical lines.
    assert land_files.count_csv_rows(path) == 3


def test_count_rows_header_only(tmp_path):
    path = tmp_path / "empty.csv.gz"
    with gzip.open(path, "wt", encoding="utf-8") as handle:
        handle.write("id,name\n")
    assert land_files.count_csv_rows(path) == 0


@pytest.mark.parametrize("bad", ["2026-13-01", "19-06-2026", "latest"])
def test_validate_date_rejects_bad_dates(bad):
    with pytest.raises(argparse.ArgumentTypeError):
        land_files.validate_date(bad)


def test_validate_date_accepts_iso_date():
    assert land_files.validate_date("2026-06-19") == "2026-06-19"
