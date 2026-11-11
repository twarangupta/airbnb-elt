-- =====================================================================
-- 02_integration_and_stage.sql : let Snowflake read our S3 raw files.
-- Run in Snowsight AFTER 01_setup.sql, in three parts (see comments),
-- because the AWS role and Snowflake integration need each other's IDs.
--
-- Bucket: airbnb-elt-raw-tg-7060 (ap-southeast-2, Sydney)
-- Stage points at raw/london/ ONLY, so the Phase 0 test file
-- raw/_connection_test/hello.txt is never visible to COPY INTO.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Part A (ACCOUNTADMIN). Before this, in AWS create the read policy
-- (infra/aws/iam_policy_snowflake_read.json) and the role
-- airbnb-elt-snowflake-role, and paste the role ARN below.
-- A storage integration stores NO AWS keys: Snowflake's own AWS user
-- assumes our role and gets short-lived credentials.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION IF NOT EXISTS AIRBNB_S3_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = '<PASTE_ROLE_ARN: arn:aws:iam::<account-id>:role/airbnb-elt-snowflake-role>'
  STORAGE_ALLOWED_LOCATIONS = ('s3://airbnb-elt-raw-tg-7060/raw/')
  COMMENT = 'Read-only access to the Airbnb ELT raw landing zone';

-- Copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from the
-- output into infra/aws/iam_trust_policy_snowflake.template.json and set it
-- as the role's trust policy in AWS. (Both values are identifiers, not secrets.)
DESC INTEGRATION AIRBNB_S3_INT;

-- Only the role that loads data may use the integration.
GRANT USAGE ON INTEGRATION AIRBNB_S3_INT TO ROLE TRANSFORMER;

-- ---------------------------------------------------------------------
-- Part B (TRANSFORMER). File format: how to read the CSV files.
-- ---------------------------------------------------------------------
USE ROLE TRANSFORMER;
USE WAREHOUSE AIRBNB_WH;
USE SCHEMA AIRBNB.RAW;

CREATE FILE FORMAT IF NOT EXISTS FF_INSIDE_AIRBNB_CSV
  TYPE = CSV
  COMPRESSION = GZIP                    -- files stay .csv.gz in S3
  SKIP_HEADER = 1                       -- first line holds column names
  FIELD_DELIMITER = ','
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'    -- quoted fields may contain commas and line breaks
  MULTI_LINE = TRUE                     -- a quoted review comment can span several lines
  ESCAPE_UNENCLOSED_FIELD = NONE        -- backslashes in text are just text
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE -- strict: unexpected field counts are errors (behaviour checked in Phase 2)
  EMPTY_FIELD_AS_NULL = TRUE            -- ,, becomes NULL
  TRIM_SPACE = FALSE                    -- keep text exactly as received
  ENCODING = 'UTF8'
  COMMENT = 'Inside Airbnb detailed CSV files (gzip, quoted, multi-line)';

-- ---------------------------------------------------------------------
-- Part C (TRANSFORMER). External stage: a named pointer to raw/london/.
-- ---------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS LONDON_STAGE
  URL = 's3://airbnb-elt-raw-tg-7060/raw/london/'
  STORAGE_INTEGRATION = AIRBNB_S3_INT
  FILE_FORMAT = FF_INSIDE_AIRBNB_CSV
  COMMENT = 'Inside Airbnb London snapshots, one folder per snapshot_date';

-- Check: should list 3 files per landed snapshot, and never hello.txt.
LIST @LONDON_STAGE;
