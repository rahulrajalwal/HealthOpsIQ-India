-- 07_marts.sql
-- Analytical tables for Power BI and the portal, shaped as a star schema:
--   dimensions  mart.hospital, mart.dim_state, core.dim_specialty, mart.dim_attribute, mart.source
--   facts       mart.hospital_attribute, mart.hospital_specialty, mart.hospital_source_record,
--               mart.hospital_possible_match, mart.state_context, mart.pmr_package
-- Every headline value carries its source and date. NABH (internal schema) is deliberately not referenced.

CREATE SCHEMA IF NOT EXISTS mart;

CREATE OR REPLACE MACRO source_label(k) AS CASE k
    WHEN 'nhd' THEN 'National Hospital Directory'
    WHEN 'maay_district_lists' THEN 'MAA Yojana district list'
    WHEN 'maay_live_search' THEN 'MAA Yojana live search'
    ELSE k END;

-- Short source names for chart labels (the full names are in mart.source).
CREATE OR REPLACE MACRO source_short(k) AS CASE k
    WHEN 'nhd' THEN 'NHD'
    WHEN 'maay_district_lists' THEN 'Scheme list'
    WHEN 'maay_live_search' THEN 'Scheme search'
    ELSE k END;

-- States and UTs (LGD): the state dimension shared by hospitals and state-level context.
CREATE OR REPLACE TABLE mart.dim_state AS
SELECT state_code_lgd, state_name,
       CASE state_or_ut WHEN 'S' THEN 'State' WHEN 'U' THEN 'Union Territory' ELSE state_or_ut END AS state_or_ut
FROM stg.lgd_state;

-- Attributes that evidence rows can describe, in display order.
CREATE OR REPLACE TABLE mart.dim_attribute AS
SELECT * FROM (VALUES
    ('source_listing', 'Listed in source', 0, 'Listing',
     'Which official source lists the hospital: one value per source record.'),
    ('ownership', 'Ownership', 1, 'Identity',
     'Public or Private as the source states it (NHD category, scheme list category, live-search hospital type).'),
    ('facility_type', 'Facility type', 2, 'Identity',
     'NHD care type (2016), standardised. Recorded for few hospitals.'),
    ('government_level', 'Government level', 3, 'Identity',
     'Government of Rajasthan or Government of India, from the scheme''s state-government list.'),
    ('scheme_empanelment', 'MAA Yojana empanelment', 4, 'Scheme',
     'Presence in a MAA Yojana district list (2021-22) or hospital search (2026).'),
    ('scheme_suspension_status', 'MAA Yojana suspension status', 5, 'Scheme',
     'IS_SUSPENDED flag of the MAA Yojana hospital search; only for hospitals the search returned.'),
    ('nabh_status_scheme_reported', 'NABH status (as reported in scheme list)', 6, 'Accreditation (reported by scheme)',
     'NABH status as written in the MAA Yojana list. Not taken from NABH.'),
    ('beds_declared_to_scheme', 'Beds (declared to scheme)', 7, 'Capacity',
     'Bed strength declared to MAA Yojana (BEDSTRENGTH). Zero is treated as missing.'),
    ('specialty', 'Speciality', 8, 'Services',
     'Speciality as the source names it; pilot specialities also carry a standard name.')
) AS t(attribute, attribute_label, sort_order, attribute_group, description);

-- Pending candidate matches, both directions (hospital -> the hospital it may duplicate).
CREATE OR REPLACE TABLE mart.hospital_possible_match_keys AS
SELECT hospital_key_a AS canonical_hospital_key, hospital_key_b AS possible_match_key, record_b AS other_record, rule, combined_score, pincode_relation
FROM core.hospital_match_candidate
UNION ALL
SELECT hospital_key_b, hospital_key_a, record_a, rule, combined_score, pincode_relation
FROM core.hospital_match_candidate;

-- One row per hospital. "Latest" = the most recent dated evidence; the source and date travel with it.
CREATE OR REPLACE TABLE mart.hospital AS
WITH ev AS (SELECT * FROM core.fact_hospital_evidence),
own AS (
    SELECT canonical_hospital_key,
           arg_max(value_std, as_of_date)                          AS ownership,
           arg_max(source_label(source_key), as_of_date)           AS ownership_source,
           arg_max(as_of_label, as_of_date)                        AS ownership_as_of,
           count(DISTINCT value_std) > 1                           AS ownership_sources_disagree
    FROM ev WHERE attribute = 'ownership' AND value_std IS NOT NULL GROUP BY 1
), emp AS (
    SELECT canonical_hospital_key,
           arg_max(source_label(source_key), as_of_date)           AS empanelment_source,
           arg_max(as_of_label, as_of_date)                        AS empanelment_as_of
    FROM ev WHERE attribute = 'scheme_empanelment' GROUP BY 1
), susp AS (
    SELECT canonical_hospital_key, arg_max(value_std, as_of_date) AS scheme_suspension_status, arg_max(as_of_label, as_of_date) AS suspension_as_of
    FROM ev WHERE attribute = 'scheme_suspension_status' GROUP BY 1
), nabh AS (
    SELECT canonical_hospital_key,
           arg_max(value_raw, as_of_date)                          AS nabh_status_scheme_raw,
           arg_max(value_std, as_of_date)                          AS nabh_status_scheme,
           arg_max(as_of_label, as_of_date)                        AS nabh_status_as_of
    FROM ev WHERE attribute = 'nabh_status_scheme_reported' GROUP BY 1
), beds AS (
    SELECT canonical_hospital_key, arg_max(value_num, as_of_date) AS beds_declared, arg_max(as_of_label, as_of_date) AS beds_as_of
    FROM ev WHERE attribute = 'beds_declared_to_scheme' AND value_num IS NOT NULL GROUP BY 1
), ftype AS (
    SELECT canonical_hospital_key, arg_max(value_std, as_of_date) AS facility_type, arg_max(as_of_label, as_of_date) AS facility_type_as_of
    FROM ev WHERE attribute = 'facility_type' AND value_std IS NOT NULL GROUP BY 1
), spec AS (
    SELECT canonical_hospital_key,
           bool_or(value_std = 'Orthopaedics')                                   AS has_orthopaedics,
           bool_or(value_std = 'Physical Medicine and Rehabilitation (PMR)')     AS has_pmr,
           bool_or(value_std = 'Physiotherapy')                                  AS has_physiotherapy,
           list_sort(list_distinct(list(value_std) FILTER (WHERE value_std IS NOT NULL))) AS specialties_standardized,
           count(*)                                                              AS specialty_raw_values
    FROM ev WHERE attribute = 'specialty' GROUP BY 1
), latest AS (
    SELECT canonical_hospital_key,
           year(max(as_of_date)) || ' · ' || source_label(arg_max(source_key, as_of_date)) AS latest_evidence,
           year(max(as_of_date)) || ' · ' || source_short(arg_max(source_key, as_of_date)) AS latest_evidence_short
    FROM core.pilot_record_resolved GROUP BY 1
)
SELECT
    h.canonical_hospital_key,
    h.hospital_name,
    source_label(h.hospital_name_source)                          AS hospital_name_source,
    h.address,
    h.pincode,
    source_label(h.pincode_source)                                AS pincode_source,
    h.city_derived,
    coalesce(h.city_derived, '(city not derivable)')              AS city_display,
    h.city_method,
    coalesce(h.city_method, 'not derivable')                      AS city_method_display,
    h.state_code_lgd,
    h.state_name,
    h.district_group,
    h.district_group_method,
    h.district_source_primary,
    h.district_source_values,
    h.district_current,
    h.district_current_note,
    own.ownership,
    coalesce(own.ownership, 'Not stated by sources')              AS ownership_display,
    own.ownership_source, own.ownership_as_of, coalesce(own.ownership_sources_disagree, false) AS ownership_sources_disagree,
    emp.empanelment_source IS NOT NULL                            AS maa_yojana_empanelled,
    emp.empanelment_source, emp.empanelment_as_of,
    susp.scheme_suspension_status, susp.suspension_as_of,
    nabh.nabh_status_scheme_raw, nabh.nabh_status_scheme, nabh.nabh_status_as_of,
    beds.beds_declared, beds.beds_as_of,
    ftype.facility_type, ftype.facility_type_as_of,
    coalesce(spec.has_orthopaedics, false)                        AS has_orthopaedics,
    coalesce(spec.has_pmr, false)                                 AS has_pmr,
    coalesce(spec.has_physiotherapy, false)                       AS has_physiotherapy,
    coalesce(spec.specialties_standardized, [])                   AS specialties_standardized,
    coalesce(spec.specialty_raw_values, 0)                        AS specialty_raw_values,
    h.sources,
    array_to_string(list_sort(list_transform(h.sources, s -> source_label(s))), ' + ') AS source_combination,
    array_to_string(list_sort(list_transform(h.sources, s -> source_short(s))), ' + ') AS source_combination_short,
    h.source_count, h.record_count, h.match_confidence,
    h.canonical_hospital_key IN (SELECT canonical_hospital_key FROM mart.hospital_possible_match_keys) AS possible_duplicate_pending_review,
    h.earliest_evidence_date, h.latest_evidence_date,
    latest.latest_evidence,
    latest.latest_evidence_short,
    -- Transparency indicator, not a quality score: share of six profile fields that any source provides.
    round((  (own.ownership IS NOT NULL)::INT + (emp.empanelment_source IS NOT NULL)::INT
           + (len(coalesce(spec.specialties_standardized, [])) > 0)::INT + (nabh.nabh_status_scheme IS NOT NULL)::INT
           + (beds.beds_declared IS NOT NULL)::INT + (h.pincode IS NOT NULL)::INT) / 6.0, 2) AS profile_completeness
FROM core.dim_hospital h
LEFT JOIN own    USING (canonical_hospital_key)
LEFT JOIN emp    USING (canonical_hospital_key)
LEFT JOIN susp   USING (canonical_hospital_key)
LEFT JOIN nabh   USING (canonical_hospital_key)
LEFT JOIN beds   USING (canonical_hospital_key)
LEFT JOIN ftype  USING (canonical_hospital_key)
LEFT JOIN spec   USING (canonical_hospital_key)
LEFT JOIN latest USING (canonical_hospital_key);

-- Speciality evidence per hospital (raw and standardised side by side): the bridge between
-- hospitals and standard specialities.
CREATE OR REPLACE TABLE mart.hospital_specialty AS
SELECT canonical_hospital_key, value_std AS specialty_standardized, specialty_family, value_raw AS specialty_raw,
       source_key, source_label(source_key) AS source, evidence_type, as_of_date, as_of_label, mapping_basis
FROM core.fact_hospital_evidence
WHERE attribute = 'specialty';

-- Every attributed value with its source and date (labels and order live in mart.dim_attribute).
-- Used for profiles and side-by-side comparison; no winner is computed.
CREATE OR REPLACE TABLE mart.hospital_attribute AS
SELECT canonical_hospital_key,
       attribute,
       coalesce(value_std, value_raw)                                AS value_display,
       value_raw,
       value_std,
       source_key,
       source_label(source_key)                                      AS source,
       as_of_label,
       as_of_date,
       quality_note
FROM core.fact_hospital_evidence;

-- The source records behind each hospital: how each source names and places it, and how it was matched.
CREATE OR REPLACE TABLE mart.hospital_source_record AS
SELECT canonical_hospital_key,
       source_key,
       source_label(source_key)            AS source,
       source_record_id,
       name_raw                            AS name_as_recorded,
       address_raw                         AS address_as_recorded,
       district_source                     AS district_as_recorded,
       district_group,
       pincode_valid                       AS pincode_as_recorded,
       city_derived                        AS city_derived_for_record,
       city_method                         AS city_method_for_record,
       evidence_type,
       as_of_date,
       as_of_label,
       match_method,
       match_confidence,
       review_status
FROM core.pilot_record_resolved;

-- Hospitals that may be the same facility as another listing; a person has not decided yet.
CREATE OR REPLACE TABLE mart.hospital_possible_match AS
SELECT k.canonical_hospital_key,
       k.possible_match_key,
       h.hospital_name                                               AS possible_match_name,
       h.city_derived                                                AS possible_match_city,
       source_label(split_part(k.other_record, ':', 1))              AS possible_match_source,
       CASE k.rule
           WHEN 'same_source_needs_review' THEN 'Same name listed twice in one source'
           WHEN 'kind_conflict_needs_review' THEN 'Similar name, but public and private facility words differ'
           ELSE 'Similar name; address evidence not conclusive' END  AS reason,
       k.combined_score                                              AS similarity_score,
       k.pincode_relation,
       'Pending review'                                              AS review_status
FROM mart.hospital_possible_match_keys k
JOIN mart.hospital h ON h.canonical_hospital_key = k.possible_match_key;
DROP TABLE mart.hospital_possible_match_keys;

-- Provenance shown next to values, with how the pilot uses each registered source.
CREATE OR REPLACE TABLE mart.source AS
SELECT s.source_key, source_label(s.source_key) AS source, s.title, s.publisher, s.role, s.reference_period, s.retrieved_on,
       s.licence, s.redistribution, s.resource_page,
       coalesce(p.records, 0) AS pilot_records,
       CASE
           WHEN p.records > 0 THEN 'Hospital records in the pilot'
           WHEN s.source_key = 'pmjay_hem_export' THEN 'Not acquired: needs a manual, CAPTCHA-protected export by the project owner'
           WHEN s.source_key = 'lgd_villages_pincode' THEN 'Not acquired: download failed (HTTP 500); would allow district_current'
           WHEN s.source_key = 'pincode' THEN 'Reference: pincode validation and city derivation'
           WHEN s.source_key = 'lgd_states' THEN 'Reference: state names and LGD codes'
           WHEN s.source_key = 'lgd_districts' THEN 'Reference: current districts (no reliable pilot mapping yet)'
           WHEN s.role = 'context' THEN 'State-level context indicators'
           WHEN s.source_key = 'nabh' THEN 'Not used in outputs: research only until reuse terms are verified'
           WHEN s.role = 'provenance_check' THEN 'Provenance check only (dates the NHD content)'
           WHEN s.role = 'optional_gap_fill' THEN 'Not used: no documented coverage gap in the pilot'
       END AS pilot_use
FROM core.dim_source s
LEFT JOIN (SELECT source_key, count(*) AS records FROM stg.pilot_record GROUP BY 1) p USING (source_key);

-- Official state context (Rajya Sabha answers), keyed to the state dimension where the name matches LGD.
CREATE OR REPLACE TABLE mart.state_context AS
SELECT state_code_lgd,
       coalesce(state_name_lgd, state_source)                        AS state,
       state_source,
       CASE WHEN state_source IN ('India', 'Total') THEN 'India total'
            WHEN state_code_lgd IS NULL THEN 'State/UT not matched to LGD (e.g. before the 2020 UT merger)'
            ELSE 'State/UT' END                                      AS geography_level,
       indicator,
       CASE indicator
           WHEN 'govt_hospitals_total' THEN 'Government hospitals (total)'
           WHEN 'govt_hospitals_rural' THEN 'Government hospitals (rural)'
           WHEN 'govt_hospitals_urban' THEN 'Government hospitals (urban)'
           WHEN 'govt_beds_total' THEN 'Government hospital beds (total)'
           WHEN 'govt_beds_rural' THEN 'Government hospital beds (rural)'
           WHEN 'govt_beds_urban' THEN 'Government hospital beds (urban)'
           WHEN 'pmjay_empanelled_hospitals' THEN 'AB PM-JAY empanelled hospitals'
           WHEN 'nabh_accredited_hospitals' THEN 'NABH-accredited hospitals'
           ELSE indicator END                                        AS indicator_label,
       value,
       reference_period,
       source_key
FROM core.fact_state_indicator;

-- The MAA Yojana package list behind "PMR -Phase 4" (terminology evidence), linked to its standard speciality.
CREATE OR REPLACE TABLE mart.pmr_package AS
SELECT p.*, m.specialty_standardized
FROM ref.pmr_package p
LEFT JOIN ref.specialty_map m
       ON m.source_key = 'maay_live_search' AND m.specialty_raw_normalized = specialty_norm(p.speciality_raw)
      AND m.specialty_standardized IS NOT NULL;
