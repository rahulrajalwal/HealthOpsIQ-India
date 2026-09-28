-- title: Rajasthan in official state-level context
-- question: What do official state-level figures say about Rajasthan, and how current are they?
-- note: Rajya Sabha answers published on data.gov.in. Each figure keeps its own reference date; they are context for the pilot, not hospital-level data.
SELECT indicator, value, reference_period, source_key
FROM mart.state_context
WHERE state = 'Rajasthan'
ORDER BY source_key, indicator;
