{#
  GRAIN: one row (the whole city, newest snapshot). KPI tiles for the
  dashboard; exported later. A city median cannot be derived from
  neighbourhood medians, so it is computed here from the listings.
  previous_* columns compare with the snapshot before the newest one.
#}
{{ config(materialized='table') }}

WITH snapshots AS (

    SELECT
        snapshot_date,
        ROW_NUMBER() OVER (ORDER BY snapshot_date DESC) AS recency
    FROM (SELECT DISTINCT s.snapshot_date FROM {{ ref('stg_listings') }} AS s)

),

listing_kpis AS (

    SELECT
        l.snapshot_date,
        COUNT(*) AS active_listings,
        COUNT(l.price) AS listings_with_price,
        MEDIAN(l.price) AS median_price,
        COUNT(DISTINCT l.host_id) AS active_hosts
    FROM {{ ref('stg_listings') }} AS l
    GROUP BY l.snapshot_date

),

newest AS (

    SELECT k.*
    FROM listing_kpis AS k
    INNER JOIN snapshots AS s ON k.snapshot_date = s.snapshot_date
    WHERE s.recency = 1

),

previous AS (

    SELECT k.*
    FROM listing_kpis AS k
    INNER JOIN snapshots AS s ON k.snapshot_date = s.snapshot_date
    WHERE s.recency = 2

),

availability AS (

    SELECT ROUND(AVG(IFF(f.is_available, 0, 1)), 4) AS unavailability_rate
    FROM {{ ref('fct_availability') }} AS f
    INNER JOIN newest AS n ON f.source_snapshot_date = n.snapshot_date

),

reviews AS (

    SELECT
        COUNT(*) AS total_reviews,
        COUNT_IF(f.review_date > DATEADD('month', -12, n.snapshot_date)) AS reviews_last_12_months
    FROM {{ ref('fct_reviews') }} AS f
    CROSS JOIN newest AS n

)

SELECT
    n.snapshot_date,
    n.active_listings,
    n.listings_with_price,
    n.median_price,
    n.active_hosts,
    a.unavailability_rate,
    r.total_reviews,
    r.reviews_last_12_months,
    p.snapshot_date AS previous_snapshot_date,
    p.active_listings AS previous_active_listings,
    p.median_price AS previous_median_price
FROM newest AS n
CROSS JOIN availability AS a
CROSS JOIN reviews AS r
LEFT JOIN previous AS p ON TRUE
