-- Tile 2 (bar): median nightly price by neighbourhood, newest snapshot.
-- Median, not average: listed prices have extreme outliers.
-- Source: GOLD.MART_NEIGHBOURHOOD_SUMMARY (33 rows).
SELECT
    neighbourhood,
    median_price,
    active_listings
FROM airbnb.gold.mart_neighbourhood_summary
ORDER BY median_price DESC;
