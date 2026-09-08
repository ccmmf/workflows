#!/usr/bin/env Rscript

# Get hourly weather data from Caladapt's WRF climate scenarios
# for all grid cells covering a set of parcels
#
# Caution: Expect long runtimes -- my statewide download took on the order of
# 10 min per model-year = ~4 hours per model when fetching 203 grid cells
# from 2024 to 2051.

# TODO Consider downloading models in parallel via furrr::future_walk,
# copying the approach in ERA5_met_extract.R.

options <- list(
  optparse::make_option("--parcel_geom_file",
    default = "data_raw/management/crops/v4.1.2/parcels-consolidated.gpkg",
    help = "file containing polygons defining the area of interest"
  ),
  optparse::make_option("--output_dir",
    default = "caladapt_wrf_weather/",
    help = paste(
      "Directory to write output.",
      "It will contain one subdir per grid cell downloaded,",
      "each with one netcdf per year per model.",
      "Will also contain a `parcel_to_grid` CSV mapping each parcel id to",
      "a CalAdapt grid cell."
    )
  ),
  optparse::make_option("--start_year",
    default = 2024,
    help = "First year of projections to retrieve"
  ),
  optparse::make_option("--end_year",
    default = 2024,
    help = "Last year of projections to retrieve"
  ),
  optparse::make_option("--models",
    default = paste0(
      "CESM2,CNRM-ESM2-1,EC-Earth3,EC-Earth3-Veg,",
      "FGOALS-g3,MIROC6,MPI-ESM1-2-HR,TaiESM1"
    ),
    help = paste(
      "Comma-separated list of GCMs to retrieve.",
      "See `caladaptaer::case_models(\"WRF\")` for valid names."
    )
  ),
  optparse::make_option("--scenario",
    default = "ssp370",
    help = paste(
      "Climate scenario. See `caladaptaer::cae_scenarios(\"WRF\")`",
      "for valid values."
    )
  ),
  optparse::make_option("--resolution",
    default = "d01",
    help = "Spatial resolution: 'd01' for 45km, 'd02' for 9km, 'd03' for 3km."
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()



# Needs caladaptaer, available via
# remotes::install_github("lebauerapproach/caladaptaer")
# install.packages("CFtime")

# library(caladaptaer) 
# library(tidyverse)

models <- strsplit(args$models, ",")[[1]] |>
  trimws()

centroids <- terra::vect(args$parcel_geom_file) |>
  _[,"parcel_id"] |>
  terra::centroids() |>
  terra::project("epsg:4326") |>
  as.data.frame(geom="XY") |>
  dplyr::rename(lon  = x, lat = y)

# Easiest current way to get a reference grid: fetch one timepoint with no
# location specified
# (future caladaptaer releases may add a more streamlined catalog lookup)
caladapt_ref <- caladaptaer::cae_fetch(
    variable = "t2",
    model = "CESM2",
    scenario = args$scenario,
    start_time = "2050-07-01T00:00:00",
    end_time = "2050-07-01T00:00:00",
    resolution = args$resolution,
    timescale = "1hr"
)

gridid <- caladaptaer::cae_grid_cells(centroids, caladapt_ref)
if (!dir.exists(args$output_dir)) {
  dir.create(args$output_dir, recursive = TRUE)
}
gridid |>
  mutate(
    across(
      contains(c("lon", "lat")),
      \(x) round(x, 5)
    )
  ) |>
  write.csv(
    file = file.path(
      args$output_dir,
      paste0("parcel_to_grid_", args$resolution, ".csv")
    ),
    row.names = FALSE
  )


cells_to_fetch <- gridid |> 
  dplyr::distinct(cell_id, cell_lon, cell_lat) |>
  dplyr::rename(lon = cell_lon, lat = cell_lat, site_id = cell_id)

get_one_model <- function(modelname) {
  caladaptaer::cae_build_met_drivers(
      sites = cells_to_fetch,
      model = modelname,
      scenario = args$scenario,
      start_year = args$start_year,
      end_year = args$end_year,
      outdir = args$output_dir,
      resolution = args$resolution
  )
}

models |>
  purrr::walk(get_one_model)
