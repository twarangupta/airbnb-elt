-- =====================================================================
-- 02b_stage_with_credentials.sql : FALLBACK (Plan B) for Part C of 02.
-- Used because the storage integration could not assume the AWS role:
--   "User: arn:aws:iam::<snowflake>:user/... is not authorized to perform:
--    sts:AssumeRole on resource: ...:role/airbnb-elt-snowflake-role"
-- (AWS free-plan account; Snowflake runs in another region.)
--
-- The key belongs to IAM user airbnb-elt-snowflake-reader, which can only
-- Get and List under raw/ in one bucket. Paste it into the Snowsight
-- worksheet ONLY, run, then delete it from the worksheet.
-- NEVER commit the real values; this file keeps the placeholders.
--
-- Runs as SYSADMIN (the admin login cannot switch to TRANSFORMER on this
-- trial); ownership of the stage is then handed to TRANSFORMER, which the
-- loader (DBT_SVC) uses.
-- =====================================================================

USE ROLE SYSADMIN;

-- Replaces the Plan A stage of the same name (created by 02, Part C).
CREATE OR REPLACE STAGE AIRBNB.RAW.LONDON_STAGE
  URL = 's3://airbnb-elt-raw-tg-7060/raw/london/'
  CREDENTIALS = (
    AWS_KEY_ID = '<PASTE_IN_SNOWSIGHT_ONLY>'
    AWS_SECRET_KEY = '<PASTE_IN_SNOWSIGHT_ONLY>'
  )
  FILE_FORMAT = AIRBNB.RAW.FF_INSIDE_AIRBNB_CSV
  COMMENT = 'Inside Airbnb London snapshots (Plan B: read-only IAM user key)';

GRANT OWNERSHIP ON STAGE AIRBNB.RAW.LONDON_STAGE TO ROLE TRANSFORMER;

-- Check: 3 files under snapshot_date=2026-06-19/, never hello.txt.
LIST @AIRBNB.RAW.LONDON_STAGE;
