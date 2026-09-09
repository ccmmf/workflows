#!/usr/bin/env Rscript

# Converts Caladapt WRF meteorology data from PEcAn's standard netCDF format
# (each combination of site+ensemble member gets one file per year)
# to Sipnet `clim` driver files (each site_ens gets one ASCII file for the whole
# simulation interval).

# This is a thin wrapper around `met2model.SIPNET()` enforcing a filename
# convention that makes sense for gridded WRF data: Instead of the ensemble
# numbers seen in some other met code (eg ERA5), we use GCM name as ensemble id.
# Input files: `<nc_dir>/<gridid>/<GCM>.<scenario>.<yyyy>.nc`
# Output files: `<sipnet_dir>/<gridid>/<GCM>.<scenario>.<start_date>.<end_date>.clim`

# TODO:
# Does not currently encode WRF domain (aka resolution) anywhere other than the
# default folder names (which are only advisory).
# Should this be written into filenames for clarity?

options <- list(
  optparse::make_option("--nc_dir",
    default = "data_raw/wrf_45km_nc",
    help = paste(
      "Path to your existing WRF data in PEcAn CF format, organized as",
      "single-model, single-year netcdfs in subdirectories per grid cell.",
      "Files should be named",
      "'<nc_dir>/<gridid>/<model>.<scenario>.<year>.nc'"
    )
  ),
  optparse::make_option("--sipnet_dir",
    default = "data/WRF_45km_SIPNET",
    help = paste(
      "Output path:",
      "single-site, multi-year Sipnet clim files, one per ensemble member.",
      "Files will be named",
      "<sipnet_dir>/<gridid>/<model>.<scenario>.<start>.<end>.clim"
    )
  ),
  optparse::make_option("--cells_wanted_file",
    default = "data_raw/wrf_45km_nc/parcel_to_grid_d01.csv",
    help = paste(
      "CSV file with one row per location to be extracted.",
      "Only column `cell_id` is used."
    )
  ),
  optparse::make_option("--start_date",
    default = "2024-01-01",
    help = "Date to begin clim file"
  ),
  optparse::make_option("--end_date",
    default = "2051-12-31",
    help = "Date to end clim file"
  ),
  optparse::make_option("--models",
    default = paste0(
      "CESM2,CNRM-ESM2-1,EC-Earth3,EC-Earth3-Veg,",
      "FGOALS-g3,MIROC6,MPI-ESM1-2-HR,TaiESM1"
    ),
    help = paste(
      "Comma-separated list of GCMs to convert.",
      "See `caladaptaer::cae_models(\"WRF\")` for valid names."
    )
  ),
  optparse::make_option("--scenario",
    default = "ssp370",
    help = paste(
      "Climate scenario. See `caladaptaer::cae_scenarios(\"WRF\")`",
      "for valid values."
    )
  ),
  optparse::make_option("--n_cores",
    default = 1L,
    help = "number of CPUs to use in parallel"
  ),
  optparse::make_option("--parallel_strategy",
    default = "multisession",
    help = "Strategy for parallel conversion, passed to future::plan()"
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()




future::plan(args$parallel_strategy, workers = args$n_cores)

site_info <- read.csv(args$cells_wanted_file) |>
  dplyr::distinct(cell_id)
site_info$start_date <- args$start_date
site_info$end_date <- args$end_date

models <- strsplit(args$models, ",")[[1]] |>
  trimws()

file_info <- site_info |>
  dplyr::cross_join(data.frame(gcm = models))

if (!dir.exists(args$sipnet_dir)) {
  dir.create(args$sipnet_dir, recursive = TRUE)
}
furrr::future_pwalk(
  file_info,
  function(gcm, start_date, end_date, cell_id, ...) {
    PEcAn.SIPNET::met2model.SIPNET(
      in.path = file.path(args$nc_dir, cell_id),
      start_date = start_date,
      end_date = end_date,
      in.prefix = paste0(gcm, ".", args$scenario),
      outfolder = file.path(args$sipnet_dir, cell_id)
    )
  }
)
