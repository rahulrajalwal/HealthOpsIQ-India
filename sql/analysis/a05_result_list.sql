-- title: Result list for one filter, without ranking
-- question: What would a user see for Rajasthan -> Jaipur -> city Jaipur -> Orthopaedics, and how is each row sourced?
-- note: Sorted alphabetically. No score, rating or "best" order is computed; profile_completeness only says how much the sources tell us about the hospital.
-- show: 12
SELECT hospital_name,
       ownership,
       maa_yojana_empanelled                AS empanelled,
       nabh_status_scheme_raw               AS nabh_status_reported_by_scheme,
       beds_declared,
       empanelment_as_of,
       profile_completeness,
       possible_duplicate_pending_review    AS pending_review
FROM mart.hospital
WHERE state_name = 'Rajasthan' AND district_group = 'Jaipur' AND city_derived = 'Jaipur' AND has_orthopaedics
ORDER BY hospital_name;
