-- =====================================================================
-- 01_setup.sql : one-time Snowflake setup for the Airbnb ELT project
-- Run in Snowsight as the trial's admin user, top to bottom.
-- DO NOT RUN YET. We run this at the start of Phase 2, the day you
-- activate the 30-day trial, so no trial days are wasted.
-- Safe to rerun: every statement uses IF NOT EXISTS or is a GRANT.
-- The trial account MUST be on AWS, region Asia Pacific (Mumbai)
-- (ap-south-1), the same region as the S3 bucket.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Cost guard first: a resource monitor caps credits per month.
--    Only ACCOUNTADMIN can create resource monitors.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS AIRBNB_RM
  WITH CREDIT_QUOTA = 20            -- far above what this project needs
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
       ON 50 PERCENT DO NOTIFY
       ON 90 PERCENT DO NOTIFY
       ON 100 PERCENT DO SUSPEND;   -- stops the warehouse after running queries finish

-- ---------------------------------------------------------------------
-- 2. Compute: the smallest warehouse, asleep unless a query needs it.
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS AIRBNB_WH
  WAREHOUSE_SIZE = 'XSMALL'         -- 1 credit per hour while running
  AUTO_SUSPEND = 60                 -- sleep after 60 idle seconds
  AUTO_RESUME = TRUE                -- wake up automatically on the next query
  INITIALLY_SUSPENDED = TRUE        -- do not start burning credits at creation
  COMMENT = 'Airbnb ELT portfolio project';

USE ROLE ACCOUNTADMIN;
ALTER WAREHOUSE AIRBNB_WH SET RESOURCE_MONITOR = AIRBNB_RM;

-- ---------------------------------------------------------------------
-- 3. Storage: one database for the project.
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS AIRBNB COMMENT = 'Airbnb ELT: RAW, SILVER, GOLD, SNAPSHOTS';

-- ---------------------------------------------------------------------
-- 4. Access: one role that loads RAW and runs dbt.
--    USERADMIN creates roles and users; SYSADMIN owns objects.
-- ---------------------------------------------------------------------
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS TRANSFORMER COMMENT = 'Loads RAW with COPY INTO and builds dbt models';

-- Role hierarchy: SYSADMIN inherits TRANSFORMER, so admins can see its objects.
GRANT ROLE TRANSFORMER TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
GRANT USAGE, OPERATE ON WAREHOUSE AIRBNB_WH TO ROLE TRANSFORMER;
GRANT USAGE, CREATE SCHEMA ON DATABASE AIRBNB TO ROLE TRANSFORMER;

-- ---------------------------------------------------------------------
-- 5. Schemas, created BY the TRANSFORMER role so it owns them
--    (owner can create tables and views inside without extra grants).
-- ---------------------------------------------------------------------
-- Give the admin user the role for this session so we can switch to it.
SET my_user = CURRENT_USER();
USE ROLE USERADMIN;
GRANT ROLE TRANSFORMER TO USER IDENTIFIER($my_user);

USE ROLE TRANSFORMER;
USE WAREHOUSE AIRBNB_WH;
CREATE SCHEMA IF NOT EXISTS AIRBNB.RAW       COMMENT = 'Bronze: files loaded as-is by COPY INTO';
CREATE SCHEMA IF NOT EXISTS AIRBNB.SILVER    COMMENT = 'Silver: cleaned, typed, deduplicated dbt models';
CREATE SCHEMA IF NOT EXISTS AIRBNB.SNAPSHOTS COMMENT = 'dbt snapshots (SCD Type 2 history)';
CREATE SCHEMA IF NOT EXISTS AIRBNB.GOLD      COMMENT = 'Gold: star schema and marts';

-- ---------------------------------------------------------------------
-- 6. Service user for dbt and the pipeline runner.
--    TYPE = SERVICE: no password, no MFA prompt, key-pair login only.
--    Generate the key pair on your laptop first (Phase 2 shows how) and
--    paste ONLY the public key body below. The private key never leaves
--    your laptop and never enters git.
-- ---------------------------------------------------------------------
USE ROLE USERADMIN;
CREATE USER IF NOT EXISTS DBT_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = TRANSFORMER
  DEFAULT_WAREHOUSE = AIRBNB_WH
  DEFAULT_NAMESPACE = AIRBNB.SILVER
  RSA_PUBLIC_KEY = '<PASTE_PUBLIC_KEY_BODY_HERE>'
  COMMENT = 'dbt and pipeline runner for the Airbnb ELT project';

GRANT ROLE TRANSFORMER TO USER DBT_SVC;

-- ---------------------------------------------------------------------
-- 7. Check
-- ---------------------------------------------------------------------
USE ROLE TRANSFORMER;
SHOW SCHEMAS IN DATABASE AIRBNB;
SHOW WAREHOUSES LIKE 'AIRBNB_WH';

-- Storage integration, file format, stage and RAW tables come in Phase 2
-- (02_integration_and_stage.sql), because they need the AWS role ARN.
