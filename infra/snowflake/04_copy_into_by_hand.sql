-- =====================================================================
-- 04_copy_into_by_hand.sql : learn COPY INTO step by step in Snowsight.
-- The pipeline itself uses ingestion/load_raw.py, which builds the same
-- statements for all three tables. Run these once by hand to see each
-- piece working. Uses the smallest file (calendar has 5 columns).
-- =====================================================================

USE ROLE TRANSFORMER;
USE WAREHOUSE AIRBNB_WH;
USE SCHEMA AIRBNB.RAW;

-- 1. Peek at the file through the stage without loading anything.
--    $1, $2, ... are the columns by position.
SELECT
    T.$1 AS LISTING_ID,
    T.$2 AS CALENDAR_DATE,
    T.$3 AS AVAILABLE,
    METADATA$FILENAME AS SOURCE_FILE,
    METADATA$FILE_ROW_NUMBER AS SOURCE_ROW
FROM @LONDON_STAGE/snapshot_date=2026-06-19/calendar.csv.gz AS T
ORDER BY SOURCE_ROW
LIMIT 10;

-- 2. Dry run: count the records Snowflake parses in the file, without
--    loading anything. It should equal the row-count stored on the S3
--    object at landing (33,871,636 for this file). A parse error fails here.
--    (COPY ... VALIDATION_MODE = RETURN_ERRORS is the other dry-run tool,
--    but it cannot be combined with the SELECT transformation used in 3.)
SELECT COUNT(*) AS ROWS_IN_FILE
FROM @LONDON_STAGE/snapshot_date=2026-06-19/calendar.csv.gz;

-- 3. The real load: positional columns plus metadata columns.
--    _loaded_at is filled by its DEFAULT.
COPY INTO CALENDAR (
    LISTING_ID, DATE, AVAILABLE, MINIMUM_NIGHTS, MAXIMUM_NIGHTS,
    _SOURCE_FILE, _SOURCE_ROW, _SNAPSHOT_DATE
)
FROM (
    SELECT
        T.$1,
        T.$2,
        T.$3,
        T.$4,
        T.$5,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        '2026-06-19'::DATE
    FROM @LONDON_STAGE/snapshot_date=2026-06-19/ AS T
)
FILES = ('calendar.csv.gz')
ON_ERROR = ABORT_STATEMENT;   -- all or nothing: one bad row stops the load

-- 4. Run step 3 again: Snowflake answers "0 files processed" because its
--    load metadata remembers this file (path + checksum) for 64 days.

-- 5. Load history for the table.
SELECT
    FILE_NAME,
    STATUS,
    ROW_COUNT,
    ROW_PARSED,
    FIRST_ERROR_MESSAGE,
    LAST_LOAD_TIME
FROM INFORMATION_SCHEMA.LOAD_HISTORY
WHERE TABLE_NAME = 'CALENDAR'
ORDER BY LAST_LOAD_TIME DESC;

-- 6. Reconcile with the row-count stored on the S3 object at landing.
SELECT
    _SNAPSHOT_DATE,
    COUNT(*) AS ROWS_LOADED
FROM CALENDAR
GROUP BY _SNAPSHOT_DATE;

-- When you stop for the day:
ALTER WAREHOUSE AIRBNB_WH SUSPEND;
