"""Unit tests for the pipeline runner's snapshot guard. No Snowflake needed."""

import datetime as dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import run_pipeline  # noqa: E402


def test_first_run_snapshots_every_date_oldest_first():
    assert run_pipeline.snapshot_dates_to_run(["2026-09-17", "2026-06-19"], None) == ["2026-06-19", "2026-09-17"]


def test_rerun_skips_dates_already_recorded():
    assert run_pipeline.snapshot_dates_to_run(["2026-06-19", "2026-09-17"], dt.date(2026, 9, 17)) == []


def test_only_newer_dates_run_never_backwards():
    newest = dt.date(2026, 9, 17)
    assert run_pipeline.snapshot_dates_to_run(["2026-06-19", "2026-12-15"], newest) == ["2026-12-15"]
