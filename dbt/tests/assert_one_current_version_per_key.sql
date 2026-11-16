-- Singular test: an SCD Type 2 table must have at most ONE current version
-- (dbt_valid_to IS NULL) per key, and no version may end before it starts.
-- Returns the offending keys; passes when empty.
WITH listing_problems AS (
    SELECT
        'snap_listings' AS snapshot_name,
        listing_id AS entity_key
    FROM {{ ref('snap_listings') }}
    GROUP BY listing_id
    HAVING COUNT_IF(dbt_valid_to IS NULL) > 1 OR COUNT_IF(dbt_valid_to < dbt_valid_from) > 0
),

host_problems AS (
    SELECT
        'snap_hosts' AS snapshot_name,
        host_id AS entity_key
    FROM {{ ref('snap_hosts') }}
    GROUP BY host_id
    HAVING COUNT_IF(dbt_valid_to IS NULL) > 1 OR COUNT_IF(dbt_valid_to < dbt_valid_from) > 0
)

SELECT * FROM listing_problems
UNION ALL
SELECT * FROM host_problems
