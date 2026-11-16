-- Tile 4 (line): reviews per month, whole city, from 2015.
-- The last month is partial (the newest snapshot was taken mid-month).
-- Source: GOLD.MART_REVIEWS_MONTHLY (199 rows).
SELECT
    month_start_date,
    review_count
FROM airbnb.gold.mart_reviews_monthly
WHERE month_start_date >= '2015-01-01'
ORDER BY month_start_date;
