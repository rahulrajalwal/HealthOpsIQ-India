-- 08_quality_checks.sql
-- Data-quality assertions with measured values. status: pass / fail (a rule is broken),
-- warn (a known source issue worth attention), info (a measurement to report).

CREATE SCHEMA IF NOT EXISTS dq;
CREATE OR REPLACE TABLE dq.check_result (
    check_id VARCHAR, area VARCHAR, description VARCHAR, measured DOUBLE, expectation VARCHAR, status VARCHAR
);

CREATE OR REPLACE MACRO dq_status(measured, rule_ok) AS CASE WHEN rule_ok THEN 'pass' ELSE 'fail' END;

-- Privacy -------------------------------------------------------------------------------------
INSERT INTO dq.check_result
SELECT 'PRIV-01', 'Privacy', 'Contact or personal columns in landing/stg/core/mart tables', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM information_schema.columns
      WHERE table_schema IN ('landing', 'stg', 'core', 'mart')
        AND regexp_matches(column_name, 'phone|mobile|tele|e-?mail|fax|nodal|helpline|toll', 'i'));

INSERT INTO dq.check_result
SELECT 'PRIV-02', 'Privacy', 'Mart values that look like an e-mail address or a 10-digit mobile number', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM (
        SELECT address AS v FROM mart.hospital UNION ALL SELECT hospital_name FROM mart.hospital
        UNION ALL SELECT value_raw FROM mart.hospital_attribute
        UNION ALL SELECT name_as_recorded FROM mart.hospital_source_record
        UNION ALL SELECT address_as_recorded FROM mart.hospital_source_record
        UNION ALL SELECT possible_match_name FROM mart.hospital_possible_match)
      WHERE regexp_matches(v, '@|(^|[^0-9])[6-9][0-9]{9}([^0-9]|$)'));

INSERT INTO dq.check_result
SELECT 'PRIV-03', 'Privacy', 'Scheme-list rows where the loader removed a nodal officer name from a name/address cell', n, 'reported', 'info'
FROM (SELECT count(*) AS n FROM stg.maay_list WHERE privacy_scrubbed LIKE 'officer name removed%');

INSERT INTO dq.check_result
SELECT 'PRIV-04', 'Privacy', 'Scheme-list rows whose officer cell repeats the facility name (source entry error; nothing removed)', n, 'reported', 'info'
FROM (SELECT count(*) AS n FROM stg.maay_list WHERE privacy_scrubbed LIKE 'officer cell repeats%');

-- Lineage -------------------------------------------------------------------------------------
INSERT INTO dq.check_result
SELECT 'LIN-01', 'Lineage', 'Pilot source records without a canonical hospital', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM stg.pilot_record r
      LEFT JOIN core.hospital_xref x USING (source_key, source_record_id) WHERE x.canonical_hospital_key IS NULL);

INSERT INTO dq.check_result
SELECT 'LIN-02', 'Lineage', 'Pilot source records', n, 'reported', 'info' FROM (SELECT count(*) AS n FROM stg.pilot_record);

INSERT INTO dq.check_result
SELECT 'LIN-03', 'Lineage', 'Canonical hospitals in the pilot', n, 'reported', 'info' FROM (SELECT count(*) AS n FROM core.dim_hospital);

INSERT INTO dq.check_result
SELECT 'LIN-05', 'Lineage', 'Pilot hospitals without a name', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM core.dim_hospital WHERE nullif(trim(hospital_name), '') IS NULL);

INSERT INTO dq.check_result
SELECT 'LIN-06', 'Lineage', 'Pilot hospitals without a source-listing evidence row', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM core.dim_hospital h
      WHERE NOT EXISTS (SELECT 1 FROM core.fact_hospital_evidence e
                        WHERE e.canonical_hospital_key = h.canonical_hospital_key AND e.attribute = 'source_listing'));

INSERT INTO dq.check_result
SELECT 'LIN-04', 'Lineage', 'Evidence rows without source or as-of date', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM core.fact_hospital_evidence WHERE source_key IS NULL OR as_of_date IS NULL);

-- Entity resolution --------------------------------------------------------------------------
INSERT INTO dq.check_result
SELECT 'ER-' || row_number() OVER (ORDER BY decision), 'Entity resolution', 'Candidate pairs decided: ' || decision, n, 'reported',
       CASE WHEN decision = 'needs_review' THEN 'warn' ELSE 'info' END
FROM (SELECT decision, count(*) AS n FROM core.er_candidate GROUP BY decision);

INSERT INTO dq.check_result
SELECT 'ER-SAME-CODE', 'Entity resolution', 'MAA Yojana hospital codes listed with more than one token ID (merged as one facility)', n, 'reported', 'info'
FROM (SELECT count(*) AS n FROM (SELECT hospital_code FROM stg.maay_list WHERE lower(district_source) LIKE 'jaipur%'
                                 GROUP BY hospital_code HAVING count(DISTINCT token_id) > 1));

-- Specialities --------------------------------------------------------------------------------
INSERT INTO dq.check_result
SELECT 'SPEC-01', 'Specialities', 'Raw speciality tokens of pilot records not carried into evidence', n, '0', dq_status(n, n = 0)
FROM (SELECT (SELECT count(*) FROM stg.specialty_token t JOIN stg.pilot_record USING (source_key, source_record_id))
           - (SELECT count(*) FROM core.fact_hospital_evidence WHERE attribute = 'specialty') AS n);

INSERT INTO dq.check_result
SELECT 'SPEC-02', 'Specialities', 'Evidence where a PMR value is standardised as Physiotherapy', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM core.fact_hospital_evidence
      WHERE attribute = 'specialty' AND regexp_matches(value_raw, 'pmr|physical medicine', 'i') AND value_std = 'Physiotherapy');

INSERT INTO dq.check_result
SELECT 'SPEC-03', 'Specialities', 'Raw spellings mapped to more than one standard speciality', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM (SELECT source_key, specialty_raw_normalized FROM ref.specialty_map
                                 WHERE specialty_standardized IS NOT NULL GROUP BY ALL HAVING count(DISTINCT specialty_standardized) > 1));

INSERT INTO dq.check_result
SELECT 'SPEC-04', 'Specialities', 'Orthodontics (dental) standardised as Orthopaedics', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM stg.specialty_std WHERE specialty_raw_normalized LIKE '%orthodont%' AND specialty_standardized = 'Orthopaedics');

INSERT INTO dq.check_result
SELECT 'SPEC-05', 'Specialities', 'Share of pilot speciality tokens standardised (pilot maps only its specialities)', round(100.0 * avg((value_std IS NOT NULL)::INT), 1), 'reported (%)', 'info'
FROM core.fact_hospital_evidence WHERE attribute = 'specialty';

-- Geography -----------------------------------------------------------------------------------
INSERT INTO dq.check_result
SELECT 'GEO-01', 'Geography', 'Pilot records without district_source', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM stg.pilot_record WHERE district_source IS NULL);

INSERT INTO dq.check_result
SELECT 'GEO-02', 'Geography', 'district_current filled without a documented mapping', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM stg.pilot_record WHERE district_current IS NOT NULL);

INSERT INTO dq.check_result
SELECT 'GEO-03', 'Geography', 'Pilot hospitals with a valid pincode (%)', round(100.0 * avg((pincode IS NOT NULL)::INT), 1), 'reported (%)', 'info'
FROM core.dim_hospital;

INSERT INTO dq.check_result
SELECT 'GEO-04', 'Geography', 'Pilot hospitals with a derived city (%)', round(100.0 * avg((city_derived IS NOT NULL)::INT), 1), 'reported (%)', 'info'
FROM core.dim_hospital;

INSERT INTO dq.check_result
SELECT 'GEO-05', 'Geography', 'Address-keyword city agrees with pincode city where both exist (%, validation of the address method)',
       round(100.0 * avg((city_from_address = city_from_pincode)::INT), 1), 'reported (%); n = ' || count(*), 'info'
FROM stg.pilot_record WHERE city_from_address IS NOT NULL AND city_from_pincode IS NOT NULL;

INSERT INTO dq.check_result
SELECT 'GEO-06-' || coalesce(city_method, 'none'), 'Geography', 'Pilot hospitals by city method: ' || coalesce(city_method, 'no city'), count(*), 'reported', 'info'
FROM core.dim_hospital GROUP BY city_method;

INSERT INTO dq.check_result
SELECT 'GEO-07', 'Geography', 'District groupings without a documented basis and decision (ref_district_source_group.csv)', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM ref.district_source_group
      WHERE nullif(trim(basis), '') IS NULL OR nullif(trim(decided_by), '') IS NULL OR TRY_CAST(decided_on AS DATE) IS NULL);

INSERT INTO dq.check_result
SELECT 'GEO-08', 'Geography', 'Pilot records placed in the district by a documented grouping (e.g. scheme districts Jaipur1/Jaipur2)', n, 'reported', 'info'
FROM (SELECT count(*) AS n FROM stg.pilot_record WHERE district_group_method = 'documented_grouping');

INSERT INTO dq.check_result
SELECT 'GEO-09', 'Geography', 'Hospitals linking a grouped record to a record that names the district itself (evidence for the grouping)', n, 'reported', 'info'
FROM (SELECT count(*) AS n FROM (
        SELECT canonical_hospital_key FROM core.pilot_record_resolved GROUP BY 1
        HAVING bool_or(district_group_method = 'documented_grouping') AND bool_or(district_group_method = 'as_recorded')));

INSERT INTO dq.check_result
SELECT 'GEO-10', 'Geography', 'Hospitals whose records fall in more than one district group', n, '0', dq_status(n, n = 0)
FROM (SELECT count(*) AS n FROM core.dim_hospital WHERE district_groups_in_records > 1);

-- Source issues -------------------------------------------------------------------------------
INSERT INTO dq.check_result
SELECT 'SRC-BEDS-0', 'Source issues', 'Scheme-list rows declaring zero beds (treated as missing)', n, 'reported', CASE WHEN n > 0 THEN 'warn' ELSE 'info' END
FROM (SELECT count(*) AS n FROM stg.maay_list WHERE beds_raw = '0');

INSERT INTO dq.check_result
SELECT 'SRC-PARSE', 'Source issues', 'State-government list rows where name and address could not be separated', n, 'reported', CASE WHEN n > 0 THEN 'warn' ELSE 'info' END
FROM (SELECT count(*) AS n FROM stg.maay_list WHERE parse_warning IS NOT NULL);

INSERT INTO dq.check_result
SELECT 'SRC-OWN', 'Source issues', 'Hospitals whose sources disagree on ownership', n, 'reported', CASE WHEN n > 0 THEN 'warn' ELSE 'info' END
FROM (SELECT count(*) AS n FROM mart.hospital WHERE ownership_sources_disagree);

-- NABH stays out of exports (terms) ----------------------------------------------------------
INSERT INTO dq.check_result
SELECT 'NABH-01', 'Terms', 'NABH-derived rows or columns in mart tables', n, '0', dq_status(n, n = 0)
FROM (SELECT (SELECT count(*) FROM core.fact_hospital_evidence WHERE source_key = 'nabh')
           + (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'mart' AND regexp_matches(column_name, 'nabh_directory|accreditation_no|programme_code', 'i')) AS n);

-- Star schema: dimension keys are unique and filled; every fact row finds its dimension row ----
-- These back the Power BI relationships: a failure here would show up as a "(Blank)" member.
INSERT INTO dq.check_result
SELECT 'KEY-' || dim, 'Model', 'Duplicate or empty keys in dimension ' || dim, n, '0', dq_status(n, n = 0)
FROM (
    SELECT 'hospital' AS dim, count(*) - count(DISTINCT canonical_hospital_key) + count(*) FILTER (WHERE canonical_hospital_key IS NULL) AS n FROM mart.hospital
    UNION ALL SELECT 'dim_state', count(*) - count(DISTINCT state_code_lgd) + count(*) FILTER (WHERE state_code_lgd IS NULL) FROM mart.dim_state
    UNION ALL SELECT 'dim_specialty', count(*) - count(DISTINCT specialty_standardized) + count(*) FILTER (WHERE specialty_standardized IS NULL) FROM core.dim_specialty
    UNION ALL SELECT 'dim_attribute', count(*) - count(DISTINCT attribute) + count(*) FILTER (WHERE attribute IS NULL) FROM mart.dim_attribute
    UNION ALL SELECT 'source', count(*) - count(DISTINCT source_key) + count(*) FILTER (WHERE source_key IS NULL) FROM mart.source
);

INSERT INTO dq.check_result
SELECT 'REL-' || lpad(CAST(row_number() OVER (ORDER BY relationship) AS VARCHAR), 2, '0'), 'Model',
       'Rows without a matching dimension row: ' || relationship, n, '0', dq_status(n, n = 0)
FROM (
    SELECT 'hospital_specialty -> hospital' AS relationship, count(*) AS n FROM mart.hospital_specialty f
        WHERE NOT EXISTS (SELECT 1 FROM mart.hospital d WHERE d.canonical_hospital_key = f.canonical_hospital_key)
    UNION ALL SELECT 'hospital_specialty -> dim_specialty (standardised rows)', count(*) FROM mart.hospital_specialty f
        WHERE f.specialty_standardized IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.dim_specialty d WHERE d.specialty_standardized = f.specialty_standardized)
    UNION ALL SELECT 'hospital_attribute -> hospital', count(*) FROM mart.hospital_attribute f
        WHERE NOT EXISTS (SELECT 1 FROM mart.hospital d WHERE d.canonical_hospital_key = f.canonical_hospital_key)
    UNION ALL SELECT 'hospital_attribute -> dim_attribute', count(*) FROM mart.hospital_attribute f
        WHERE NOT EXISTS (SELECT 1 FROM mart.dim_attribute d WHERE d.attribute = f.attribute)
    UNION ALL SELECT 'hospital_attribute -> source', count(*) FROM mart.hospital_attribute f
        WHERE NOT EXISTS (SELECT 1 FROM mart.source d WHERE d.source_key = f.source_key)
    UNION ALL SELECT 'hospital_source_record -> hospital', count(*) FROM mart.hospital_source_record f
        WHERE NOT EXISTS (SELECT 1 FROM mart.hospital d WHERE d.canonical_hospital_key = f.canonical_hospital_key)
    UNION ALL SELECT 'hospital_source_record -> source', count(*) FROM mart.hospital_source_record f
        WHERE NOT EXISTS (SELECT 1 FROM mart.source d WHERE d.source_key = f.source_key)
    UNION ALL SELECT 'hospital_possible_match -> hospital (both keys)', count(*) FROM mart.hospital_possible_match f
        WHERE NOT EXISTS (SELECT 1 FROM mart.hospital d WHERE d.canonical_hospital_key = f.canonical_hospital_key)
           OR NOT EXISTS (SELECT 1 FROM mart.hospital d WHERE d.canonical_hospital_key = f.possible_match_key)
    UNION ALL SELECT 'hospital -> dim_state', count(*) FROM mart.hospital f
        WHERE f.state_code_lgd IS NULL OR NOT EXISTS (SELECT 1 FROM mart.dim_state d WHERE d.state_code_lgd = f.state_code_lgd)
    UNION ALL SELECT 'state_context -> dim_state (matched rows)', count(*) FROM mart.state_context f
        WHERE f.state_code_lgd IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mart.dim_state d WHERE d.state_code_lgd = f.state_code_lgd)
    UNION ALL SELECT 'pmr_package -> dim_specialty', count(*) FROM mart.pmr_package f
        WHERE f.specialty_standardized IS NULL OR NOT EXISTS (SELECT 1 FROM core.dim_specialty d WHERE d.specialty_standardized = f.specialty_standardized)
);

INSERT INTO dq.check_result
SELECT 'CTX-01', 'Model', 'State-context rows not linked to an LGD state (India totals; UTs as they were before the 2020 merger)', n, 'reported', 'info'
FROM (SELECT count(*) AS n FROM mart.state_context WHERE state_code_lgd IS NULL);
