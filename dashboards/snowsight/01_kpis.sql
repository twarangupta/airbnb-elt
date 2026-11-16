-- Tile 1 (scorecards): active listings and median nightly price, newest snapshot,
-- with the previous snapshot for comparison. Source: GOLD.MART_CITY_KPIS (1 row).
SELECT
    snapshot_date,
    active_listings,
    median_price,
    ROUND(unavailability_rate * 100, 1) AS unavailable_nights_pct,
    total_reviews,
    previous_snapshot_date,
    previous_active_listings,
    previous_median_price
FROM airbnb.gold.mart_city_kpis;
