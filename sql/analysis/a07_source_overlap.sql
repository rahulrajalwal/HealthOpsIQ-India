-- title: Source overlap after entity resolution
-- question: How many pilot hospitals rest on each combination of sources, and how confident are the links?
-- note: A hospital with several sources was linked by the rules in src/transformation/entity_resolution.py; pending_review counts hospitals with a candidate match that a person still has to decide.
SELECT array_to_string(sources, ' + ')                                AS sources,
       count(*)                                                       AS hospitals,
       count(*) FILTER (WHERE match_confidence = 'high')              AS high_confidence,
       count(*) FILTER (WHERE match_confidence = 'medium')            AS medium_confidence,
       count(*) FILTER (WHERE match_confidence = 'single record')     AS single_record,
       count(*) FILTER (WHERE possible_duplicate_pending_review)      AS pending_review
FROM mart.hospital
GROUP BY ALL
ORDER BY hospitals DESC;
