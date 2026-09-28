-- title: Physiotherapy is not PMR
-- question: What does the pilot find for physiotherapy, and what evidence decides that MAA Yojana 'PMR -Phase 4' is reported as rehabilitation (PMR) rather than physiotherapy?
-- note: The package names were read from the official search page's package list for 'PMR -Phase 4' (the page truncates long names).
SELECT 'Jaipur hospitals with physiotherapy named explicitly' AS measure, count(*) FILTER (WHERE has_physiotherapy) AS value FROM mart.hospital
UNION ALL
SELECT 'Jaipur hospitals with PMR', count(*) FILTER (WHERE has_pmr) FROM mart.hospital
UNION ALL
SELECT 'Jaipur PMR hospitals, ownership ' || coalesce(ownership, 'Unknown'), count(*) FROM mart.hospital WHERE has_pmr GROUP BY ownership
UNION ALL
SELECT 'NHD records, all India, naming physiotherapy explicitly', count(DISTINCT source_record_id)
FROM stg.specialty_std WHERE source_key = 'nhd' AND specialty_standardized = 'Physiotherapy'
UNION ALL
SELECT 'Packages the scheme lists under PMR -Phase 4', count(*) FROM ref.pmr_package
UNION ALL
SELECT 'PMR packages whose name mentions rehabilitation', count(*) FILTER (WHERE mentions_rehabilitation) FROM ref.pmr_package
UNION ALL
SELECT 'PMR packages whose name mentions physiotherapy', count(*) FILTER (WHERE mentions_physiotherapy) FROM ref.pmr_package
UNION ALL
SELECT 'PMR packages marked as reserved for government hospitals', count(*) FILTER (WHERE marked_government_reserve) FROM ref.pmr_package;
