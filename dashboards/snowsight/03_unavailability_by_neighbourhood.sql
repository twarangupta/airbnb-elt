-- Tile 3 (bar): share of forward calendar nights marked unavailable, by
-- neighbourhood. Unavailable includes host-blocked nights, so this is a
-- demand proxy, NOT occupancy. Source: GOLD.MART_NEIGHBOURHOOD_SUMMARY.
SELECT
    neighbourhood,
    ROUND(unavailability_rate * 100, 1) AS unavailable_nights_pct
FROM airbnb.gold.mart_neighbourhood_summary
ORDER BY unavailable_nights_pct DESC;
