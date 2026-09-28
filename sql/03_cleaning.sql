-- 03_cleaning.sql
-- Tokenise specialities and validate pincodes. Raw tokens are kept exactly as written.

-- Normal form used to match speciality spellings to data/reference/ref_specialty_map.csv.
CREATE OR REPLACE MACRO specialty_norm(x) AS lower(regexp_replace(regexp_replace(trim(x), '[:.]+$', ''), '\s+', ' ', 'g'));

-- One row per speciality token per source record:
--   NHD: free text split on commas, semicolons and line breaks (real or literal "\n");
--   MAA Yojana lists: pipe-separated scheme specialities;
--   MAA Yojana live search: the speciality that the search was run for.
CREATE OR REPLACE TABLE stg.specialty_token AS
WITH src AS (
    SELECT source_key, source_record_id,
           string_split_regex(replace(replace(specialties_raw, chr(10), ','), '\n', ','), '[,;]') AS parts
    FROM stg.nhd WHERE specialties_raw IS NOT NULL
    UNION ALL
    SELECT source_key, source_record_id, string_split(specialties_raw, '|')
    FROM stg.maay_list WHERE specialties_raw IS NOT NULL
    UNION ALL
    SELECT source_key, source_record_id, [specialty_filter_raw]
    FROM stg.maay_live WHERE specialty_filter_raw IS NOT NULL
), tokens AS (
    SELECT source_key, source_record_id, unnest(parts) AS part, generate_subscripts(parts, 1) AS token_index
    FROM src
)
SELECT
    source_key,
    source_record_id,
    token_index,
    trim(regexp_replace(part, '\s+', ' ', 'g'))                                              AS specialty_raw,
    specialty_norm(part)                                                                     AS specialty_raw_normalized
FROM tokens
WHERE trim(part) <> '';

-- Pincodes that exist in the India Post directory.
CREATE OR REPLACE TABLE stg.pincode_known AS
SELECT DISTINCT pincode FROM stg.india_post WHERE regexp_full_match(pincode, '[1-9][0-9]{5}');
