"""Unit tests for the lineage diagram generator. No dbt or Snowflake needed."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import lineage_mermaid  # noqa: E402


def test_short_names():
    assert lineage_mermaid.short_name("model.airbnb_elt.stg_listings") == "stg_listings"
    assert lineage_mermaid.short_name("source.airbnb_elt.raw.listings") == "raw.listings"


def test_mermaid_groups_layers_and_draws_edges():
    manifest = {
        "sources": {
            "source.airbnb_elt.raw.listings": {"resource_type": "source", "fqn": ["airbnb_elt", "raw", "listings"]},
        },
        "nodes": {
            "model.airbnb_elt.stg_listings": {
                "resource_type": "model",
                "fqn": ["airbnb_elt", "silver", "stg_listings"],
                "depends_on": {"nodes": ["source.airbnb_elt.raw.listings"]},
            },
            "model.airbnb_elt.dim_listing": {
                "resource_type": "model",
                "fqn": ["airbnb_elt", "gold", "dim_listing"],
                "depends_on": {"nodes": ["model.airbnb_elt.stg_listings"]},
            },
            "test.airbnb_elt.some_test": {"resource_type": "test", "fqn": [], "depends_on": {"nodes": []}},
        },
    }
    out = lineage_mermaid.mermaid(manifest)
    assert out.startswith("flowchart LR")
    assert 'subgraph silver["SILVER"]' in out
    assert "raw_listings --> stg_listings" in out
    assert "stg_listings --> dim_listing" in out
    assert "some_test" not in out
