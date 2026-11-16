-- Tile 6 (table or bar): what changed between the two snapshots, from the
-- SCD Type 2 snapshots. Source: GOLD.MART_SCD_CHANGES (19 rows).
SELECT
    entity_type,
    REPLACE(metric_name, '_', ' ') AS change_metric,
    record_count
FROM airbnb.gold.mart_scd_changes
ORDER BY entity_type ASC, record_count DESC;
