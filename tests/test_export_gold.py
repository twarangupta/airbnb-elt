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
    entry = export_gold.manifest_entry("mart_x", "SELECT 1", 3, ["a", "b"], path, "d")
    assert entry["file"] == "exports/gold/x.parquet"
    assert entry["rows"] == 3
    assert entry["bytes"] == 3
    assert entry["sha256"] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    assert entry["table"] == "AIRBNB.GOLD.MART_X"
    assert entry["data_sha256"] == "d"


def test_attribution_names_the_licence():
    assert "Inside Airbnb" in export_gold.ATTRIBUTION
    assert "CC BY 4.0" in export_gold.ATTRIBUTION


def test_unchanged_compares_data_fingerprints(tmp_path):
    import json

    manifest = tmp_path / "manifest.json"
    hashes = {"AIRBNB.GOLD.MART_A": "abc"}
    assert not export_gold.unchanged(hashes, manifest)  # no manifest yet
    old = {"tables": [{"table": "AIRBNB.GOLD.MART_A", "data_sha256": "abc"}]}
    manifest.write_text(json.dumps(old), encoding="utf-8")
    assert export_gold.unchanged(hashes, manifest)
    assert not export_gold.unchanged({"AIRBNB.GOLD.MART_A": "xyz"}, manifest)


def test_data_sha256_ignores_file_encoding():
    import pyarrow as pa

    a = pa.table({"x": [1, 2], "y": ["a", "b"]})
    b = pa.concat_tables([a.slice(0, 1), a.slice(1, 1)])  # same data, different chunks
    assert export_gold.data_sha256(a) == export_gold.data_sha256(b)
