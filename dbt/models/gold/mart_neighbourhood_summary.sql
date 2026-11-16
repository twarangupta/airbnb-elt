{#
  GRAIN: one row per neighbourhood, for the newest snapshot. Small and
  dashboard-ready (exported later).
  - Prices: MEDIAN is the headline (prices range from about 2 to over 500,000
    a night, so averages are pulled up by outliers); AVG kept for comparison.
    Only listings that show a price count.
  - unavailability_rate: share of calendar nights marked unavailable in the
    newest snapshot's forward window. Unavailable includes nights the host
    blocked, not only bookings, so this is a PROXY for demand, not occupancy.
  - review_count: all reviews of listings in the neighbourhood (any time);
    reviews_last_12_months: reviews in the 12 months before the snapshot.
#}
{{ config(materialized='table') }}

WITH latest_snapshot AS (

    SELECT MAX(snapshot_date) AS snapshot_date FROM {{ ref('stg_listings') }}

),

active_listings AS (

    SELECT s.*
    FROM {{ ref('stg_listings') }} AS s
    INNER JOIN latest_snapshot ON s.snapshot_date = latest_snapshot.snapshot_date

),

listing_stats AS (

    SELECT
        neighbourhood,
        COUNT(*) AS active_listings,
        COUNT(price) AS listings_with_price,
        MEDIAN(price) AS median_price,
        ROUND(AVG(price), 2) AS avg_price,
        ROUND(AVG(review_scores_rating), 2) AS avg_review_score
    FROM active_listings
    GROUP BY neighbourhood

),

availability_stats AS (

    SELECT
        a.neighbourhood,
        COUNT(*) AS calendar_nights,
        ROUND(AVG(IFF(f.is_available, 0, 1)), 4) AS unavailability_rate
    FROM {{ ref('fct_availability') }} AS f
    INNER JOIN latest_snapshot ON f.source_snapshot_date = latest_snapshot.snapshot_date
    INNER JOIN active_listings AS a ON f.listing_id = a.listing_id
    GROUP BY a.neighbourhood

),

review_stats AS (

    SELECT
        l.neighbourhood,
        COUNT(*) AS review_count,
        COUNT_IF(f.review_date > DATEADD('month', -12, latest_snapshot.snapshot_date)) AS reviews_last_12_months
    FROM {{ ref('fct_reviews') }} AS f
    INNER JOIN {{ ref('dim_listing') }} AS l ON f.listing_key = l.listing_key
    CROSS JOIN latest_snapshot
    WHERE l.listing_id <> -1
    GROUP BY l.neighbourhood

)

SELECT
    lst.neighbourhood,
    latest_snapshot.snapshot_date,
    lst.active_listings,
    lst.listings_with_price,
    lst.median_price,
    lst.avg_price,
    av.unavailability_rate,
    av.calendar_nights,
    rs.review_count,
    rs.reviews_last_12_months,
    lst.avg_review_score
FROM listing_stats AS lst
CROSS JOIN latest_snapshot
LEFT JOIN availability_stats AS av ON lst.neighbourhood = av.neighbourhood
LEFT JOIN review_stats AS rs ON lst.neighbourhood = rs.neighbourhood
