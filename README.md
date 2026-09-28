# HealthOpsIQ India: Power BI report and SQL model

Hospital discovery and comparison on **official Indian public data**. The pilot covers Rajasthan → Jaipur, with Orthopaedics and Physical Medicine & Rehabilitation (PMR).

This repository holds two parts of the project:
- the **SQL model**, which cleans and joins the sources;
- the **Power BI report**, built on top of it.

> HealthOpsIQ India is an informational and analytical prototype. Hospital information and comparisons are based on the underlying public data sources and should not be interpreted as medical advice.

## What is inside

| Folder | Contents |
|---|---|
| `sql/` | DuckDB SQL in layers:<br>`01_landing` → `02_staging` → `03_cleaning` → `04_standardization` → `06_model` → `07_marts` (star schema) → `08_quality_checks` (53 checks).<br>Step 05 (entity resolution) is Python and not included.<br>`analysis/` holds 11 queries, e.g. the location funnel, speciality filters, PMR vs physiotherapy, the two-hospital comparison, source overlap, evidence age and field coverage. |
| `powerbi/HealthOpsIQ__India.pbix` | The report (three pages, in progress). Users can:<br>• filter hospitals by state, city, speciality and ownership;<br>• open one hospital's details and compare it side by side with another;<br>• see the source and date behind every value. |
| `powerbi/build_kit/` | The model as copy-paste files:<br>• Power Query load script (12 tables);<br>• model settings (11 relationships);<br>• 54 DAX measures;<br>• DAX validation queries, with expected values. |
| `powerbi/theme/` | Dark and light report themes (colour-blind-safe palette). |

## The data

- **Scale:** 826 source records become 769 Jaipur hospitals once records are matched across sources.
- **Model:** a star schema around `hospital` (speciality, attribute, source and state dimensions). Every value keeps its source and as-of date.
- **Sources:**
  - National Hospital Directory (data.gov.in, Government Open Data License – India);
  - MAA Yojana empanelment lists and hospital search (Rajasthan State Health Assurance Agency, Government of Rajasthan).
- **No ratings, reviews or rankings.** No official source publishes them, so none are shown or invented.
- **Opening the report:** open `powerbi/HealthOpsIQ__India.pbix` in Power BI Desktop; the data is embedded. Refreshing it needs the full project's data folder.
- **Not included:** raw source files. This repository is private because the MAA Yojana portal states no reuse terms.

## Tools

DuckDB SQL · Power BI Desktop (Power Query M, DAX) · Python (pipeline, not included)
