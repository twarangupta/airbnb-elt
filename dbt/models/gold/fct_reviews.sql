{#
  Review fact. GRAIN: one row per review (review_id).
  Point-in-time joins: each review joins to the listing version valid on the
  review date, and that version's host to the host version valid on the same
  date (valid_from <= review_date < valid_to). Reviews whose listing is in no
  listings file get the "unknown" listing and host keys, so no review is lost.
  Keyed by review_id so extra per-review columns can be joined in later.
#}
{{ config(materialized='table') }}

WITH reviews AS (

    SELECT * FROM {{ ref('stg_reviews') }}

),

listings AS (

    SELECT * FROM {{ ref('dim_listing') }}
    WHERE listing_id <> -1

),

hosts AS (

    SELECT * FROM {{ ref('dim_host') }}
    WHERE host_id <> -1

),

unknown AS (

    SELECT
        (
            SELECT l.listing_key FROM {{ ref('dim_listing') }} AS l
            WHERE l.listing_id = -1
        ) AS unknown_listing_key,
        (
            SELECT h.host_key FROM {{ ref('dim_host') }} AS h
            WHERE h.host_id = -1
        ) AS unknown_host_key

)

SELECT
    r.review_id,
    TO_NUMBER(TO_CHAR(r.review_date, 'YYYYMMDD')) AS review_date_key,
    COALESCE(l.listing_key, u.unknown_listing_key) AS listing_key,
    COALESCE(h.host_key, u.unknown_host_key) AS host_key,
    r.listing_id,
    r.reviewer_id,
    r.review_date,
    r.comment_length,
    r.first_seen_snapshot_date
FROM reviews AS r
CROSS JOIN unknown AS u
LEFT JOIN listings AS l
    ON
        r.listing_id = l.listing_id
        AND r.review_date >= l.valid_from
        AND r.review_date < l.valid_to
LEFT JOIN hosts AS h
    ON
        l.host_id = h.host_id
        AND r.review_date >= h.valid_from
        AND r.review_date < h.valid_to
