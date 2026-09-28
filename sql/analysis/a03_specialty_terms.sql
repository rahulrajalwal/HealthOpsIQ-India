-- title: Source spellings behind each standard speciality
-- question: Which exact source terms feed each pilot speciality, and which look-alike terms are deliberately left unmapped?
-- note: records_all_loaded counts records in everything loaded (the NHD covers all of India; the scheme lists cover Jaipur). Rows marked "(deliberately not mapped)" record a decision not to map; for example, orthodontics (dental) is not orthopaedics.
-- show: 40
WITH all_tokens AS (
    SELECT source_key, specialty_raw_normalized, count(*) AS records_all_loaded
    FROM stg.specialty_token GROUP BY ALL
), pilot_tokens AS (
    SELECT t.source_key, t.specialty_raw_normalized, count(*) AS records_jaipur_pilot
    FROM stg.specialty_token t
    JOIN stg.pilot_record p USING (source_key, source_record_id)
    GROUP BY ALL
)
SELECT coalesce(m.specialty_standardized, '(deliberately not mapped)') AS specialty_standardized,
       m.source_key,
       m.specialty_raw_normalized                                      AS source_term_normalised,
       coalesce(a.records_all_loaded, 0)                               AS records_all_loaded,
       coalesce(p.records_jaipur_pilot, 0)                             AS records_jaipur_pilot
FROM ref.specialty_map m
LEFT JOIN all_tokens a USING (source_key, specialty_raw_normalized)
LEFT JOIN pilot_tokens p USING (source_key, specialty_raw_normalized)
ORDER BY m.specialty_standardized NULLS LAST, records_all_loaded DESC, source_term_normalised;
