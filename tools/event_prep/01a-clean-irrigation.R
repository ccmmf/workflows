#!/usr/bin/env Rscript

# Adapted from a more generic script maintained as part of PEcAn.
# Its path in the PEcAn repository is workflows/preprocess-event-parquet/01a-clean-irrigation.R.
# Modifications added here: argument parsing, filtering to target sites,
# adding ensemble id if not present

## ---------------------- parse command-line options --------------------------
options <- list(
  optparse::make_option("--irr_path",
    default = "data_raw/management/irrigation/v1.0",
    help = "Directory containing Parquet files of irrigation events"
  ),
  optparse::make_option("--outdir",
    default = "data/management/irrigation",
    help = paste(
      "Directory to write cleaned irrigation events.",
      "Format will be Parquet organized by ensemble member,",
      "with subdirectories named in 'hive partion' style."
    )
  ),
  optparse::make_option("--site_info_path",
    default = "site_info.csv",
    help = "CSV giving ids to be extracted. Only column 'field_id' is used"
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

## -------------------------- end option parsing ------------------------------

dir.create(args$outdir, showWarnings = FALSE, recursive = TRUE)
site_info <- read.csv(args$site_info_path)
siteids <-  site_info$field_id |>
  unique() |>
  glue::glue_collapse(",")

dbdir <- tempfile("duckdb", fileext = ".duckdb")
conn <- DBI::dbConnect(duckdb::duckdb(dbdir = dbdir))
on.exit({
  DBI::dbDisconnect(conn, shutdown = TRUE)
  unlink(dbdir, recursive = TRUE)
}, add = TRUE)

# Cast ensemble ID to an enum to accelerate and reduce the memory pressure of
# the sort.
# ...and if ensemble ID doesn't exist yet, add it as a constant.
irr <- arrow::open_dataset(args$irr_path)
if ("ens_id" %in% colnames(irr)) {
  distinct_ensid_clause <- glue::glue(
    "SELECT DISTINCT ens_id FROM read_parquet('{args$irr_path}')"
  )
  qry_ensid_clause <- "ens_id"
} else {
  distinct_ensid_clause <- "'irr_ens_001'"
  qry_ensid_clause <- "'irr_ens_001'"
}
DBI::dbExecute(conn, glue::glue("
  CREATE OR REPLACE TYPE ens_id_enum AS ENUM (
    {distinct_ensid_clause}
  )
  "
))

method_join_clause <- ""
if (! "method" %in% colnames(irr)) {
  PEcAn.logger::logger.warn(
    "No `method` column in irrigation data.",
    "Assuming 'flood' for all sites whose initial PFT is 'rice',",
    "and 'canopy' for all other sites."
  )
  method_table <- site_info |>
    dplyr::mutate(
      method = dplyr::if_else(
        condition = site.pft == "rice",
        true = "flood",
        false = "canopy",
        missing = "canopy"
      )
    ) |>
    dplyr::distinct(parcel_id, method)
  duckdb::duckdb_register(conn, "sites_methods", method_table)
  method_join_clause <- "LEFT JOIN sites_methods USING (parcel_id)"
}

# Now, sort and write the (partitioned) parquet output
DBI::dbExecute(conn, glue::glue("
  COPY (
    SELECT
      CAST (parcel_id AS INTEGER) AS site_id,
      CAST ({qry_ensid_clause} AS ens_id_enum) AS event_member_id,
      date,
      CAST (amount_mm AS DECIMAL(6, 2)) AS amount_mm,
      method
    FROM read_parquet('{args$irr_path}')
    {method_join_clause}
    WHERE site_id IN ({siteids})
    ORDER BY event_member_id, site_id, date
  ) TO
  '{args$outdir}/irrigation.parquet' 
  (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE, PARTITION_BY (event_member_id))
  "
))
