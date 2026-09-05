#!/usr/bin/env Rscript

# Converts raw ERA5 ensemble netCDFs to PEcAn-standard met format,
# then from PEcAn-standard to Sipnet `clim` driver format.

# This was used (via wrapper script `run_ERA5_met_extract.sh`) to generate the
# met files provided in cccmmf_phase_1b_input_artifacts.tgz. See also
# `tools/run_CA_grid_ERA5_nc_extraction.R` for a one-shot extraction of all the
# California grid cells.

# Note that it was written targeting raw ERA5 files _as stored_ on the Dietze
# lab group server, collected over time by multiple lab members.
# In concept you can download additional ERA5 files using
# `PEcAn.data.atmosphere::download.ERA5.old()` and then convert them with this,
# but in practice the ECMWF API has had major recent changes and is no longer
# guaranteed to match the format this script expects.
# We are waiting for the API to stabilize again before updating the code.
# It may also work to download locations/years of interest via web:
# https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels

options <- list(
  optparse::make_option("--site_info_file",
    default = "site_info.csv",
    help = paste(
      "csv file with one row per site to be retrieved,",
      "and at least columns 'id', 'lat', 'lon', 'start_date', 'end_date'.",
      "Any other columns are ignored."
    )
  ),
  optparse::make_option("--raw_era5_path",
    default = "/projectnb/dietzelab/dongchen/anchorSites/ERA5",
    help = paste(
      "Path to your existing ERA5 data.",
      "These should be whole-year ensemble netcdfs as downloaded from ECWMF,",
      "with dimensions (latitude, longitude, number [aka ensemble member], time).",
      "Files must be named '<raw_era5_path>/ERA5_<year>.nc."
    )
  ),
  optparse::make_option("--site_era5_path",
    default = "/projectnb/dietzelab/chrisb/ERA5_nc",
    help = paste(
      "Path to save netcdf output in PEcAn met format.",
      "These are single site, single-year netcdfs placed in subdirectories per",
      "ensemble member. Files have dimensions (lat, lon, time), with only one",
      "lat and lon per file; note that ensemble number is tracked only in the",
      "filename and not in the netCDF metadata.",
      "Files are named",
      "'<site_era5_path>/ERA5_<siteid>_<ensid>/ERA5.<ensid>.<year>.nc'."
    )
  ),
  optparse::make_option("--site_sipnet_met_path",
    default = "/projectnb/dietzelab/chrisb/ERA5_SIPNET",
    help = paste(
      "Path to save output in Sipnet format.",
      "These are single-site, multi-year Sipnet clim files, one per ensemble",
      "member. Files are tab-delimited ASCII text with no header and are named",
      "'<site_sipnet_met_path>/<siteid>/ERA5.<ensid>.<start>.<end>.clim'."
    )
  ),
  optparse::make_option("--n_cores",
    default = 1,
    help = paste("Number of CPUs to use in parallel")
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

future::plan("multisession", workers = args$n_cores)

# options(
#   repos = c(
#     getOption("repos"), # to keep your existing CRAN mirror
#     PEcAn = "pecanproject.r-universe.dev", # for PEcAn packages
#     ropensci = "ropensci.r-universe.dev" # for deps `traits` and `taxize`
#   )
# )

# if (!requireNamespace("PEcAn.data.atmosphere", quietly = TRUE)) {
#   print("installing PEcAn.data.atmosphere")
#   install.packages("PEcAn.data.atmosphere")
# }

# if (!requireNamespace("PEcAn.SIPNET", quietly = TRUE)) {
#   print("Installing PEcAn.SIPNET")
#   install.packages("PEcAn.SIPNET")
# }

site_info <- read.csv(args$site_info_file)

furrr::future_pwalk(
  site_info,
  function(id, lat, lon, start_date, end_date, ...) {
    PEcAn.data.atmosphere::extract.nc.ERA5(
      slat = lat,
      slon = lon,
      in.path = args$raw_era5_path,
      start_date = start_date,
      end_date = end_date,
      outfolder = args$site_era5_path,
      in.prefix = "ERA5_",
      newsite = id
    )
  },
  .options = furrr::furrr_options(seed = TRUE)
)



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
      start_date = start_date,
      end_date = end_date,
      in.prefix = paste0("ERA5.", ens_id),
      outfolder = file.path(args$site_sipnet_met_path, site_id)
    )
  },
  .options = furrr::furrr_options(seed = TRUE)
)
