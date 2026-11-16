{#
  Silver calendar: one row per listing per date, typed.

  INCREMENTAL with MERGE on (listing_id, calendar_date). Each snapshot holds
  the next 365 days. When a newer snapshot is loaded, dates it shares with the
  older one are UPDATED (the newer view of availability wins) and dates beyond
  the old window are INSERTED. Dates only in the older snapshot (now in the
  past) keep their last known values, so availability history is not lost.
  source_snapshot_date says which snapshot each row currently comes from.
  No price column: Inside Airbnb's calendar file has none (see Phase 5).
#}
{{
    config(
        materialized='incremental',
        unique_key=['listing_id', 'calendar_date'],
        incremental_strategy='merge',
        on_schema_change='fail'
    )
}}

WITH source AS (

    SELECT * FROM {{ source('raw', 'calendar') }}

    {% if is_incremental() %}
        -- only RAW rows loaded since the last successful run of this model
        WHERE _loaded_at > (SELECT MAX(existing.loaded_at) FROM {{ this }} AS existing)
    {% endif %}

),

latest_per_day AS (

    -- if one batch holds several snapshots, the newest snapshot wins per day
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY listing_id, date
        ORDER BY _snapshot_date DESC, _loaded_at DESC
    ) = 1

)

SELECT
    TRY_TO_NUMBER(listing_id) AS listing_id,
    TRY_TO_DATE(date) AS calendar_date,
    {{ to_boolean_tf('available') }} AS is_available,
    TRY_TO_NUMBER(minimum_nights) AS minimum_nights,
    TRY_TO_NUMBER(maximum_nights) AS maximum_nights,
    _snapshot_date AS source_snapshot_date,
    _loaded_at AS loaded_at
FROM latest_per_day
