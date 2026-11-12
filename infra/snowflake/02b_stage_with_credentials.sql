-- =====================================================================
-- 02b_stage_with_credentials.sql : FALLBACK (Plan B) for Part C of 02.
-- Use ONLY if the storage integration cannot assume the AWS role
-- (LIST @LONDON_STAGE fails with an AssumeRole / access error).
--
-- The key belongs to IAM user airbnb-elt-snowflake-reader, which can only
-- Get and List under raw/ in one bucket. Paste it into the Snowsight
-- worksheet ONLY, run, then close the worksheet without saving.
-- NEVER commit the real values; this file keeps the placeholders.
-- =====================================================================

USE ROLE TRANSFORMER;
USE WAREHOUSE AIRBNB_WH;
USE SCHEMA AIRBNB.RAW;

-- Replaces a stage of the same name created by 02 (Plan A), if any.
CREATE OR REPLACE STAGE LONDON_STAGE
  URL = 's3://airbnb-elt-raw-tg-7060/raw/london/'
  CREDENTIALS = (
    AWS_KEY_ID = '<PASTE_IN_SNOWSIGHT_ONLY>'
    AWS_SECRET_KEY = '<PASTE_IN_SNOWSIGHT_ONLY>'
  )
  FILE_FORMAT = FF_INSIDE_AIRBNB_CSV
  COMMENT = 'Inside Airbnb London snapshots (Plan B: read-only IAM user key)';

-- Check: 3 files under snapshot_date=2026-06-19/, never hello.txt.
LIST @LONDON_STAGE;
