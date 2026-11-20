"""Print the dbt lineage graph (sources, models, snapshots) as a Mermaid flowchart.

    make lineage        # runs dbt parse, then this script

Reads dbt/target/manifest.json, which `dbt parse` writes without connecting
to Snowflake, so the README diagram always matches the real dbt DAG.
Tests are left out; they hang off models and would clutter the picture.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = REPO_ROOT / "dbt" / "target" / "manifest.json"
LAYERS = {
    "source": "RAW (sources)",
    "silver": "SILVER",
    "snapshot": "SNAPSHOTS",
    "gold": "GOLD",
}


def node_layer(node: dict) -> str:
    if node["resource_type"] == "source":
        return "source"
    if node["resource_type"] == "snapshot":
        return "snapshot"
    return "gold" if "gold" in node.get("fqn", []) else "silver"


def short_name(unique_id: str) -> str:
    """'model.airbnb_elt.stg_listings' -> 'stg_listings'; 'source.airbnb_elt.raw.listings' -> 'raw.listings'."""
    parts = unique_id.split(".")
    return ".".join(parts[2:]) if parts[0] == "source" else parts[-1]


def mermaid(manifest: dict) -> str:
    nodes = {
        uid: n
        for uid, n in {**manifest["nodes"], **manifest["sources"]}.items()
        if n["resource_type"] in ("model", "snapshot", "source")
    }
    lines = ["flowchart LR"]
    for layer, title in LAYERS.items():
        members = sorted(uid for uid, n in nodes.items() if node_layer(n) == layer)
        if not members:
            continue
        lines.append(f'  subgraph {layer}["{title}"]')
        for uid in members:
            lines.append(f'    {short_name(uid).replace(".", "_")}["{short_name(uid)}"]')
        lines.append("  end")
    edges = set()
    for uid, n in nodes.items():
        for parent in n.get("depends_on", {}).get("nodes", []):
            if parent in nodes:
                edges.add((short_name(parent).replace(".", "_"), short_name(uid).replace(".", "_")))
    lines += [f"  {a} --> {b}" for a, b in sorted(edges)]
    return "\n".join(lines)


def main() -> int:
    if not MANIFEST.exists():
        print("dbt/target/manifest.json not found: run `make parse` first", file=sys.stderr)
        return 1
    print(mermaid(json.loads(MANIFEST.read_text(encoding="utf-8"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
