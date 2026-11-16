{#
  Input for the hosts snapshot: ONE row per host, from ONE snapshot.
  Same rules as stg_listings_current.
#}
{{ config(materialized='view') }}

{% set chosen_snapshot = var('snapshot_date', none) %}

SELECT
    *,  -- noqa: AM04 (pass-through view: all stg columns plus snapshot_ts)
    snapshot_date::TIMESTAMP_NTZ AS snapshot_ts
FROM {{ ref('stg_hosts') }}
WHERE snapshot_date = {% if chosen_snapshot %}'{{ chosen_snapshot }}'::DATE{% else %}(SELECT MAX(h.snapshot_date) FROM {{ ref('stg_hosts') }} AS h){% endif %}
