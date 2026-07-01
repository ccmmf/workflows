#!/usr/bin/env Rscript

# Creates an ensemble of PEcAn-formatted `events.JSON` containing all management
# events from all years of all the locations in `site_info.csv`,
# then divides these into Sipnet-formatted `events.in` for each site.
# Ensemble size is determined by the number of members in the management files.

## ---------------------- parse command-line options --------------------------
options <- list(
  optparse::make_option("--site_info_path",
    default = "site_info.csv",
    help = "CSV giving ids, locations, and PFTs for sites of interest"
  ),
  optparse::make_option("--raw_parquet_dir",
    default = "data_raw/management",
    help = paste(
      "Directory containing management inputs in Parquet format.",
      "Note: Code currently looks for subpaths that include hard-coded",
      "version numbers for each management type.",
      "If this path is empty, cleaning is skipped and clean Parquet files",
      " must already exist at the path specified by --clean_parquet_dir`."
    )
  ),
  optparse::make_option("--clean_parquet_dir",
    default = "data/management_ensembles",
    help = paste(
      "Directory containing management inputs cleaned and organized by ensemble member."
    )
  ),
  optparse::make_option("--event_outdir",
    default = "data/events",
    help = "directory to write events-*.in, events.json, and phenology.csv"
  ),
  optparse::make_option("--start_date",
    default = "2016-01-01",
    help = "Date to begin simulations"
  ),
  optparse::make_option("--end_date",
    default = "2023-12-31",
    help = "Date to end simulations"
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

library(tidyverse)

# TODO these probably deserve to be runtime args,
# but first better fix other version-specific assumptions below
mgmt_subdirs <- list(
  pheno = file.path(args$raw_parquet_dir, "phenology/v1.0"),
  plant = file.path(args$raw_parquet_dir, "planting/v1.0"),
  harv = file.path(args$raw_parquet_dir, "harvest/v1.0"),
  till = file.path(args$raw_parquet_dir, "tillage/v1.0"),
  irri = file.path(args$raw_parquet_dir, "irrigation/max_150/irrigation_all"), # "irrigation/v1.0"),
  fert = NULL, # TODO
  occ = NULL # TODO
)

if (!dir.exists(args$event_outdir)) {
  dir.create(args$event_outdir, recursive = TRUE)
}

cargs <- function(...) {
  paste0("--", ...names(), "=", list(...))
}

if (args$raw_parquet_dir != "") {
  PEcAn.logger::logger.info("Cleaning irrigation files")
  callr::rscript(
    "../../tools/event_prep/01a-clean-irrigation.R",
    cmdargs = cargs(
      irr_path = mgmt_subdirs$irri,
      outdir = args$clean_parquet_dir
    )
  )
  PEcAn.logger::logger.info("Cleaning other management files")
  callr::rscript(
    "../../tools/event_prep/01b-clean-other-events.R",
    cmdargs = cargs(
      pheno_dir = mgmt_subdirs$pheno,
      planting_dir = mgmt_subdirs$plant,
      harvest_dir = mgmt_subdirs$harv,
      tillage_dir = mgmt_subdirs$till,
      adjust_start = args$start_date,
      outdir = args$clean_parquet_dir
    )
  )
}

PEcAn.logger::logger.info("converting management files to events")
callr::rscript(
  "../../tools/event_prep/02-events-to-json-and-sipnet.R",
  cmdargs = cargs(
    site_info_path = args$site_info_path,
    parquet_dir = args$clean_parquet_dir,
    event_dir = args$event_outdir,
    start_date = args$start_date,
    end_date = args$end_date
  )
)

