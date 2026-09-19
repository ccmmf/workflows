#!/usr/bin/env Rscript

# (re)building site info from an existing set of design points,
# retaining location but updating to use harmonized parcel IDs
# and PFT asignments for 2016 (previous version used 2018)

# This may need further adjustment to account for PFT timeseries once restarts
# are enabled.

## ---------------------- parse command-line options --------------------------
options <- list(
  optparse::make_option("--location_file",
    default = "data/design_points.csv",
    help = paste(
      "CSV giving at least lat and lon for sites of interest.",
      "Any other columns will be passed unchanged to the output."
      )
  ),
  optparse::make_option("--out_file",
    default = "site_info.csv",
    help = "Path to write CSV with parcel ids and PFTs added"
  ),
  optparse::make_option("--pft_lookup",
    default = "data_raw/pfts/crop2pft.csv",
    help = paste(
      "CSV mapping DWR crop codes to pft names.",
      "Must have columns 'CLASS', 'SUBCLASS', and 'pft'."
    )
  ),
  optparse::make_option("--parcel_file",
    default = "data_raw/management/crops/v4.1/parcels-consolidated.gpkg",
    help = "Geopackage to be used for spatial lookup of parcel IDs"
  ),
  optparse::make_option("--crop_file",
    default = "data_raw/management/crops/v4.1/crops_all_years.parq",
    help = "Parquet file containing harmonized DWR crop history"
  ),
  optparse::make_option("--WRF_grid_lookup",
    default = "data_raw/met/parcel_to_grid_d01.csv",
    help = paste(
      "CSV with at least columns `parcel_id` and `cell_id`,",
      "mapping harmonized DWR parcel IDs to WRF grid cells."
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


library(tidyverse)

#' Look up parcel IDs from harmonized DWR California crop map
#'
#' @param df dataframe with at least columns `lat` and `lon`
#'  Any other columns will be passed through unchanged
#'
#' @return dataframe with `parcel_id` column added
#'
#' @examples
#' point_to_dwr_parcelid(
#'   data.frame(lat = c(32.18, 32.22), lon = c(-122.22, -123.18)),
#'   "data_raw/management/crops/v4.1/parcels-consolidated.gpkg"
#' )
#'
point_to_dwr_parcelid <- function(df, geo_file = args$parcel_file) {
  stopifnot(is.numeric(df$lat), is.numeric(df$lon))
  parcel_geo <- terra::vect(geo_file)
  nearest_parcels <- df |>
    terra::vect(crs="epsg:4326") |>
    terra::project(parcel_geo) |>
    terra::nearest(parcel_geo)

  # Some extra steps to avoid silently clobbering existing parcel_ids
  orig_parcel_id <- NULL
  if (!is.null(df$parcel_id)) {
    orig_parcel_id <- df$parcel_id
  }

  df <- df |>
    dplyr::mutate(parcel_id = parcel_geo$parcel_id[nearest_parcels$to_id])

  if (!is.null(orig_parcel_id) && !all(df$parcel_id == orig_parcel_id)) {
    warning(
      "Found an input column named `parcel_id`, but it is not identical to",
      " the ids computed from parcel location.",
      " Please compare result columns `parcel_id.0` and `parcel_id`",
      " and correct as needed.")
    df$parcel_id.0 <- orig_parcel_id
  }

  df
}

#' @param ids vector of parcel ids
#' @param years,seasons numeric vectors to subset by.
#'  If not specified, returns all years and seasons.
#' @param crop_file path to a Parquet file containing harmonized DWR crop history
#' @return dataframe of crop info
dwr_parcelid_to_crop <- function(
    ids, 
    years = NULL,
    seasons = NULL,
    crop_file = args$crop_file) {
  cropdat <- arrow::open_dataset(args$crop_file) |>
    dplyr::filter(.data$parcel_id %in% ids) |>
    select(parcel_id, year, season, CLASS, SUBCLASS)
  if (!is.null(years)) {
    cropdat <- cropdat |>
      dplyr::filter(.data$year %in% years)
  }
  if (!is.null(seasons)) {
    cropdat <- cropdat |>
      dplyr::filter(.data$season %in% seasons)
  }

  dplyr::collect(cropdat)
}


design_pts <- read.csv(args$location_file)
pts_matched <- point_to_dwr_parcelid(design_pts)
pft_lookup <- read.csv(args$pft_lookup) |>
  select(CLASS, SUBCLASS, site.pft = pft)

crop_2016 <- dwr_parcelid_to_crop(
    pts_matched$parcel_id,
    years = 2016,
    seasons = 2
  ) |>
  left_join(
    pft_lookup,
    by = c("CLASS", "SUBCLASS"),
    relationship = "many-to-one"
  ) |>
  dplyr::select("parcel_id", "site.pft")
wrf_cells <- read.csv(args$WRF_grid_lookup) |>
  select(parcel_id, WRF_grid_cell = cell_id)

if (!is.null(design_pts$id) && anyDuplicated(design_pts$id)) {
  PEcAn.logger::logger.severe("column `id` of design points is not unique")
}

if (typeof(crop_2016$parcel_id) != typeof(pts_matched$parcel_id)) {
  crop_2016$parcel_id <- as.character(crop_2016$parcel_id)
  pts_matched$parcel_id = as.character(pts_matched$parcel_id)
}

site_info <- pts_matched |>
  left_join(crop_2016, by = "parcel_id") |>
  left_join(wrf_cells, by = "parcel_id") |>
  dplyr::mutate(
    # match locations to half-degree ERA5 grid cell centers
    # CAUTION: Calculation only correct when all lats are N and all lons are W!
    ERA5_grid_cell = paste0(
      ((lat + 0.25) %/% 0.5) * 0.5, "N_",
      ((abs(lon) + 0.25) %/% 0.5) * 0.5, "W"
    )
  )

if (is.null(site_info$id)) {
  site_info$id <- site_info$parcel_id
}

write.csv(site_info, args$out_file, row.names = FALSE)
