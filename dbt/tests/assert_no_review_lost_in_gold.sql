-- Singular test: every Silver review must reach fct_reviews exactly once.
-- The point-in-time joins are LEFT JOINs with an unknown member, so a
-- review can neither drop out (no matching version) nor be duplicated
-- (overlapping versions). Returns a row when the counts differ.
WITH counts AS (
    SELECT
        (SELECT COUNT(*) FROM {{ ref('stg_reviews') }}) AS silver_reviews,
        (SELECT COUNT(*) FROM {{ ref('fct_reviews') }}) AS gold_reviews
)

SELECT
    silver_reviews,
    gold_reviews
FROM counts
WHERE silver_reviews <> gold_reviews
