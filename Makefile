# One place for every command in this project.
# Usage: make <target>   (run `make help` to list targets)
# Grows phase by phase; Phase 6 adds `make all` (land, COPY INTO, dbt build).

# Load .env (gitignored) and export every value to child processes (dbt, python).
-include .env
export

# The virtual environment lives OUTSIDE OneDrive so OneDrive does not try to
# sync thousands of library files. Override with: make VENV=path/to/venv ...
VENV ?= C:/dev/venvs/airbnb-elt
PY   := $(VENV)/Scripts/python.exe
DBT  := $(VENV)/Scripts/dbt.exe
DBT_FLAGS := --project-dir dbt --profiles-dir dbt
SQL_PATHS := infra/snowflake dbt/models dbt/snapshots dbt/tests dbt/analyses
PY_PATHS  := ingestion scripts tests

# Inside Airbnb London snapshots used by this project (decision D33).
# Load OLD first, then NEW, so Phase 4 snapshots see real changes.
SNAPSHOT_OLD ?= 2026-06-19
SNAPSHOT_NEW ?= 2026-09-17

.PHONY: help venv install deps parse debug clean lint pylint test check-secrets ci land land-old land-new

help:            ## List targets
	@grep -E '^[a-z_-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/ :/'

venv:            ## Create the Python 3.11 virtual environment (needs uv)
	uv venv $(VENV) --python 3.11

install:         ## Install pinned Python packages into the venv
	VIRTUAL_ENV=$(VENV) uv pip install --only-binary :all: -r requirements-dev.txt

deps:            ## Download dbt packages (dbt_utils) into dbt/dbt_packages
	$(DBT) deps $(DBT_FLAGS)

parse:           ## Check the dbt project compiles (no Snowflake connection needed)
	$(DBT) parse $(DBT_FLAGS)

debug:           ## Test the dbt connection to Snowflake (works from Phase 2)
	$(DBT) debug $(DBT_FLAGS)

clean:           ## Delete dbt build output
	$(DBT) clean $(DBT_FLAGS)

lint:            ## Lint SQL with sqlfluff (same paths as CI)
	$(VENV)/Scripts/sqlfluff.exe lint $(SQL_PATHS)

pylint:          ## Lint Python with ruff (same paths as CI)
	$(VENV)/Scripts/ruff.exe check $(PY_PATHS)

test:            ## Run Python unit tests (no network, no AWS)
	$(PY) -m pytest -q tests

check-secrets:   ## Fail if a secret-looking file or value is tracked by git
	$(PY) scripts/check_secrets.py

land:            ## Land one snapshot in S3: make land SNAPSHOT_DATE=YYYY-MM-DD
	$(PY) ingestion/land_files.py --snapshot-date $(SNAPSHOT_DATE)

land-old:        ## Land the OLD London snapshot (Phase 1)
	$(MAKE) land SNAPSHOT_DATE=$(SNAPSHOT_OLD)

land-new:        ## Land the NEW London snapshot (Phase 4)
	$(MAKE) land SNAPSHOT_DATE=$(SNAPSHOT_NEW)

ci:              ## Run the same checks as GitHub Actions, locally
	$(MAKE) check-secrets lint pylint test deps
	SNOWFLAKE_ACCOUNT=dummy-account SNOWFLAKE_PRIVATE_KEY_PATH=/tmp/dummy_key.p8 $(DBT) parse $(DBT_FLAGS) --target ci
