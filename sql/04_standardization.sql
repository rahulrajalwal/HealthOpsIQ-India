-- 04_standardization.sql
-- Standardised values sit beside the raw ones; nothing raw is overwritten.
-- Variables set by the build: reference_dir.

-- Curated maps (data/reference/*.csv). Rows with an empty standard value document a deliberate non-mapping.
CREATE OR REPLACE TABLE ref.specialty_map AS
SELECT source_key, specialty_raw_normalized, NULLIF(specialty_standardized, '') AS specialty_standardized,
       NULLIF(specialty_family, '') AS specialty_family, mapping_basis
FROM read_csv(getvariable('reference_dir') || '/ref_specialty_map.csv', all_varchar = true, header = true);

CREATE OR REPLACE TABLE ref.specialty_definition AS
SELECT specialty_standardized, definition, basis
FROM read_csv(getvariable('reference_dir') || '/ref_specialty_definition.csv', all_varchar = true, header = true);

CREATE OR REPLACE TABLE ref.value_map AS
SELECT source_key, attribute, value_raw, value_standardized, mapping_basis
FROM read_csv(getvariable('reference_dir') || '/ref_value_map.csv', all_varchar = true, header = true);

-- Specialities: raw token + standardised name + family + why. Unmapped tokens stay, with NULL standard values.
CREATE OR REPLACE TABLE stg.specialty_std AS
SELECT t.*, m.specialty_standardized, m.specialty_family, m.mapping_basis
FROM stg.specialty_token t
LEFT JOIN ref.specialty_map m
       ON m.source_key = t.source_key
      AND m.specialty_raw_normalized = t.specialty_raw_normalized
      AND m.specialty_standardized IS NOT NULL;

-- City derived from the pincode (India Post). Method recorded; ambiguous pincodes get no city.
--   * every office of the pincode is in one "<X> City Division"       -> city = X
--   * otherwise the pincode has exactly one delivery office (PO/HO)   -> city = that office's town
CREATE OR REPLACE TABLE ref.pincode_city AS
WITH offices AS (
    SELECT pincode, division_name, office_type, postal_district, postal_state,
           trim(regexp_replace(office_name, '\s+(G\.?P\.?O|S\.?O|H\.?O|B\.?O|P\.?O)\.?(\s*\(.*\))?\s*$', '', 'i')) AS office_town
    FROM stg.india_post
), per_pin AS (
    SELECT pincode,
           list_sort(list_distinct(list(division_name)))                                      AS divisions,
           list_sort(list_distinct(list(office_town) FILTER (WHERE office_type IN ('PO', 'HO')))) AS delivery_towns,
           list_sort(list_distinct(list(postal_district)))                                    AS postal_districts,
           list_sort(list_distinct(list(postal_state)))                                       AS postal_states
    FROM offices GROUP BY pincode
)
SELECT
    pincode,
    CASE WHEN len(divisions) = 1 AND divisions[1] ILIKE '% City Division' THEN regexp_replace(divisions[1], '\s+City Division$', '', 'i')
         WHEN len(delivery_towns) = 1 THEN delivery_towns[1] END                             AS city_derived,
    CASE WHEN len(divisions) = 1 AND divisions[1] ILIKE '% City Division' THEN 'india_post_city_division'
         WHEN len(delivery_towns) = 1 THEN 'india_post_single_delivery_office' END             AS city_method,
    divisions, delivery_towns, postal_districts, postal_states
FROM per_pin;

-- Localities for address matching: names of delivery post offices (PO/HO, not village branch offices)
-- in each postal district, with the city their pincode resolves to. "Jaipur" itself is excluded because
-- addresses use it for the district as well as the city.
CREATE OR REPLACE TABLE ref.locality_keyword AS
SELECT lower(trim(regexp_replace(ip.office_name, '\s+(G\.?P\.?O|S\.?O|H\.?O|B\.?O|P\.?O)\.?(\s*\(.*\))?\s*$', '', 'i'))) AS keyword,
       ip.postal_district,
       min(pc.city_derived) AS city
FROM stg.india_post ip
JOIN ref.pincode_city pc USING (pincode)
WHERE ip.office_type IN ('PO', 'HO') AND pc.city_derived IS NOT NULL
GROUP BY 1, 2
HAVING count(DISTINCT pc.city_derived) = 1 AND length(keyword) >= 5 AND keyword <> 'jaipur';

-- District groups: labels that sources use for one district, grouped by a documented decision
-- (data/reference/ref_district_source_group.csv, e.g. the scheme districts Jaipur1/Jaipur2 -> Jaipur).
-- A label without a row stays as recorded. This groups source labels; it is not a current-LGD mapping.
CREATE OR REPLACE TABLE ref.district_source_group AS
SELECT source_key, district_source, district_group, basis, decided_by, decided_on
FROM read_csv(getvariable('reference_dir') || '/ref_district_source_group.csv', all_varchar = true, header = true);

-- Pilot records: every hospital-level source's records in the pilot state and district group, harmonised.
-- Geography is dual: district_source keeps what each source says; district_current is filled only
-- from a reliable mapping. No reliable mapping exists yet, so it is NULL with the reason recorded.
-- Variables set by the build: pilot_state, pilot_district.
CREATE OR REPLACE TABLE stg.pilot_record_base AS
WITH r AS (
    SELECT source_key, source_record_id, name_raw, address_raw, location_raw,
           pincode, state_source, district_source, ownership_raw,
           CAST(NULL AS VARCHAR) AS list_category, CAST(NULL AS VARCHAR) AS suspended_raw,
           DATE '2016-05-31' AS as_of_date,
           'May 2016 (content of the National Hospital Directory)' AS as_of_label,
           'self_reported_directory' AS evidence_type
    FROM stg.nhd
    UNION ALL BY NAME
    SELECT source_key, source_record_id, name_raw, address_raw, CAST(NULL AS VARCHAR) AS location_raw,
           pincode_in_address AS pincode, 'Rajasthan' AS state_source, district_source, list_category AS ownership_raw,
           list_category, CAST(NULL AS VARCHAR) AS suspended_raw,
           CASE WHEN list_category = 'Central Government' THEN DATE '2021-02-13' ELSE DATE '2022-09-12' END AS as_of_date,
           CASE WHEN list_category = 'Central Government' THEN 'As on 13-02-2021 (stated in the list)'
                ELSE 'On or before 12-09-2022 (file date; the list states no date)' END AS as_of_label,
           'scheme_empanelment_list' AS evidence_type
    FROM stg.maay_list
    UNION ALL BY NAME
    SELECT source_key, source_record_id, name_raw, address_raw, CAST(NULL AS VARCHAR) AS location_raw,
           pincode_in_address AS pincode, 'Rajasthan' AS state_source, district_source, ownership_raw,
           CAST(NULL AS VARCHAR) AS list_category, suspended_raw,
           CAST(retrieved_at_utc AS DATE) AS as_of_date,
           'Search on ' || strftime(retrieved_at_utc, '%d-%m-%Y') || ' (MAA Yojana live search)' AS as_of_label,
           'scheme_live_search' AS evidence_type
    FROM stg.maay_live
), grouped AS (
    SELECT r.*,
           coalesce(g.district_group, r.district_source)                                   AS district_group,
           CASE WHEN g.district_group IS NULL THEN 'as_recorded' ELSE 'documented_grouping' END AS district_group_method
    FROM r
    LEFT JOIN ref.district_source_group g
           ON g.source_key = r.source_key AND lower(g.district_source) = lower(r.district_source)
)
SELECT * FROM grouped
WHERE lower(state_source) = lower(getvariable('pilot_state'))
  AND lower(district_group) = lower(getvariable('pilot_district'));

-- City from address text: the record's name/address mentions India Post localities of its postal
-- district that all resolve to one city. Used only when the pincode gives no city.
CREATE OR REPLACE TABLE stg.address_city AS
SELECT b.source_key, b.source_record_id,
       list_sort(list_distinct(list(k.keyword))) AS matched_localities,
       min(k.city) AS address_city,
       count(DISTINCT k.city) AS cities_matched
FROM stg.pilot_record_base b
JOIN ref.locality_keyword k
  ON upper(b.district_group) LIKE k.postal_district || '%'
 AND regexp_matches(lower(coalesce(b.name_raw, '') || ' ' || coalesce(b.address_raw, '') || ' ' || coalesce(b.location_raw, '')),
                    '(^|[^a-z])' || k.keyword || '([^a-z]|$)')
GROUP BY 1, 2;

CREATE OR REPLACE TABLE stg.pilot_record AS
SELECT
    r.*,
    own.value_standardized                                                     AS ownership_std,
    CASE WHEN r.pincode IN (SELECT pincode FROM stg.pincode_known) THEN r.pincode END AS pincode_valid,
    pc.city_derived                                                            AS city_from_pincode,
    CASE WHEN ac.cities_matched = 1 THEN ac.address_city END                   AS city_from_address,
    ac.matched_localities,
    coalesce(pc.city_derived, CASE WHEN ac.cities_matched = 1 THEN ac.address_city END) AS city_derived,
    coalesce(pc.city_method, CASE WHEN ac.cities_matched = 1 THEN 'address_keyword' END) AS city_method,
    s.state_code_lgd,
    s.state_name                                                               AS state_name_lgd,
    CAST(NULL AS INTEGER)                                                      AS district_current_code_lgd,
    CAST(NULL AS VARCHAR)                                                      AS district_current,
    'No reliable mapping to current LGD districts: Rajasthan boundaries changed in 2023-24; '
      || 'India Post still files these pincodes under JAIPUR and the LGD village-pincode table could not be downloaded (HTTP 500, 2026-09-25).'
                                                                               AS district_current_note
FROM stg.pilot_record_base r
LEFT JOIN ref.value_map own
       ON own.source_key = r.source_key AND own.attribute = 'ownership' AND own.value_raw = r.ownership_raw
LEFT JOIN ref.pincode_city pc
       ON pc.pincode = r.pincode
LEFT JOIN stg.address_city ac
       ON ac.source_key = r.source_key AND ac.source_record_id = r.source_record_id
LEFT JOIN stg.lgd_state s
       ON lower(s.state_name) = lower(r.state_source);
