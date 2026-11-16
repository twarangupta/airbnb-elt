{#
  Silver reviews: one row per review (review_id), typed and cleaned.

  INCREMENTAL. Every Inside Airbnb snapshot is a FULL dump that repeats all
  past reviews. So on each run we only look at RAW rows loaded after the last
  run (_loaded_at), and of those only reviews we have never seen. A review
  keeps the snapshot it first appeared in (first_seen_snapshot_date).
  Rerunning with no new RAW load processes 0 rows.
  dbt build --full-refresh rebuilds the table from all of RAW.
#}
{{
    config(
        materialized='incremental',
        unique_key='review_id',
        incremental_strategy='merge',
        on_schema_change='fail'
    )
}}

WITH source AS (

    SELECT * FROM {{ source('raw', 'reviews') }}

    {% if is_incremental() %}
        -- only RAW rows loaded since the last successful run of this model,
        -- and only reviews that are not in the table yet
        WHERE
            _loaded_at > (SELECT MAX(existing.loaded_at) FROM {{ this }} AS existing)
            AND TRY_TO_NUMBER(id) NOT IN (SELECT seen.review_id FROM {{ this }} AS seen)
    {% endif %}

),

first_seen AS (

    -- within one batch a review can appear in several snapshots; keep the oldest
    SELECT *
    FROM source
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY _snapshot_date ASC, _loaded_at ASC
    ) = 1

),

cleaned AS (

    SELECT
        TRY_TO_NUMBER(id) AS review_id,
        TRY_TO_NUMBER(listing_id) AS listing_id,
        TRY_TO_DATE(date) AS review_date,
        TRY_TO_NUMBER(reviewer_id) AS reviewer_id,
        reviewer_name,
        -- Inside Airbnb encodes many line breaks as <br/>; turn them back into newlines
        REGEXP_REPLACE(comments, '<br\\s*/?>', '\n', 1, 0, 'i') AS comments,
        _snapshot_date AS first_seen_snapshot_date,
        _loaded_at AS loaded_at
    FROM first_seen

)

SELECT
    review_id,
    listing_id,
    review_date,
    reviewer_id,
    reviewer_name,
    comments,
    LENGTH(comments) AS comment_length,
    first_seen_snapshot_date,
    loaded_at
FROM cleaned
