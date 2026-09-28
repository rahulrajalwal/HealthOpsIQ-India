-- title: Location-first funnel: State -> District -> City
-- question: How many pilot hospitals does each step of the location hierarchy lead to, and how many cannot be placed in a city?
-- note: District is shown as the sources record it, with the documented grouping of the MAA Yojana scheme districts Jaipur1/Jaipur2 under Jaipur (placed_by_grouping counts hospitals known only under those labels); district_current stays empty until a reliable mapping exists. City is derived from India Post data or left empty, never guessed.
-- show: 15
SELECT state_name                                       AS state,
       district_group                                   AS district_as_recorded,
       coalesce(city_derived, '(city not derivable)')   AS city_derived,
       count(*)                                         AS hospitals,
       count(*) FILTER (WHERE district_group_method = 'documented_grouping') AS placed_by_grouping,
       count(*) FILTER (WHERE has_orthopaedics)         AS with_orthopaedics,
       count(*) FILTER (WHERE has_pmr)                  AS with_pmr,
       count(*) FILTER (WHERE has_physiotherapy)        AS with_physiotherapy_explicit
FROM mart.hospital
GROUP BY ALL
ORDER BY hospitals DESC, city_derived;
