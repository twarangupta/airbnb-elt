"""Unit tests for the RAW load runner. No Snowflake or AWS needed."""

import gzip
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ingestion"))

import load_raw  # noqa: E402


def test_header_from_gzip_prefix_reads_first_row_only():
    data = gzip.compress(b'listing_id,id,date\n1,2,"a\nb"\n')
    assert load_raw.header_from_gzip_prefix(data[:40]) == ["listing_id", "id", "date"]


def test_header_differences_none_when_equal_ignoring_case():
    assert load_raw.header_differences(["ID", "Name"], ["id", "name"]) == []


def test_header_differences_reports_reorder():
    problems = load_raw.header_differences(["id", "date", "name"], ["id", "name", "date"])
    assert any("position 2" in p for p in problems)


def test_header_differences_reports_added_column():
    problems = load_raw.header_differences(["id", "name", "new_col"], ["id", "name"])
    assert "file has 3 columns, table has 2" in problems
    assert any("new_col" in p for p in problems)


def test_build_copy_sql_maps_positions_and_metadata():
    sql = load_raw.build_copy_sql("calendar", ["listing_id", "date"], "2026-06-19")
    assert "COPY INTO AIRBNB.RAW.CALENDAR (" in sql
    assert "listing_id,\n    date,\n    _source_file,\n    _source_row,\n    _snapshot_date" in sql
    assert "t.$1,\n        t.$2,\n        metadata$filename" in sql
    assert "'2026-06-19'::date" in sql
    assert "@AIRBNB.RAW.LONDON_STAGE/snapshot_date=2026-06-19/" in sql
    assert "FILES = ('calendar.csv.gz')" in sql
    assert "ON_ERROR = ABORT_STATEMENT" in sql


def test_table_result_ok_only_when_counts_match():
    assert load_raw.TableResult("X", "LOADED", 5, 5, 5).ok
    assert not load_raw.TableResult("X", "LOADED", 4, 4, 5).ok
