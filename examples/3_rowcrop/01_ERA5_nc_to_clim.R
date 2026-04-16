#!/usr/bin/env Rscript

# Converts ERA5 meteorology data from PEcAn's standard netCDF format
# to Sipnet `clim` driver files.

# This is basically a thin wrapper around `met2model.SIPNET()`.
# Only the filenames are specific to ERA5 by assuming each file is named
# "ERA5.<ens_id>.<year>nc" with ens_id between 1 and 10.

## --------- runtime values: change for your system and simulation ---------

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


# ----------- end system-specific ---------------------------------


future::plan(args$parallel_strategy, workers = args$n_cores)

site_info <- read.csv(args$site_info_file)
site_info$start_date <- args$start_date
site_info$end_date <- args$end_date


file_info <- site_info |>
  dplyr::rename(site_id = id) |>
  dplyr::cross_join(data.frame(ens_id = 1:10))

if (!dir.exists(args$site_sipnet_met_path)) {
  dir.create(args$site_sipnet_met_path, recursive = TRUE)
}
furrr::future_pwalk(
  file_info,
  function(site_id, start_date, end_date, ens_id, ...) {
    PEcAn.SIPNET::met2model.SIPNET(
      in.path = file.path(
        args$site_era5_path,
        paste("ERA5", site_id, ens_id, sep = "_")
      ),
      start_date = args$start_date,
      end_date = args$end_date,
      in.prefix = paste0("ERA5.", ens_id),
      outfolder = file.path(args$site_sipnet_met_path, site_id)
    )
  }
)
