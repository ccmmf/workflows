#!/usr/bin/env Rscript

# Adapted from a more generic script maintained as part of PEcAn.
# Its path in the PEcAn repository is workflows/preprocess-event-parquet/01a-clean-irrigation.R.
# Modifications added here: argument parsing, filtering to target sites.

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
siteids <- read.csv(args$site_info_path) |>
  _$field_id |>
  unique() |>
  glue::glue_collapse(",")

dbdir <- tempfile("duckdb", fileext = ".duckdb")
conn <- DBI::dbConnect(duckdb::duckdb(dbdir = dbdir))
on.exit({
  DBI::dbDisconnect(conn, shutdown = TRUE)
  unlink(dbdir, recursive = TRUE)
}, add = TRUE)

# UGLY hack to handle files with or without ensembling
ens_cast <- ""
ens_partition <- ""
evt_order <- ""
if ("ens_id" %in% colnames(arrow::open_dataset(args$irr_path))) {
  # Cast ensemble ID to an enum to accelerate and reduce the memory pressure of
  # the sort.
  DBI::dbExecute(conn, glue::glue("
    CREATE OR REPLACE TYPE ens_id_enum AS ENUM (
      SELECT DISTINCT ens_id FROM read_parquet('{args$irr_path}')
    )
    "
  ))
  ens_cast <- "CAST (ens_id AS ens_id_enum) AS event_member_id,"
  ens_partition <- ", PARTITION_BY (event_member_id)"
  evt_order <- "event_member_id, "
}

# Now, sort and write the (partitioned) parquet output
DBI::dbExecute(conn, glue::glue("
  COPY (
    SELECT
      CAST (parcel_id AS INTEGER) AS site_id,
      {ens_cast}
      date,
      CAST (amount_mm AS DECIMAL(6, 2)) AS amount_mm,
      method
    FROM read_parquet('{args$irr_path}')
    WHERE site_id IN ({siteids})
    ORDER BY {evt_order}site_id, date
  ) TO
  '{args$outdir}/irrigation.parquet' 
  (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE{ens_partition})
  "
))
