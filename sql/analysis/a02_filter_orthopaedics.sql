-- title: Filter: Rajasthan -> Jaipur -> Orthopaedics
-- question: What does the Orthopaedics filter return for Jaipur, by ownership, scheme empanelment and scheme-reported NABH status?
-- note: NABH values are what the MAA Yojana list reports about each hospital, not data from NABH. "Empanelled" means found in a scheme source of the pilot.
SELECT coalesce(ownership, 'Unknown')                                                   AS ownership,
       count(*)                                                                         AS hospitals,
       count(*) FILTER (WHERE maa_yojana_empanelled)                                    AS maa_yojana_empanelled,
       count(*) FILTER (WHERE nabh_status_scheme_raw = 'Fully accredited NABH')         AS nabh_fully_accredited_as_reported,
       count(*) FILTER (WHERE nabh_status_scheme_raw = 'Pre-entry level NABH')          AS nabh_pre_entry_as_reported,
       count(*) FILTER (WHERE nabh_status_scheme_raw = 'Non accredited')                AS non_accredited_as_reported,
       count(*) FILTER (WHERE city_derived IS NULL)                                     AS city_unknown,
       median(beds_declared)                                                            AS median_beds_declared
FROM mart.hospital
WHERE state_name = 'Rajasthan' AND district_group = 'Jaipur' AND has_orthopaedics
GROUP BY ALL
ORDER BY hospitals DESC;
