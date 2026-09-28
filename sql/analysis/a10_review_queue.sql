-- title: What entity resolution decides, and what it leaves to a person
-- question: How many candidate pairs did each rule accept, reject or send to review?
-- note: Pairs needing review are listed in reports/er_review_queue.csv; a person's decisions go into data/reference/er_decisions.csv and are applied on the next build.
SELECT decision,
       coalesce(rule, '-')                                  AS rule,
       count(*)                                             AS pairs,
       round(min(combined_score), 1)                        AS min_score,
       round(max(combined_score), 1)                        AS max_score,
       count(*) FILTER (WHERE kind_conflict)                AS facility_kind_conflicts,
       count(*) FILTER (WHERE numbers_conflict)             AS address_number_conflicts
FROM core.er_candidate
GROUP BY ALL
ORDER BY decision, pairs DESC;
