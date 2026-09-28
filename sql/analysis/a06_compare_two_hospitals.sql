-- title: Side-by-side comparison of two hospitals
-- question: How do two hospitals compare on every attribute the sources provide, with the source and date of each value?
-- note: The example pairs the first hospital (alphabetically) that two sources confirm with the first private Orthopaedics hospital that declares beds. Missing values read "Not available in pilot sources". No winner is computed.
SET VARIABLE hospital_a = (SELECT canonical_hospital_key FROM mart.hospital
                           WHERE has_orthopaedics AND source_count >= 2 ORDER BY hospital_name LIMIT 1);
SET VARIABLE hospital_b = (SELECT canonical_hospital_key FROM mart.hospital
                           WHERE has_orthopaedics AND ownership = 'Private' AND beds_declared IS NOT NULL ORDER BY hospital_name LIMIT 1);
WITH identity AS (
    SELECT canonical_hospital_key, label, sort_order, value, source
    FROM mart.hospital,
         LATERAL (VALUES ('Hospital', -5, hospital_name, hospital_name_source),
                         ('Address', -4, address, hospital_name_source),
                         ('City (derived)', -3, city_derived, city_method),
                         ('District (as recorded by sources)', -2, district_group || ' (' || district_source_values || ')', district_group_method),
                         ('Pincode', -1, pincode, pincode_source)) AS v(label, sort_order, value, source)
), evidence AS (
    SELECT e.canonical_hospital_key, a.attribute_label AS label, a.sort_order,
           string_agg(DISTINCT e.value_display, '; ' ORDER BY e.value_display) AS value,
           string_agg(DISTINCT e.source || ' (' || e.as_of_label || ')', '; ') AS source
    FROM mart.hospital_attribute e
    JOIN mart.dim_attribute a USING (attribute)
    GROUP BY ALL
), side AS (
    SELECT * FROM identity UNION ALL BY NAME SELECT * FROM evidence
), labels AS (
    SELECT DISTINCT label, sort_order FROM side
)
SELECT l.label                                                   AS attribute,
       coalesce(a.value, 'Not available in pilot sources')       AS hospital_a,
       a.source                                                  AS source_a,
       coalesce(b.value, 'Not available in pilot sources')       AS hospital_b,
       b.source                                                  AS source_b
FROM labels l
LEFT JOIN side a ON a.label = l.label AND a.canonical_hospital_key = getvariable('hospital_a')
LEFT JOIN side b ON b.label = l.label AND b.canonical_hospital_key = getvariable('hospital_b')
ORDER BY l.sort_order;
