-- Tile 5 (grouped bar): median nightly price by room type, per snapshot.
-- Source: GOLD.MART_PRICE_BY_ROOM_TYPE (8 rows).
SELECT
    room_type,
    TO_VARCHAR(snapshot_date) AS snapshot,
    median_price,
    listings
FROM airbnb.gold.mart_price_by_room_type
ORDER BY room_type, snapshot_date;
