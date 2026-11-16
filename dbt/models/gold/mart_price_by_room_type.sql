{#
  GRAIN: one row per snapshot per room type. Dashboard bar chart; exported.
  Median and quartiles (outlier-resistant); only listings that show a price.
#}
{{ config(materialized='table') }}

SELECT
    snapshot_date,
    room_type,
    COUNT(*) AS listings,
    COUNT(price) AS listings_with_price,
    MEDIAN(price) AS median_price,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price) AS p25_price,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY price) AS p75_price
FROM {{ ref('stg_listings') }}
GROUP BY snapshot_date, room_type
