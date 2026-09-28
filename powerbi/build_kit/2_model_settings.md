# 2 · Model settings (docs/POWERBI_BUILD_GUIDE.md, steps 5–7)

Generated from `src/powerbi/model_definition.py`; do not edit by hand.

## Relationships (Model view → Manage relationships → New)

Every relationship is **many-to-one (*:1)** and **active**. Only no. 3 filters in both directions.

| No. | From table (many) | Column | To table (one) | Column | Cross-filter direction |
|---:|---|---|---|---|---|
| 1 | `hospital` | `state_code_lgd` | `dim_state` | `state_code_lgd` | **Single** |
| 2 | `state_context` | `state_code_lgd` | `dim_state` | `state_code_lgd` | **Single** |
| 3 | `hospital_specialty` | `canonical_hospital_key` | `hospital` | `canonical_hospital_key` | **Both** |
| 4 | `hospital_specialty` | `specialty_standardized` | `dim_specialty` | `specialty_standardized` | **Single** |
| 5 | `pmr_package` | `specialty_standardized` | `dim_specialty` | `specialty_standardized` | **Single** |
| 6 | `hospital_attribute` | `canonical_hospital_key` | `hospital` | `canonical_hospital_key` | **Single** |
| 7 | `hospital_attribute` | `attribute` | `dim_attribute` | `attribute` | **Single** |
| 8 | `hospital_attribute` | `source_key` | `source` | `source_key` | **Single** |
| 9 | `hospital_source_record` | `canonical_hospital_key` | `hospital` | `canonical_hospital_key` | **Single** |
| 10 | `hospital_source_record` | `source_key` | `source` | `source_key` | **Single** |
| 11 | `hospital_possible_match` | `canonical_hospital_key` | `hospital` | `canonical_hospital_key` | **Single** |

Deliberately **not** related: `compare_b` (the Hospital B selector), `check_result`, `_Measures`.
`hospital_specialty` is not related to `source`: that would give a second filter path from `source` into
`hospital_attribute` through the two-way relationship, and Power BI would switch a relationship off.

## Hide in report view (keys and technical columns)

| Table | Columns to hide |
|---|---|
| `hospital` | `build_id`, `sources`, `state_code_lgd`, `state_name` |
| `dim_state` | `build_id`, `state_code_lgd` |
| `dim_specialty` | `build_id` |
| `dim_attribute` | `attribute`, `build_id`, `sort_order` |
| `source` | `build_id`, `source_key` |
| `hospital_attribute` | `attribute`, `build_id`, `canonical_hospital_key`, `source`, `source_key` |
| `hospital_specialty` | `build_id`, `canonical_hospital_key`, `source_key`, `specialty_standardized` |
| `hospital_source_record` | `build_id`, `canonical_hospital_key`, `source`, `source_key` |
| `hospital_possible_match` | `build_id`, `canonical_hospital_key`, `possible_match_key` |
| `state_context` | `build_id`, `indicator`, `state_code_lgd` |
| `pmr_package` | `build_id`, `specialty_standardized` |
| `check_result` | `build_id` |

## Sort by column, data category and hierarchy

- Sort `dim_attribute[attribute_label]` by `sort_order` (Column tools → Sort by column).
- Data category of `dim_state[state_name]`: **State or Province** (Column tools → Data category).
- Data category of `hospital[city_derived]`: **City** (Column tools → Data category).
- Data category of `hospital[city_display]`: **City** (Column tools → Data category).
- Data category of `hospital[pincode]`: **Postal code** (Column tools → Data category).
- Hierarchy `Location` on `hospital`: right-click `district_group` → Create hierarchy, then add `city_display`, `hospital_name` (in that order).

## Display folders of `hospital` (optional; Properties → Display folder)

| Folder | Columns |
|---|---|
| Identity | `canonical_hospital_key`, `hospital_name`, `hospital_name_source`, `address` |
| Location | `pincode`, `pincode_source`, `city_derived`, `city_display`, `city_method`, `city_method_display`, `state_code_lgd`, `state_name`, `district_group`, `district_group_method`, `district_source_primary`, `district_source_values`, `district_current`, `district_current_note` |
| Ownership and type | `ownership`, `ownership_display`, `ownership_source`, `ownership_as_of`, `ownership_sources_disagree`, `facility_type`, `facility_type_as_of` |
| MAA Yojana scheme | `maa_yojana_empanelled`, `empanelment_source`, `empanelment_as_of`, `scheme_suspension_status`, `suspension_as_of`, `nabh_status_scheme_raw`, `nabh_status_scheme`, `nabh_status_as_of`, `beds_declared`, `beds_as_of` |
| Specialities | `has_orthopaedics`, `has_pmr`, `has_physiotherapy`, `specialties_standardized`, `specialty_raw_values` |
| Provenance and matching | `sources`, `source_combination`, `source_combination_short`, `source_count`, `record_count`, `match_confidence`, `possible_duplicate_pending_review`, `earliest_evidence_date`, `latest_evidence_date`, `latest_evidence`, `latest_evidence_short`, `profile_completeness` |

## Calculated tables (Modeling → New table; paste the whole line)

**compare_b**: Selector for Hospital B on the comparison page (deliberately not related to other tables).

```dax
compare_b = SELECTCOLUMNS ( hospital, "Hospital B", hospital[hospital_name] & " (" & COALESCE ( hospital[city_derived], "city unknown" ) & ") " & hospital[canonical_hospital_key], "key_b", hospital[canonical_hospital_key] )
```

**_Measures**: Holds every measure of the report, in display folders.

```dax
_Measures = ROW ( "measure_table", 0 )
```

Then hide `key_b` and `_Measures[measure_table]`.

## Table descriptions (optional; Properties → Description)

| Table | Description |
|---|---|
| `hospital` | One row per hospital after entity resolution: identity, location, the latest value of each attribute with its source and date, speciality flags and match status. |
| `dim_state` | States and Union Territories (Local Government Directory). Filters hospitals and state-level context. |
| `dim_specialty` | Standard specialities of the pilot filter, with what each covers and excludes. |
| `dim_attribute` | Attributes that evidence rows describe, in display order: the rows of profile and comparison tables. |
| `source` | Registered sources: publisher, reference period, retrieval date, licence and how the pilot uses each. |
| `hospital_attribute` | One row per attributed value with its source and as-of date. Values from different sources and dates sit side by side; nothing is overwritten. |
| `hospital_specialty` | Hospital × speciality value as the source writes it, with the standard name where the pilot maps one. The bridge that lets the speciality slicer filter hospitals. |
| `hospital_source_record` | The source records behind each hospital: how each source names and places it, and how the record was matched. |
| `hospital_possible_match` | Hospitals that may be the same facility as another listing; a person has not decided yet. |
| `state_context` | Official state-level indicators (Rajya Sabha answers on data.gov.in), each with its own reference date. |
| `pmr_package` | Packages listed under MAA Yojana 'PMR -Phase 4': the evidence that PMR is rehabilitation medicine, not physiotherapy. |
| `check_result` | Data-quality checks of the build (pass/fail rules, warnings, measurements). |
