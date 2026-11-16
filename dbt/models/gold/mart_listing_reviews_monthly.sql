{#
  GRAIN: one row per listing per month with at least one review.
  avg_review_score: the listing's overall rating (review_scores_rating, 0 to 5)
  from the listing version valid when each review was written, averaged over
  that month's reviews. Inside Airbnb gives one rating per listing, not per
  review, so this is the listing rating at the time, not a per-review score.
#}
{{ config(materialized='table') }}

SELECT
    f.listing_id,
    d.month_start_date,
    COUNT(*) AS review_count,
    COUNT(DISTINCT f.reviewer_id) AS unique_reviewers,
    ROUND(AVG(l.review_scores_rating), 2) AS avg_review_score
FROM {{ ref('fct_reviews') }} AS f
INNER JOIN {{ ref('dim_date') }} AS d ON f.review_date_key = d.date_key
INNER JOIN {{ ref('dim_listing') }} AS l ON f.listing_key = l.listing_key
GROUP BY f.listing_id, d.month_start_date
