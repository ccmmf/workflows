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
  optparse::make_option("--phenology_path",
    default = "data_raw/management/phenology/v1.0",
    help = "Parquet file or directory of Parquet files containing phenology events",
  ),
  optparse::make_option("--planting_path",
    default = "data_raw/management/planting/v1.0",
    help = "Parquet file or directory of Parquet files containing planting events",
  ),
  optparse::make_option("--harvest_path",
    default = "data_raw/management/harvest/v1.0",
    help = "Parquet file or directory of Parquet files containing harvest events",
  ),
  optparse::make_option("--tillage_path",
    default = "data_raw/management/tillage/v1.0",
    help = "Parquet file or directory of Parquet files containing tillage events",
  ),
  optparse::make_option("--irrigation_path",
    default = "data_raw/management/irrigation/v1.1",
    help = "Parquet file or directory of Parquet files containing tillage events",
  ),
  # TODO add fertilization and NCC here
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

# Locate tools/event_prep/ relative to this script's own file location, so it
# works regardless of the caller's working directory (magic-ensemble invokes
# with cwd = repo root; the README's manual workflow uses cwd = this directory).
this_file <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  normalizePath(sub("^--file=", "", grep("^--file=", cmd_args, value = TRUE)))
}
event_prep_dir <- normalizePath(file.path(dirname(this_file()), "..", "..", "tools", "event_prep"))

if (!dir.exists(args$event_outdir)) {
  dir.create(args$event_outdir, recursive = TRUE)
}

cargs <- function(...) {
  paste0("--", ...names(), "=", list(...))
}


PEcAn.logger::logger.info("Cleaning irrigation files")
callr::rscript(
  file.path(event_prep_dir, "01a-clean-irrigation.R"),
  cmdargs = cargs(
    irr_path = args$irrigation_path,
    outdir = args$clean_parquet_dir,
    site_info_path = args$site_info_path
  )
)
PEcAn.logger::logger.info("Cleaning other management files")
callr::rscript(
  file.path(event_prep_dir, "01b-clean-other-events.R"),
  cmdargs = cargs(
    site_info_path = args$site_info_path,
    pheno_dir = args$phenology_path,
    planting_dir = args$planting_path,
    harvest_dir = args$harvest_path,
    tillage_dir = args$tillage_path,
    adjust_start = args$start_date,
    outdir = args$clean_parquet_dir
  )
)


PEcAn.logger::logger.info("converting management files to events")
callr::rscript(
  file.path(event_prep_dir, "02-events-to-json-and-sipnet.R"),
  cmdargs = cargs(
    site_info_path = args$site_info_path,
    parquet_dir = args$clean_parquet_dir,
    event_dir = args$event_outdir,
    start_date = args$start_date,
    end_date = args$end_date
  )
)

