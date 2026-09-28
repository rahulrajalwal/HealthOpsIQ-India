-- 02_staging.sql
-- Typed staging tables: source placeholders ("0", "NA", ...) become NULL, text is trimmed,
-- raw values are kept in *_raw columns. Nothing is standardised or joined here.

CREATE SCHEMA IF NOT EXISTS stg;
CREATE SCHEMA IF NOT EXISTS ref;

-- The NHD writes missing values as "0" or "NA" and line breaks as a literal "\n"
-- (backslash + n; DuckDB string literals do not interpret escapes, so '\n' is those two characters).
CREATE OR REPLACE MACRO is_placeholder(x) AS lower(trim(CAST(x AS VARCHAR))) IN ('', '0', 'na', 'n/a', 'nil', 'none', 'null', '-', '--', 'not available', '.');
CREATE OR REPLACE MACRO raw_value(x) AS CASE WHEN x IS NULL OR is_placeholder(x) THEN NULL ELSE CAST(x AS VARCHAR) END;
CREATE OR REPLACE MACRO clean_text(x) AS NULLIF(trim(regexp_replace(replace(replace(raw_value(x), chr(10), ' '), '\n', ' '), '\s+', ' ', 'g')), '');
CREATE OR REPLACE MACRO pincode_in(x) AS NULLIF(regexp_extract(coalesce(CAST(x AS VARCHAR), ''), '(^|[^0-9])([1-9][0-9]{5})([^0-9]|$)', 2), '');

-- National Hospital Directory (all rows; the pilot filter is applied in 04).
CREATE OR REPLACE TABLE stg.nhd AS
SELECT
    'nhd'                                                  AS source_key,
    Sr_No                                                  AS source_record_id,
    clean_text(Hospital_Name)                              AS name_raw,
    clean_text(State)                                      AS state_source,
    clean_text(District)                                   AS district_source,
    clean_text(Subdistrict)                                AS subdistrict_source,
    clean_text(Pincode)                                    AS pincode_raw,
    CASE WHEN regexp_full_match(clean_text(Pincode), '[1-9][0-9]{5}') THEN clean_text(Pincode) END AS pincode,
    clean_text(Address_Original_First_Line)                AS address_raw,
    clean_text(Location)                                   AS location_raw,
    TRY_CAST(NULLIF(_latitude, '') AS DOUBLE)              AS latitude_raw,
    TRY_CAST(NULLIF(_longitude, '') AS DOUBLE)             AS longitude_raw,
    clean_text(Hospital_Category)                          AS ownership_raw,
    clean_text(Hospital_Care_Type)                         AS facility_type_raw,
    clean_text(Discipline_Systems_of_Medicine)             AS system_of_medicine_raw,
    raw_value(Specialties)                                 AS specialties_raw,
    clean_text(Facilities)                                 AS facilities_raw,
    trim(Total_Num_Beds)                                   AS beds_raw,
    TRY_CAST(clean_text(Total_Num_Beds) AS INTEGER)        AS beds_reported,
    clean_text(Emergency_Services)                         AS emergency_raw,
    clean_text(Website)                                    AS website,
    clean_text(State_ID)                                   AS state_census2011_code,
    clean_text(District_ID)                                AS district_census2011_code
FROM landing.nhd;

-- MAA Yojana district lists (private, state-government and central-government PDFs).
CREATE OR REPLACE TABLE stg.maay_list AS
SELECT
    'maay_district_lists'                                  AS source_key,
    clean_text(_hospital_code) || '|' || coalesce(clean_text(coalesce(NULLIF("TOKEN ID", ''), NULLIF(TOKEN_ID, ''))), 'no-token') AS source_record_id,
    clean_text(_hospital_code)                             AS hospital_code,
    clean_text(coalesce(NULLIF("TOKEN ID", ''), NULLIF(TOKEN_ID, ''))) AS token_id,
    clean_text("HOSPITAL NAME")                            AS name_raw,
    clean_text("HOSPITAL ADDRESS")                         AS address_raw,
    clean_text("DISTRICT NAME")                            AS district_source,
    _list_category                                         AS list_category,
    raw_value(SPECIALITY)                                  AS specialties_raw,
    clean_text("NABH STATUS")                              AS nabh_status_raw,
    trim(BEDSTRENGTH)                                      AS beds_raw,
    TRY_CAST(clean_text(BEDSTRENGTH) AS INTEGER)           AS beds_declared,
    clean_text(coalesce(NULLIF("GOVT TYPE", ''), NULLIF(GOVT_TYPE, ''))) AS govt_type_raw,
    pincode_in("HOSPITAL ADDRESS")                         AS pincode_in_address,
    NULLIF(_parse_warning, '')                             AS parse_warning,
    NULLIF(_privacy_scrubbed, '')                          AS privacy_scrubbed,
    _source_file                                           AS source_file,
    _layout                                                AS parse_layout
FROM landing.maay_district_lists;

-- MAA Yojana live-search snapshot (manual searches in the official page).
CREATE OR REPLACE TABLE stg.maay_live AS
SELECT
    'maay_live_search'                                     AS source_key,
    _snapshot_file || '#' || district || '#' || sr         AS source_record_id,
    clean_text(district)                                   AS district_source,
    clean_text(hospital_type)                              AS ownership_raw,
    clean_text(hospital_name)                              AS name_raw,
    clean_text(is_suspended)                               AS suspended_raw,
    clean_text(hospital_address)                           AS address_raw,
    clean_text(_speciality_filter)                         AS specialty_filter_raw,
    CAST(replace(_retrieved_at_utc, 'Z', '') AS TIMESTAMP) AS retrieved_at_utc,
    pincode_in(hospital_address)                           AS pincode_in_address
FROM landing.maay_live_search;

-- India Post pincode directory (post offices).
CREATE OR REPLACE TABLE stg.india_post AS
SELECT
    pincode,
    clean_text(officename)                                 AS office_name,
    clean_text(officetype)                                 AS office_type,
    clean_text(divisionname)                               AS division_name,
    clean_text(district)                                   AS postal_district,
    clean_text(statename)                                  AS postal_state,
    TRY_CAST(latitude AS DOUBLE)                           AS latitude,
    TRY_CAST(longitude AS DOUBLE)                          AS longitude
FROM landing.pincode;

-- LGD states and districts.
CREATE OR REPLACE TABLE stg.lgd_state AS
SELECT TRY_CAST(state_code AS INTEGER) AS state_code_lgd, clean_text(state_name_english) AS state_name,
       clean_text(state_or_ut) AS state_or_ut, clean_text(state_census2011_code) AS state_census2011_code
FROM landing.lgd_states;

CREATE OR REPLACE TABLE stg.lgd_district AS
SELECT TRY_CAST(state_code AS INTEGER) AS state_code_lgd, clean_text(state_name_english) AS state_name,
       TRY_CAST(district_code AS INTEGER) AS district_code_lgd, clean_text(district_name_english) AS district_name,
       clean_text(district_census2011_code) AS district_census2011_code
FROM landing.lgd_districts;

-- Official state-level context (Rajya Sabha answers), long format.
CREATE OR REPLACE MACRO num(x) AS TRY_CAST(replace(CAST(x AS VARCHAR), ',', '') AS DOUBLE);
CREATE OR REPLACE TABLE stg.state_indicator AS
SELECT 'rs_govt_hospitals_beds' AS source_key, clean_text("State/UT/Division") AS state_source, indicator, value, clean_text("Reference Period") AS reference_period
FROM landing.rs_govt_hospitals_beds,
     LATERAL (VALUES
        ('govt_hospitals_rural', num("Rural Hosital (Government ) - Number")),
        ('govt_beds_rural',      num("Rural Hosital (Government ) - Beds")),
        ('govt_hospitals_urban', num("Urban Hospitals (Government ) - Number")),
        ('govt_beds_urban',      num("Urban Hospitals (Government ) - Beds")),
        ('govt_hospitals_total', num("Total Hospital (Government ) - Number")),
        ('govt_beds_total',      num("Total Hospital (Government ) - Beds"))
     ) AS v(indicator, value)
UNION ALL
SELECT 'rs_pmjay_empanelled', clean_text("State/UT"), 'pmjay_empanelled_hospitals',
       num("Number of Empanelled Hospitals under PMJAY (as on 01-03-2025)"), 'as on 01-03-2025'
FROM landing.rs_pmjay_empanelled
UNION ALL
SELECT 'rs_nabh_accredited', clean_text("State/UT"), 'nabh_accredited_hospitals',
       num("No. of NABH Accredited Hospitals"), 'as on 31-12-2024'
FROM landing.rs_nabh_accredited;

-- Terminology evidence: package names displayed for the MAA Yojana 'PMR -Phase 4' speciality.
CREATE OR REPLACE TABLE ref.pmr_package AS
SELECT speciality_raw, package_value, package_name_as_displayed,
       CAST(replace(retrieved_at_utc, 'Z', '') AS TIMESTAMP) AS retrieved_at_utc,
       regexp_matches(package_name_as_displayed, 'rehab', 'i')              AS mentions_rehabilitation,
       regexp_matches(package_name_as_displayed, 'physio', 'i')             AS mentions_physiotherapy,
       regexp_matches(package_name_as_displayed, 'go?v[t.]*\s*\.?\s*reserve|- gov', 'i') AS marked_government_reserve
FROM landing.maay_pmr_packages;

-- NABH (internal only).
CREATE OR REPLACE TABLE internal.nabh AS
SELECT clean_text(name) AS name_raw, clean_text(address) AS address_raw, clean_text(_city) AS city_parsed,
       clean_text(_state) AS state_parsed, NULLIF(_pincode, '') AS pincode, clean_text(accreditation_no) AS accreditation_no,
       clean_text(status_badge) AS status_badge, NULLIF(programme_code, '') AS programme_code,
       TRY_CAST(latitude AS DOUBLE) AS latitude, TRY_CAST(longitude AS DOUBLE) AS longitude, _retrieved_at_utc AS retrieved_at_utc
FROM internal.nabh_landing;
