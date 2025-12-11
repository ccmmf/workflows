#!/usr/bin/env Rscript

# Standalone command-line adapter for convert_era5_nc_to_clim function from workflow_functions.R
# This script sources workflow_functions.R, parses command-line arguments using the
# exact same argument parsing as the original 01_ERA5_nc_to_clim.R, and builds the
# required data structures to pass into the workflow_functions.R version.

# Source the workflow functions
source("../tools/workflow_functions.R")

# Argument parsing section (exact copy from 01_ERA5_nc_to_clim.R)
options <- list(
  optparse::make_option("--site_era5_path",
    default = "data_raw/ERA5_nc",
    help = paste(
      "Path to your existing ERA5 data in PEcAn CF format, organized as",
      "single-site, single-year netcdfs in subdirectories per ensemble member.",
      "Files should be named",
      "'<site_era5_path>/ERA5_<siteid>_<ensid>/ERA5.<ensid>.<year>.nc'"
    )
  ),
  optparse::make_option("--site_sipnet_met_path",
    default = "data/ERA5_SIPNET",
    help = paste(
      "Output path:",
      "single-site, multi-year Sipnet clim files, one per ensemble member.",
      "Files will be named",
      "<site_sipnet_met_path>/<siteid>/ERA5.<ensid>.<start>.<end>.clim"
    )
  ),
  optparse::make_option("--site_info_file",
    default = "site_info.csv",
    help = "CSV file with one row per location. Only the `id` column is used",
  ),
  optparse::make_option("--start_date",
    default = "2016-01-01",
    help = "Date to begin clim file",
  ),
  optparse::make_option("--end_date",
    default = "2023-12-31",
    help = "Date to end clim file",
  ),
  optparse::make_option("--n_cores",
    default = 1L,
    help = "number of CPUs to use in parallel",
  ),
  optparse::make_option("--parallel_strategy",
    default = "multisession",
    help = "Strategy for parallel conversion, passed to future::plan()",
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

## ---------------------------------------------------------
# Build site_combinations data frame using the helper function from workflow_functions.R
# This replicates the logic from the original script which does:
#   site_info |> dplyr::rename(site_id = id) |> dplyr::cross_join(data.frame(ens_id = 1:10))
# The original script hardcodes ensemble members 1:10, so we do the same here.

site_combinations <- build_era5_site_combinations(
  site_info_file = args$site_info_file,
  start_date = args$start_date,
  end_date = args$end_date,
  ensemble_members = 1:10
)

## ---------------------------------------------------------
# Call the convert_era5_nc_to_clim function from workflow_functions.R
convert_era5_nc_to_clim(
  site_combinations = site_combinations,
  site_era5_path = args$site_era5_path,
  site_sipnet_met_path = args$site_sipnet_met_path,
  n_workers = as.integer(args$n_cores)
)

