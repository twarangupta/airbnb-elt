{#
  Listing dimension, SCD Type 2: one row per listing VERSION (from the
  snap_listings dbt snapshot), plus one "unknown" member.

  Point-in-time join columns (use these, not dbt_valid_*):
    valid_from: the version's start date, EXCEPT the first version of each
                listing starts at 1900-01-01. Versions only begin at our first
                snapshot (2026-06-19) but reviews go back to 2009; without
                this, older reviews would match no version and silently drop
                out of the join. (Alternative: join older events to the first
                version explicitly; same result, more join logic.)
    valid_to:   the next version's start date; the LAST version of each
                listing is open-ended (9999-12-31), even if the listing has
                left Inside Airbnb, so late reviews still find it.
  is_current: TRUE only for the version still listed in the newest snapshot
              (dbt_valid_to IS NULL); listings that left are FALSE.
#}
{{ config(materialized='table') }}

WITH versions AS (

    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY listing_id ORDER BY dbt_valid_from) AS version_number,
        LEAD(dbt_valid_from) OVER (PARTITION BY listing_id ORDER BY dbt_valid_from) AS next_valid_from
    FROM {{ ref('snap_listings') }}

),

dimension AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['listing_id', 'dbt_valid_from']) }} AS listing_key,
        listing_id,
        host_id,
        listing_name,
        neighbourhood,
        latitude,
        longitude,
        property_type,
        room_type,
        accommodates,
        bedrooms,
        beds,
        price,
        minimum_nights,
        maximum_nights,
        review_scores_rating,
        number_of_reviews,
        version_number,
        CASE WHEN version_number = 1 THEN '1900-01-01'::DATE ELSE dbt_valid_from::DATE END AS valid_from,
        COALESCE(next_valid_from::DATE, '9999-12-31'::DATE) AS valid_to,
        dbt_valid_to IS NULL AS is_current,
        snapshot_date AS source_snapshot_date
    FROM versions

),

unknown_member AS (

    -- Facts whose listing is not in any listings file (a source gap) point here
    -- instead of being dropped.
    SELECT
        {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }} AS listing_key,
        -1 AS listing_id,
        -1 AS host_id,
        'Unknown listing' AS listing_name,
        'Unknown' AS neighbourhood,
        NULL AS latitude,
        NULL AS longitude,
        'Unknown' AS property_type,
        'Unknown' AS room_type,
        NULL AS accommodates,
        NULL AS bedrooms,
        NULL AS beds,
        NULL AS price,
        NULL AS minimum_nights,
        NULL AS maximum_nights,
        NULL AS review_scores_rating,
        NULL AS number_of_reviews,
        1 AS version_number,
        '1900-01-01'::DATE AS valid_from,
        '9999-12-31'::DATE AS valid_to,
        FALSE AS is_current,
        NULL AS source_snapshot_date

)

SELECT * FROM dimension
UNION ALL
SELECT * FROM unknown_member
