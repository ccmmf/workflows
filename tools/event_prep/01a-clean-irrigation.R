#!/usr/bin/env Rscript

# Adapted from a more generic script maintained as part of PEcAn.
# Its path in the PEcAn repository is workflows/preprocess-event-parquet/01a-clean-irrigation.R.
# Modifications added here: argument parsing.

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

dbdir <- file.path(Sys.getenv("TMPDIR", "/tmp"), "temp.duckdb")
conn <- DBI::dbConnect(duckdb::duckdb(dbdir = dbdir))

# Cast ensemble ID to an enum to accelerate and reduce the memory pressure of
# the sort.
DBI::dbExecute(conn, glue::glue("
  CREATE OR REPLACE TYPE ens_id_enum AS ENUM (
    SELECT DISTINCT ens_id FROM read_parquet('{args$irr_path}')
  )
  "
))

# Now, sort and write the (partitioned) parquet output
DBI::dbExecute(conn, glue::glue("
  COPY (
    SELECT
      CAST (parcel_id AS INTEGER) AS site_id,
      CAST (ens_id AS ens_id_enum) AS event_member_id,
      date,
      CAST (amount_mm AS DECIMAL(6, 2)) AS amount_mm,
      method
    FROM read_parquet('{args$irr_path}')
    ORDER BY event_member_id, site_id, date
  ) TO
  '{args$outdir}/irrigation.parquet' 
  (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE, PARTITION_BY (event_member_id))
  "
))
