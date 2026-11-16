{#
  Availability fact. GRAIN: one row per listing per calendar date
  (listing_id + date_key), from stg_calendar.
  PRICE: Inside Airbnb's calendar files have no price column, so the nightly
  price is taken from the listing version valid on that date (dim_listing,
  point-in-time join). It is NULL when the listing showed no price (about a
  third of listings).
  is_available = FALSE includes nights the host blocked, not only bookings,
  so unavailability is a proxy for demand, not occupancy.
#}
{{ config(materialized='table') }}

WITH calendar AS (

    SELECT * FROM {{ ref('stg_calendar') }}

),

listings AS (

    SELECT * FROM {{ ref('dim_listing') }}
    WHERE listing_id <> -1

),

unknown AS (

    SELECT l.listing_key AS unknown_listing_key
    FROM {{ ref('dim_listing') }} AS l
    WHERE l.listing_id = -1

)

SELECT
    c.listing_id,
    TO_NUMBER(TO_CHAR(c.calendar_date, 'YYYYMMDD')) AS date_key,
    COALESCE(l.listing_key, u.unknown_listing_key) AS listing_key,
    c.calendar_date,
    c.is_available,
    c.minimum_nights,
    c.maximum_nights,
    l.price AS nightly_price,
    'listing_version' AS price_source,
    c.source_snapshot_date
FROM calendar AS c
CROSS JOIN unknown AS u
LEFT JOIN listings AS l
    ON
        c.listing_id = l.listing_id
        AND c.calendar_date >= l.valid_from
        AND c.calendar_date < l.valid_to
