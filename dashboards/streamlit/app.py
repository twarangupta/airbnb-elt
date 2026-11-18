"""Public Streamlit dashboard for the Airbnb London ELT project.

Reads the small Gold exports in exports/gold/ (written by
scripts/export_gold.py), so it needs no warehouse and no credentials, and it
keeps working after the Snowflake trial ends.

    streamlit run dashboards/streamlit/app.py
"""

from __future__ import annotations

import json
from pathlib import Path

import altair as alt
import pandas as pd
import streamlit as st

AIRBNB = Path(__file__).resolve().parents[2] / "exports" / "gold"

st.set_page_config(page_title="Airbnb London ELT", page_icon="🏠", layout="wide")


@st.cache_data
def load(name: str) -> pd.DataFrame:
    df = pd.read_parquet(AIRBNB / f"{name}.parquet")
    df.columns = [c.lower() for c in df.columns]
    return df


@st.cache_data
def manifest() -> dict:
    path = AIRBNB / "manifest.json"
    return json.loads(path.read_text()) if path.exists() else {}


def airbnb_tab() -> None:
    kpi = load("mart_city_kpis").iloc[0]
    hoods = load("mart_neighbourhood_summary")
    reviews = load("mart_reviews_monthly")
    rooms = load("mart_price_by_room_type")
    changes = load("mart_scd_changes")

    st.subheader("Market snapshot")
    st.caption(
        "Two public snapshots of every London Airbnb listing. Pipeline: S3 → Snowflake → dbt "
        "(RAW → SILVER → SCD2 snapshots → GOLD). Prices are medians because a few listings "
        "have extreme prices."
    )

    def delta(now, before, fmt):
        if pd.isna(before) or before == 0:
            return None
        return fmt(now - before)

    c1, c2, c3, c4 = st.columns(4)
    c1.metric(
        f"Active listings ({kpi.snapshot_date})",
        f"{int(kpi.active_listings):,}",
        delta(kpi.active_listings, kpi.previous_active_listings, lambda d: f"{int(d):+,} vs June"),
    )
    c2.metric(
        "Median nightly price",
        f"£{kpi.median_price:,.0f}",
        delta(kpi.median_price, kpi.previous_median_price, lambda d: f"{'-' if d < 0 else '+'}£{abs(d):,.0f} vs June"),
        delta_color="inverse",
    )
    c3.metric("Forward nights unavailable", f"{kpi.unavailability_rate * 100:.1f}%")
    c4.metric("Reviews (all time)", f"{int(kpi.total_reviews):,}")

    st.markdown("#### Where is London expensive?")
    st.altair_chart(
        alt.Chart(hoods)
        .mark_bar()
        .encode(
            x=alt.X("neighbourhood:N", sort="-y", title=None),
            y=alt.Y("median_price:Q", title="Median nightly price (£)"),
            tooltip=["neighbourhood", alt.Tooltip("median_price:Q", format=",.0f"), "active_listings"],
        )
        .properties(height=340),
        width="stretch",
    )
    st.caption("Central areas (Westminster, City of London, Kensington and Chelsea) cost about 3× the outer boroughs.")

    st.markdown("#### Which areas look busiest?")
    hoods = hoods.assign(unavailable_pct=(hoods.unavailability_rate * 100).round(1))
    st.altair_chart(
        alt.Chart(hoods)
        .mark_bar(color="#e0a33a")
        .encode(
            x=alt.X("neighbourhood:N", sort="-y", title=None),
            y=alt.Y("unavailable_pct:Q", title="Forward nights unavailable (%)"),
            tooltip=["neighbourhood", "unavailable_pct"],
        )
        .properties(height=340),
        width="stretch",
    )
    st.caption(
        "A demand hint, not occupancy: unavailable nights include dates the host blocked. "
        "Trendy mid-priced areas lead, not the most expensive ones."
    )

    left, right = st.columns(2)
    with left:
        st.markdown("#### Reviews per month")
        recent = reviews[pd.to_datetime(reviews.month_start_date) >= "2015-01-01"]
        st.altair_chart(
            alt.Chart(recent)
            .mark_area(line=True, opacity=0.35)
            .encode(
                x=alt.X("month_start_date:T", title=None),
                y=alt.Y("review_count:Q", title="Reviews"),
                tooltip=[alt.Tooltip("month_start_date:T", format="%b %Y"), "review_count"],
            )
            .properties(height=300),
            width="stretch",
        )
        st.caption(
            "Reviews are a proxy for stays: the April 2020 COVID collapse, then record highs. "
            "The last month is partial."
        )
    with right:
        st.markdown("#### Price by room type: June vs September")
        rooms = rooms.assign(snapshot=rooms.snapshot_date.astype(str))
        st.altair_chart(
            alt.Chart(rooms)
            .mark_bar()
            .encode(
                x=alt.X("room_type:N", title=None),
                xOffset="snapshot:N",
                y=alt.Y("median_price:Q", title="Median nightly price (£)"),
                color=alt.Color("snapshot:N", title="Snapshot"),
                tooltip=["room_type", "snapshot", alt.Tooltip("median_price:Q", format=",.1f"), "listings"],
            )
            .properties(height=300),
            width="stretch",
        )
        st.caption("A whole home costs about 3× a private room.")

    st.markdown("#### What changed between the snapshots (SCD Type 2)")
    st.dataframe(
        changes.assign(metric_name=changes.metric_name.str.replace("_", " "))
        .sort_values(["entity_type", "record_count"], ascending=[True, False])
        .rename(columns={"entity_type": "Entity", "metric_name": "Change", "record_count": "Records"}),
        hide_index=True,
        width="stretch",
    )
    st.caption(
        "History is kept, not overwritten: every changed listing or host gets a new version row with validity dates."
    )

    m = manifest()
    st.divider()
    st.caption(
        f"{m.get('attribution', 'Data: Inside Airbnb (CC BY 4.0)')} · "
        f"Exported {m.get('exported_at', 'n/a')} · "
        "[Pipeline code](https://github.com/twarangupta/airbnb-elt)"
    )


st.title("🏠 Airbnb London: ELT pipeline results")
st.write(
    "Built by **Twaran Gupta** on the Gold layer of an S3 → Snowflake → dbt pipeline. "
    "The Gold tables are exported as small Parquet files, so this app needs no credentials."
)
airbnb_tab()
