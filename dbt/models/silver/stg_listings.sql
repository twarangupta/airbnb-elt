{#
  Silver listings: one row per listing per snapshot, typed and cleaned.
  Host details live in stg_hosts; only host_id is kept here.
  Materialized as a table (about 93k rows per snapshot, rebuilt in seconds).
#}
{{ config(materialized='table') }}

WITH source AS (

    SELECT * FROM {{ source('raw', 'listings') }}

),

deduplicated AS (

    -- One row per listing per snapshot. RAW is append-only, so if a file were
    -- ever loaded twice the latest load wins.
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id, _snapshot_date
        ORDER BY _loaded_at DESC, _source_row DESC
    ) = 1

)

SELECT
    -- keys
    TRY_TO_NUMBER(id) AS listing_id,
    TRY_TO_NUMBER(host_id) AS host_id,
    _snapshot_date AS snapshot_date,

    -- descriptive
    name AS listing_name,
    neighbourhood_cleansed AS neighbourhood,
    TRY_TO_DOUBLE(latitude) AS latitude,
    TRY_TO_DOUBLE(longitude) AS longitude,
    property_type,
    room_type,
    TRY_TO_NUMBER(accommodates) AS accommodates,
    TRY_TO_NUMBER(bathrooms, 4, 1) AS bathrooms,
    bathrooms_text,
    TRY_TO_NUMBER(bedrooms) AS bedrooms,
    TRY_TO_NUMBER(beds) AS beds,

    -- price and stay rules
    {{ clean_price('price') }} AS price,
    TRY_TO_NUMBER(minimum_nights) AS minimum_nights,
    TRY_TO_NUMBER(maximum_nights) AS maximum_nights,
    {{ to_boolean_tf('instant_bookable') }} AS is_instant_bookable,
    {{ to_boolean_tf('has_availability') }} AS has_availability,
    TRY_TO_NUMBER(availability_30) AS availability_30,
    TRY_TO_NUMBER(availability_365) AS availability_365,
    license,

    -- reviews summary (as published in this snapshot)
    TRY_TO_NUMBER(number_of_reviews) AS number_of_reviews,
    TRY_TO_NUMBER(number_of_reviews_ltm) AS number_of_reviews_ltm,
    TRY_TO_DATE(first_review) AS first_review_date,
    TRY_TO_DATE(last_review) AS last_review_date,
    TRY_TO_NUMBER(review_scores_rating, 4, 2) AS review_scores_rating,
    TRY_TO_NUMBER(review_scores_accuracy, 4, 2) AS review_scores_accuracy,
    TRY_TO_NUMBER(review_scores_cleanliness, 4, 2) AS review_scores_cleanliness,
    TRY_TO_NUMBER(review_scores_checkin, 4, 2) AS review_scores_checkin,
    TRY_TO_NUMBER(review_scores_communication, 4, 2) AS review_scores_communication,
    TRY_TO_NUMBER(review_scores_location, 4, 2) AS review_scores_location,
    TRY_TO_NUMBER(review_scores_value, 4, 2) AS review_scores_value,
    TRY_TO_NUMBER(reviews_per_month, 6, 2) AS reviews_per_month,

    -- scrape metadata
    TRY_TO_DATE(last_scraped) AS last_scraped_date,
    TRY_TO_NUMBER(scrape_id) AS scrape_id,
    _loaded_at AS loaded_at

FROM deduplicated
