{#
  Input for the listings snapshot: ONE row per listing, from ONE Inside
  Airbnb snapshot. Which snapshot: var('snapshot_date') if given, else the
  newest one in stg_listings. Run dbt snapshot once per snapshot, oldest
  first (make snapshot SNAPSHOT_DATE=...).
  snapshot_ts is the snapshot date as a timestamp; the dbt snapshot uses it
  as updated_at, so versions start on the date the data describes, not on
  the day dbt happened to run.
#}
{{ config(materialized='view') }}

{% set chosen_snapshot = var('snapshot_date', none) %}

SELECT
    *,  -- noqa: AM04 (pass-through view: all stg columns plus snapshot_ts)
    snapshot_date::TIMESTAMP_NTZ AS snapshot_ts
FROM {{ ref('stg_listings') }}
WHERE snapshot_date = {% if chosen_snapshot %}'{{ chosen_snapshot }}'::DATE{% else %}(SELECT MAX(l.snapshot_date) FROM {{ ref('stg_listings') }} AS l){% endif %}
