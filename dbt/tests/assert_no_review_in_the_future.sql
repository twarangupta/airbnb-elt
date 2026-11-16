-- Singular test: returns the rows that break the rule; the test passes when
-- it returns nothing. A review cannot be dated after today.
-- (Reviews CAN be dated after the snapshot date: a scrape runs over several
-- days; 6,173 reviews in the 2026-06-19 files are dated up to 2026-06-30.)
SELECT
    review_id,
    review_date
FROM {{ ref('stg_reviews') }}
WHERE review_date > CURRENT_DATE()
