"""Unit tests for the Gold export helpers. No Snowflake needed."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import export_gold  # noqa: E402


def test_only_small_marts_are_exported():
    assert set(export_gold.MARTS) == {
        "mart_city_kpis",
        "mart_neighbourhood_summary",
        "mart_reviews_monthly",
        "mart_price_by_room_type",
        "mart_scd_changes",
    }
    # the big tables must never be exported
    for big in ("fct_reviews", "fct_availability", "mart_listing_reviews_monthly", "dim_host"):
        assert big not in export_gold.MARTS


def test_source_query_is_deterministic():
    q = export_gold.source_query("mart_reviews_monthly", "month_start_date")
    assert q == "SELECT * FROM AIRBNB.GOLD.MART_REVIEWS_MONTHLY ORDER BY month_start_date"


def test_manifest_entry(tmp_path, monkeypatch):
    monkeypatch.setattr(export_gold, "REPO_ROOT", tmp_path)
    path = tmp_path / "exports" / "gold" / "x.parquet"
    path.parent.mkdir(parents=True)
    path.write_bytes(b"abc")
    entry = export_gold.manifest_entry("mart_x", "SELECT 1", 3, ["a", "b"], path)
    assert entry["file"] == "exports/gold/x.parquet"
    assert entry["rows"] == 3
    assert entry["bytes"] == 3
    assert entry["sha256"] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    assert entry["table"] == "AIRBNB.GOLD.MART_X"


def test_attribution_names_the_licence():
    assert "Inside Airbnb" in export_gold.ATTRIBUTION
    assert "CC BY 4.0" in export_gold.ATTRIBUTION
