{#
  Silver hosts: one row per host per snapshot.
  Host details are repeated on every listing of that host; profiling showed
  they are identical across a host's listings within a snapshot, so we keep
  the row from the most recently scraped listing (ties: lowest listing id).
  Note: in the 2026-06-19 snapshot host_since, host_response_rate,
  host_response_time, host_acceptance_rate and host_total_listings_count are
  NULL for every row; they are kept so a later snapshot can fill them.
#}
{{ config(materialized='table') }}

WITH source AS (

    SELECT * FROM {{ source('raw', 'listings') }}

),

one_row_per_host AS (

    SELECT *
    FROM source
    WHERE host_id IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY host_id, _snapshot_date
        ORDER BY TRY_TO_DATE(last_scraped) DESC, TRY_TO_NUMBER(id) ASC, _loaded_at DESC
    ) = 1

)

SELECT
    TRY_TO_NUMBER(host_id) AS host_id,
    _snapshot_date AS snapshot_date,
    host_name,
    host_url,
    host_location,
    host_neighbourhood,
    TRY_TO_DATE(host_since) AS host_since_date,
    host_response_time,
    {{ percent_to_fraction('host_response_rate') }} AS host_response_rate,
    {{ percent_to_fraction('host_acceptance_rate') }} AS host_acceptance_rate,
    {{ to_boolean_tf('host_is_superhost') }} AS is_superhost,
    TRY_TO_NUMBER(host_listings_count) AS host_listings_count,
    TRY_TO_NUMBER(host_total_listings_count) AS host_total_listings_count,
    TRY_TO_NUMBER(calculated_host_listings_count) AS calculated_host_listings_count,
    {{ to_boolean_tf('host_has_profile_pic') }} AS has_profile_pic,
    {{ to_boolean_tf('host_identity_verified') }} AS is_identity_verified,
    host_verifications,
    _loaded_at AS loaded_at

FROM one_row_per_host
