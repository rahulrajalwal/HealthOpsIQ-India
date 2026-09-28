// 1 · Load the tables (docs/POWERBI_BUILD_GUIDE.md, step 3)
//
// First create the parameter: Home → Transform data → Manage parameters → New
//   Name: DataFolder   Type: Text   Current value (with the final backslash):
//   C:\Users\acer\Documents\Data_Analytics_Project\HealthOpsIQ__India\data\processed\powerbi\
//
// Then, for each table below: Home → New source → Blank query → Advanced editor → replace
// everything with the block → Done → rename the query to the table name shown (exactly).

// ── hospital  (769 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "hospital.parquet" ) )
in
    Source

// ── dim_state  (36 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "dim_state.parquet" ) )
in
    Source

// ── dim_specialty  (3 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "dim_specialty.parquet" ) )
in
    Source

// ── dim_attribute  (9 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "dim_attribute.parquet" ) )
in
    Source

// ── source  (14 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "source.parquet" ) )
in
    Source

// ── hospital_attribute  (6,207 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "hospital_attribute.parquet" ) )
in
    Source

// ── hospital_specialty  (3,720 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "hospital_specialty.parquet" ) )
in
    Source

// ── hospital_source_record  (826 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "hospital_source_record.parquet" ) )
in
    Source

// ── hospital_possible_match  (300 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "hospital_possible_match.parquet" ) )
in
    Source

// ── state_context  (286 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "state_context.parquet" ) )
in
    Source

// ── pmr_package  (64 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "pmr_package.parquet" ) )
in
    Source

// ── check_result  (53 rows) ─────────────────────────────
let
    Source = Parquet.Document ( File.Contents ( DataFolder & "check_result.parquet" ) )
in
    Source
