-- title: How old is the evidence?
-- question: What dates does the pilot's evidence carry, and for how many hospitals is each the most recent evidence?
-- note: As-of dates are what each source states (or, for undated lists, the file date). They are shown next to values instead of being merged away.
SELECT e.evidence_type,
       e.as_of_label,
       count(DISTINCT e.canonical_hospital_key)                                                      AS hospitals_with_evidence,
       count(DISTINCT e.canonical_hospital_key) FILTER (WHERE h.latest_evidence_date = e.as_of_date) AS hospitals_whose_latest_evidence,
       count(*)                                                                                      AS evidence_rows
FROM core.fact_hospital_evidence e
JOIN mart.hospital h USING (canonical_hospital_key)
GROUP BY ALL
ORDER BY min(e.as_of_date), e.evidence_type;
