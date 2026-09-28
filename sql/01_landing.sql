-- 01_landing.sql
-- Load the Parquet files written by src/pipeline/landing.py into DuckDB tables so the
-- database is self-contained. Values are unchanged strings in the sources' own columns.
-- Variables set by the build: landing_dir, internal_dir.

CREATE SCHEMA IF NOT EXISTS landing;
CREATE SCHEMA IF NOT EXISTS internal;

CREATE OR REPLACE TABLE landing.nhd                    AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/nhd.parquet');
CREATE OR REPLACE TABLE landing.maay_district_lists    AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/maay_district_lists.parquet');
CREATE OR REPLACE TABLE landing.maay_live_search       AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/maay_live_search.parquet');
CREATE OR REPLACE TABLE landing.maay_pmr_packages      AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/maay_pmr_packages.parquet');
CREATE OR REPLACE TABLE landing.pincode                AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/pincode.parquet');
CREATE OR REPLACE TABLE landing.lgd_states             AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/lgd_states.parquet');
CREATE OR REPLACE TABLE landing.lgd_districts          AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/lgd_districts.parquet');
CREATE OR REPLACE TABLE landing.rs_govt_hospitals_beds AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/rs_govt_hospitals_beds.parquet');
CREATE OR REPLACE TABLE landing.rs_pmjay_empanelled    AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/rs_pmjay_empanelled.parquet');
CREATE OR REPLACE TABLE landing.rs_nabh_accredited     AS SELECT * FROM read_parquet(getvariable('landing_dir') || '/rs_nabh_accredited.parquet');

-- NABH: research and verification only. Never joined into exported tables (NABH terms).
CREATE OR REPLACE TABLE internal.nabh_landing          AS SELECT * FROM read_parquet(getvariable('internal_dir') || '/nabh.parquet');
