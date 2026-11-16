{#
  Host dimension, SCD Type 2: one row per host VERSION (from snap_hosts),
  plus one "unknown" member. Same valid_from / valid_to / is_current rules
  as dim_listing (first version from 1900-01-01, last version open-ended).
  host_name is kept for analysis but must not appear in public outputs.
#}
{{ config(materialized='table') }}

WITH versions AS (

    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY host_id ORDER BY dbt_valid_from) AS version_number,
        LEAD(dbt_valid_from) OVER (PARTITION BY host_id ORDER BY dbt_valid_from) AS next_valid_from
    FROM {{ ref('snap_hosts') }}

),

dimension AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['host_id', 'dbt_valid_from']) }} AS host_key,
        host_id,
        host_name,
        host_neighbourhood,
        is_superhost,
        host_listings_count,
        is_identity_verified,
        has_profile_pic,
        version_number,
        CASE WHEN version_number = 1 THEN '1900-01-01'::DATE ELSE dbt_valid_from::DATE END AS valid_from,
        COALESCE(next_valid_from::DATE, '9999-12-31'::DATE) AS valid_to,
        dbt_valid_to IS NULL AS is_current,
        snapshot_date AS source_snapshot_date
    FROM versions

),

unknown_member AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }} AS host_key,
        -1 AS host_id,
        'Unknown host' AS host_name,
        'Unknown' AS host_neighbourhood,
        NULL AS is_superhost,
        NULL AS host_listings_count,
        NULL AS is_identity_verified,
        NULL AS has_profile_pic,
        1 AS version_number,
        '1900-01-01'::DATE AS valid_from,
        '9999-12-31'::DATE AS valid_to,
        FALSE AS is_current,
        NULL AS source_snapshot_date

)

SELECT * FROM dimension
UNION ALL
SELECT * FROM unknown_member
