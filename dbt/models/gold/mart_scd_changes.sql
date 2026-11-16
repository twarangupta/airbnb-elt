{#
  GRAIN: one row per entity type (listing, host) per metric. How many records
  changed, appeared or left between consecutive Inside Airbnb snapshots, and
  which tracked columns changed. Read from the dbt snapshots.
  Built as one row of counts per entity type, then UNPIVOTed into rows.
  Dashboard SCD2 tile; exported.
#}
{{ config(materialized='table') }}

WITH listing_pairs AS (

    -- each closed version, paired with the version that replaced it (if any)
    SELECT
        n.listing_id AS next_listing_id,
        o.price AS old_price,
        n.price AS new_price,
        o.room_type AS old_room_type,
        n.room_type AS new_room_type,
        o.accommodates AS old_accommodates,
        n.accommodates AS new_accommodates,
        o.minimum_nights AS old_minimum_nights,
        n.minimum_nights AS new_minimum_nights,
        o.host_id AS old_host_id,
        n.host_id AS new_host_id
    FROM {{ ref('snap_listings') }} AS o
    LEFT JOIN {{ ref('snap_listings') }} AS n
        ON o.listing_id = n.listing_id AND o.dbt_valid_to = n.dbt_valid_from
    WHERE o.dbt_valid_to IS NOT NULL

),

host_pairs AS (

    SELECT
        n.host_id AS next_host_id,
        o.is_superhost AS old_superhost,
        n.is_superhost AS new_superhost,
        o.host_listings_count AS old_listings_count,
        n.host_listings_count AS new_listings_count,
        o.is_identity_verified AS old_verified,
        n.is_identity_verified AS new_verified,
        o.has_profile_pic AS old_profile_pic,
        n.has_profile_pic AS new_profile_pic
    FROM {{ ref('snap_hosts') }} AS o
    LEFT JOIN {{ ref('snap_hosts') }} AS n
        ON o.host_id = n.host_id AND o.dbt_valid_to = n.dbt_valid_from
    WHERE o.dbt_valid_to IS NOT NULL

),

listing_first_seen AS (

    SELECT
        listing_id,
        MIN(dbt_valid_from) AS first_valid_from
    FROM {{ ref('snap_listings') }}
    GROUP BY listing_id

),

host_first_seen AS (

    SELECT
        host_id,
        MIN(dbt_valid_from) AS first_valid_from
    FROM {{ ref('snap_hosts') }}
    GROUP BY host_id

),

listing_new AS (

    SELECT COUNT_IF(first_valid_from > (SELECT MIN(f.first_valid_from) FROM listing_first_seen AS f)) AS records_new
    FROM listing_first_seen

),

host_new AS (

    SELECT COUNT_IF(first_valid_from > (SELECT MIN(f.first_valid_from) FROM host_first_seen AS f)) AS records_new
    FROM host_first_seen

),

listing_counts AS (

    SELECT
        'listing' AS entity_type,
        COUNT_IF(p.next_listing_id IS NOT NULL) AS records_changed,
        COUNT_IF(p.next_listing_id IS NULL) AS records_left,
        MAX(n.records_new) AS records_new,
        COUNT_IF(p.next_listing_id IS NOT NULL AND NOT EQUAL_NULL(p.old_price, p.new_price)) AS price_changed,
        COUNT_IF(p.new_price > p.old_price) AS price_up,
        COUNT_IF(p.new_price < p.old_price) AS price_down,
        COUNT_IF(p.next_listing_id IS NOT NULL AND NOT EQUAL_NULL(p.old_room_type, p.new_room_type)) AS room_type_changed,
        COUNT_IF(p.next_listing_id IS NOT NULL AND NOT EQUAL_NULL(p.old_accommodates, p.new_accommodates))
            AS accommodates_changed,
        COUNT_IF(p.next_listing_id IS NOT NULL AND NOT EQUAL_NULL(p.old_minimum_nights, p.new_minimum_nights))
            AS minimum_nights_changed,
        COUNT_IF(p.next_listing_id IS NOT NULL AND NOT EQUAL_NULL(p.old_host_id, p.new_host_id)) AS host_changed
    FROM listing_pairs AS p
    CROSS JOIN listing_new AS n

),

host_counts AS (

    SELECT
        'host' AS entity_type,
        COUNT_IF(p.next_host_id IS NOT NULL) AS records_changed,
        COUNT_IF(p.next_host_id IS NULL) AS records_left,
        MAX(n.records_new) AS records_new,
        COUNT_IF(p.next_host_id IS NOT NULL AND NOT EQUAL_NULL(p.old_superhost, p.new_superhost)) AS superhost_changed,
        COUNT_IF(NOT p.old_superhost AND p.new_superhost) AS became_superhost,
        COUNT_IF(p.old_superhost AND NOT p.new_superhost) AS lost_superhost,
        COUNT_IF(p.next_host_id IS NOT NULL AND NOT EQUAL_NULL(p.old_listings_count, p.new_listings_count))
            AS listings_count_changed,
        COUNT_IF(p.next_host_id IS NOT NULL AND NOT EQUAL_NULL(p.old_verified, p.new_verified))
            AS identity_verified_changed,
        COUNT_IF(p.next_host_id IS NOT NULL AND NOT EQUAL_NULL(p.old_profile_pic, p.new_profile_pic))
            AS profile_pic_changed
    FROM host_pairs AS p
    CROSS JOIN host_new AS n

),

listing_rows AS (

    SELECT
        entity_type,
        LOWER(metric_name) AS metric_name,
        record_count
    FROM listing_counts
    UNPIVOT (record_count FOR metric_name IN (
        records_changed, records_left, records_new, price_changed, price_up, price_down,
        room_type_changed, accommodates_changed, minimum_nights_changed, host_changed
    ))

),

host_rows AS (

    SELECT
        entity_type,
        LOWER(metric_name) AS metric_name,
        record_count
    FROM host_counts
    UNPIVOT (record_count FOR metric_name IN (
        records_changed, records_left, records_new, superhost_changed, became_superhost,
        lost_superhost, listings_count_changed, identity_verified_changed, profile_pic_changed
    ))

)

SELECT * FROM listing_rows
UNION ALL
SELECT * FROM host_rows
