-- 06_model.sql
-- The curated model for the pilot. Identity and location live in dim_hospital; every attribute
-- value is a dated evidence row in fact_hospital_evidence, so values from different sources and
-- dates never overwrite each other. Runs after entity resolution (core.hospital_xref).

CREATE SCHEMA IF NOT EXISTS core;

-- Source records joined to their canonical hospital.
CREATE OR REPLACE TABLE core.pilot_record_resolved AS
SELECT x.canonical_hospital_key, x.match_method, x.match_confidence, x.review_status, r.*
FROM core.hospital_xref x
JOIN stg.pilot_record r USING (source_key, source_record_id);

-- Hospitals: identity and location. Display name precedence: scheme list (official name),
-- then NHD, then live search; pincode precedence: NHD (a real field), then pincodes found in addresses.
CREATE OR REPLACE TABLE core.dim_hospital AS
WITH rec AS (
    SELECT *,
           CASE source_key WHEN 'maay_district_lists' THEN 1 WHEN 'nhd' THEN 2 ELSE 3 END AS name_rank,
           CASE source_key WHEN 'nhd' THEN 1 WHEN 'maay_district_lists' THEN 2 ELSE 3 END AS pincode_rank
    FROM core.pilot_record_resolved
), agg AS (
    SELECT
        canonical_hospital_key,
        arg_min(name_raw, name_rank)                                                    AS hospital_name,
        arg_min(source_key, name_rank)                                                  AS hospital_name_source,
        arg_min(address_raw, name_rank) FILTER (WHERE address_raw IS NOT NULL)          AS address,
        arg_min(pincode_valid, pincode_rank) FILTER (WHERE pincode_valid IS NOT NULL)   AS pincode,
        arg_min(source_key, pincode_rank) FILTER (WHERE pincode_valid IS NOT NULL)      AS pincode_source,
        -- City: pincode-based methods first, then the address-keyword method.
        arg_min(city_derived, (city_method <> 'address_keyword')::INT * -10 + pincode_rank) FILTER (WHERE city_derived IS NOT NULL) AS city_derived,
        arg_min(city_method,  (city_method <> 'address_keyword')::INT * -10 + pincode_rank) FILTER (WHERE city_derived IS NOT NULL) AS city_method,
        any_value(state_name_lgd)                                                       AS state_name,
        any_value(state_code_lgd)                                                       AS state_code_lgd,
        string_agg(DISTINCT district_source || ' [' || source_key || ']', '; ' ORDER BY district_source || ' [' || source_key || ']') AS district_source_values,
        arg_min(district_source, name_rank)                                             AS district_source_primary,
        -- The district shown to users: as recorded by the sources, with documented groupings applied.
        -- 'as_recorded' when at least one source names the group itself; otherwise the grouping placed it.
        arg_min(district_group, name_rank)                                              AS district_group,
        CASE WHEN bool_or(district_group_method = 'as_recorded') THEN 'as_recorded'
             ELSE 'documented_grouping' END                                             AS district_group_method,
        count(DISTINCT district_group)                                                  AS district_groups_in_records,
        any_value(district_current)                                                     AS district_current,
        any_value(district_current_code_lgd)                                            AS district_current_code_lgd,
        any_value(district_current_note)                                                AS district_current_note,
        list_sort(list_distinct(list(source_key)))                                      AS sources,
        count(DISTINCT source_key)                                                      AS source_count,
        count(*)                                                                        AS record_count,
        min(as_of_date)                                                                 AS earliest_evidence_date,
        max(as_of_date)                                                                 AS latest_evidence_date,
        CASE WHEN count(*) = 1 THEN 'single record'
             WHEN bool_or(match_confidence = 'medium') THEN 'medium'
             WHEN bool_or(match_confidence = 'manual') THEN 'manual'
             ELSE 'high' END                                                            AS match_confidence
    FROM rec
    GROUP BY canonical_hospital_key
)
SELECT * FROM agg;

-- Evidence: one row per attributed value, with source, evidence type and as-of date.
CREATE OR REPLACE TABLE core.fact_hospital_evidence AS
WITH listing AS (
    -- Every source record is itself evidence that the source knows the hospital (value_raw = the record id).
    SELECT canonical_hospital_key, source_key, source_record_id, 'source_listing' AS attribute,
           source_record_id AS value_raw,
           CASE source_key WHEN 'nhd' THEN 'Listed in the National Hospital Directory'
                           WHEN 'maay_district_lists' THEN 'Listed in a MAA Yojana district list'
                           WHEN 'maay_live_search' THEN 'Returned by the MAA Yojana hospital search' END AS value_std,
           CAST(NULL AS DOUBLE) AS value_num, CAST(NULL AS VARCHAR) AS specialty_family,
           'Source record resolved to this hospital' AS mapping_basis, evidence_type, as_of_date, as_of_label,
           CAST(NULL AS VARCHAR) AS quality_note
    FROM core.pilot_record_resolved
), ownership AS (
    SELECT r.canonical_hospital_key, r.source_key, r.source_record_id, 'ownership' AS attribute,
           r.ownership_raw AS value_raw, r.ownership_std AS value_std, CAST(NULL AS DOUBLE) AS value_num,
           CAST(NULL AS VARCHAR) AS specialty_family, own.mapping_basis, r.evidence_type, r.as_of_date, r.as_of_label,
           CAST(NULL AS VARCHAR) AS quality_note
    FROM core.pilot_record_resolved r
    LEFT JOIN ref.value_map own ON own.source_key = r.source_key AND own.attribute = 'ownership' AND own.value_raw = r.ownership_raw
    WHERE r.ownership_raw IS NOT NULL
), empanelment AS (
    SELECT canonical_hospital_key, source_key, source_record_id, 'scheme_empanelment',
           CASE WHEN source_key = 'maay_district_lists' THEN 'Listed in MAA Yojana ' || lower(list_category) || ' empanelled-hospitals list'
                ELSE 'Returned by MAA Yojana hospital search (' || district_source || ')' END,
           'Empanelled under MAA Yojana (Rajasthan PM-JAY convergence)', NULL, NULL,
           'Presence in the official scheme list or search result', evidence_type, as_of_date, as_of_label, NULL
    FROM core.pilot_record_resolved
    WHERE source_key IN ('maay_district_lists', 'maay_live_search')
), suspension AS (
    SELECT r.canonical_hospital_key, r.source_key, r.source_record_id, 'scheme_suspension_status',
           r.suspended_raw, vm.value_standardized, NULL, NULL, vm.mapping_basis, r.evidence_type, r.as_of_date, r.as_of_label, NULL
    FROM core.pilot_record_resolved r
    LEFT JOIN ref.value_map vm ON vm.source_key = r.source_key AND vm.attribute = 'suspension_status' AND vm.value_raw = r.suspended_raw
    WHERE r.source_key = 'maay_live_search' AND r.suspended_raw IS NOT NULL
), specialty AS (
    SELECT r.canonical_hospital_key, s.source_key, s.source_record_id, 'specialty',
           s.specialty_raw, s.specialty_standardized, NULL, s.specialty_family, s.mapping_basis,
           r.evidence_type, r.as_of_date, r.as_of_label,
           CASE WHEN s.specialty_standardized IS NULL THEN 'Not standardised in the pilot (raw value kept)' END
    FROM stg.specialty_std s
    JOIN core.pilot_record_resolved r USING (source_key, source_record_id)
), nabh_scheme AS (
    SELECT r.canonical_hospital_key, r.source_key, r.source_record_id, 'nabh_status_scheme_reported',
           m.nabh_status_raw, vm.value_standardized, NULL, NULL, vm.mapping_basis, r.evidence_type, r.as_of_date, r.as_of_label, NULL
    FROM core.pilot_record_resolved r
    JOIN stg.maay_list m USING (source_key, source_record_id)
    LEFT JOIN ref.value_map vm ON vm.source_key = r.source_key AND vm.attribute = 'nabh_status_scheme' AND vm.value_raw = m.nabh_status_raw
    WHERE m.nabh_status_raw IS NOT NULL
), beds AS (
    SELECT r.canonical_hospital_key, r.source_key, r.source_record_id, 'beds_declared_to_scheme',
           m.beds_raw,
           CASE WHEN m.beds_declared > 0 THEN CAST(m.beds_declared AS VARCHAR) || ' beds' END,
           CASE WHEN m.beds_declared > 0 THEN m.beds_declared END,
           NULL, 'BEDSTRENGTH column of the scheme list', r.evidence_type, r.as_of_date, r.as_of_label,
           CASE WHEN m.beds_raw = '0' THEN 'Zero beds in the source - treated as missing' END
    FROM core.pilot_record_resolved r
    JOIN stg.maay_list m USING (source_key, source_record_id)
    WHERE m.beds_raw IS NOT NULL AND m.beds_raw <> ''
), facility_type AS (
    SELECT r.canonical_hospital_key, r.source_key, r.source_record_id, 'facility_type',
           n.facility_type_raw, vm.value_standardized, NULL, NULL, vm.mapping_basis, r.evidence_type, r.as_of_date, r.as_of_label, NULL
    FROM core.pilot_record_resolved r
    JOIN stg.nhd n USING (source_key, source_record_id)
    LEFT JOIN ref.value_map vm ON vm.source_key = 'nhd' AND vm.attribute = 'facility_type' AND vm.value_raw = n.facility_type_raw
    WHERE n.facility_type_raw IS NOT NULL
), government_level AS (
    SELECT r.canonical_hospital_key, r.source_key, r.source_record_id, 'government_level',
           m.govt_type_raw,
           CASE m.govt_type_raw WHEN 'GOR' THEN 'Government of Rajasthan' WHEN 'GOI' THEN 'Government of India' END,
           NULL, NULL, 'GOVT TYPE column of the scheme list', r.evidence_type, r.as_of_date, r.as_of_label, NULL
    FROM core.pilot_record_resolved r
    JOIN stg.maay_list m USING (source_key, source_record_id)
    WHERE m.govt_type_raw IS NOT NULL
)
SELECT * FROM listing
UNION ALL SELECT * FROM ownership
UNION ALL SELECT * FROM empanelment
UNION ALL SELECT * FROM suspension
UNION ALL SELECT * FROM specialty
UNION ALL SELECT * FROM nabh_scheme
UNION ALL SELECT * FROM beds
UNION ALL SELECT * FROM facility_type
UNION ALL SELECT * FROM government_level;

-- Standard specialities used by the pilot filter, with their documented basis and definition.
CREATE OR REPLACE TABLE core.dim_specialty AS
SELECT m.specialty_standardized, any_value(m.specialty_family) AS specialty_family,
       any_value(d.definition) AS definition,
       string_agg(DISTINCT m.source_key, ', ' ORDER BY m.source_key) AS mapped_from_sources,
       count(*) AS raw_spellings_mapped
FROM ref.specialty_map m
LEFT JOIN ref.specialty_definition d USING (specialty_standardized)
WHERE m.specialty_standardized IS NOT NULL
GROUP BY m.specialty_standardized;

-- Sources (provenance shown next to every value).
CREATE OR REPLACE TABLE core.dim_source AS SELECT * FROM ref.source;

-- Candidate matches still waiting for a person's decision, at hospital level (both directions are
-- derived in the mart). Pairs whose records already sit in one hospital through other links are moot.
CREATE OR REPLACE TABLE core.hospital_match_candidate AS
SELECT xa.canonical_hospital_key AS hospital_key_a, xb.canonical_hospital_key AS hospital_key_b,
       c.record_a, c.record_b, c.rule, c.combined_score, c.name_score, c.pincode_relation
FROM core.er_candidate c
JOIN core.hospital_xref xa ON xa.record_ref = c.record_a
JOIN core.hospital_xref xb ON xb.record_ref = c.record_b
WHERE c.decision = 'needs_review' AND xa.canonical_hospital_key <> xb.canonical_hospital_key;

-- Official state-level context, joined to LGD state names where they match (case, punctuation,
-- "&"/"and" and a leading "The" ignored). National totals and pre-2020 UTs stay unmatched.
CREATE OR REPLACE MACRO state_match_key(x) AS
    regexp_replace(lower(regexp_replace(replace(x, '&', 'and'), '[^a-zA-Z]', '', 'g')), '^the', '');
CREATE OR REPLACE TABLE core.fact_state_indicator AS
SELECT i.source_key, i.state_source, s.state_code_lgd, s.state_name AS state_name_lgd, i.indicator, i.value, i.reference_period
FROM stg.state_indicator i
LEFT JOIN stg.lgd_state s ON state_match_key(s.state_name) = state_match_key(i.state_source)
WHERE i.value IS NOT NULL;
