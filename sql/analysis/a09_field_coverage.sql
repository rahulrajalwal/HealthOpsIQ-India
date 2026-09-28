-- title: Field coverage by source
-- question: What share of each source's Jaipur records carries the fields the product needs?
-- note: valid_pincode means a six-digit pincode that exists in the India Post directory. The scheme lists have no pincode field; pincodes are taken from their address text.
SELECT p.source_key,
       count(*)                                                          AS records,
       round(100.0 * avg((p.name_raw IS NOT NULL)::INT), 1)              AS name_pct,
       round(100.0 * avg((p.address_raw IS NOT NULL)::INT), 1)           AS address_pct,
       round(100.0 * avg((p.pincode_valid IS NOT NULL)::INT), 1)         AS valid_pincode_pct,
       round(100.0 * avg((p.city_derived IS NOT NULL)::INT), 1)          AS city_derived_pct,
       round(100.0 * avg((p.ownership_std IS NOT NULL)::INT), 1)         AS ownership_pct,
       round(100.0 * avg((t.source_record_id IS NOT NULL)::INT), 1)      AS any_speciality_pct
FROM stg.pilot_record p
LEFT JOIN (SELECT DISTINCT source_key, source_record_id FROM stg.specialty_token) t USING (source_key, source_record_id)
GROUP BY 1
ORDER BY records DESC;
