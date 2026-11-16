{#
  GRAIN: one row per month (whole city). Dashboard line chart; exported later.
#}
{{ config(materialized='table') }}

SELECT
    d.month_start_date,
    COUNT(*) AS review_count,
    COUNT(DISTINCT f.reviewer_id) AS unique_reviewers,
    COUNT(DISTINCT f.listing_id) AS reviewed_listings
FROM {{ ref('fct_reviews') }} AS f
INNER JOIN {{ ref('dim_date') }} AS d ON f.review_date_key = d.date_key
GROUP BY d.month_start_date
