{#
  Date dimension: one row per calendar day from 2009-01-01 (first review)
  to 2027-12-31 (after the last calendar date, 2027-09-22).
  date_key is an integer YYYYMMDD, the key facts use.
#}
{{ config(materialized='table') }}

WITH spine AS (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="CAST('2009-01-01' AS DATE)",
        end_date="CAST('2028-01-01' AS DATE)"
    ) }}

)

SELECT
    TO_NUMBER(TO_CHAR(date_day, 'YYYYMMDD')) AS date_key,
    CAST(date_day AS DATE) AS calendar_date,
    YEAR(date_day) AS year,
    QUARTER(date_day) AS quarter,
    MONTH(date_day) AS month,
    MONTHNAME(date_day) AS month_name,
    CAST(DATE_TRUNC('month', date_day) AS DATE) AS month_start_date,
    DAYOFWEEKISO(date_day) AS day_of_week,
    DAYNAME(date_day) AS day_name,
    DAYOFWEEKISO(date_day) IN (6, 7) AS is_weekend
FROM spine
