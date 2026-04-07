#!/usr/bin/env Rscript

# (re)building site info from an existing set of design points,
# retaining location but updating to use harmonized parcel IDs
# and PFT asignments for 2016 (previous version used 2018)

# This may need further adjustment to account for PFT timeseries once restarts
# are enabled.

## ---------------------- parse command-line options --------------------------
options <- list(
  optparse::make_option("--location_file",
    default = "../data/design_points.csv",
    help = paste(
      "CSV giving at least lat and lon for sites of interest.",
      "Any other columns will be passed unchanged to the output."
      )
  ),
  optparse::make_option("--out_file",
    default = "site_info.csv",
    help = "Path to write CSV with parcel ids and PFTs added"
  ),
  optparse::make_option("--parcel_file",
    default = "data_raw/management/crops/v4.1/parcels-consolidated.gpkg",
    help = "Geopackage to be used for spatial lookup of parcel IDs"
  ),
  optparse::make_option("--crop_file",
    default = "data_raw/management/crops/v4.1/crops_all_years.parq",
    help = "Parquet file containing harmonized DWR crop history"
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



#' Assign DWR/LandIQ California crop codes to Sipnet PFT names
#'
#' Built for the MAGiC project, may or may not be applicable elsewhere
#'
#' @param CLASS vector of crop class codes (1-2 capital letters each)
#' @param SUBCLASS vector of crop identifiers (1-2 numeric digits each)
#' @return PFT assignments as character, NA if unclassified
dwr_crop_to_pft <- function(CLASS, SUBCLASS) {
  dplyr::case_when(

    ## N fixers, treated as generic annual until N fixer PFT is created
    CLASS == "F" & SUBCLASS %in% c(10)     ~ "annual_crop", # dry beans
    CLASS == "P" & SUBCLASS %in% c(1, 2)   ~ "annual_crop", # alfalfa, clover
    CLASS == "T" & SUBCLASS %in% c(3, 11)  ~ "annual_crop", # Green beans, peas

    ## subclasses with physiology differing from the rest of their class
    # woody berries
    CLASS == "T" & SUBCLASS %in% c(19, 28) ~ "temperate.deciduous",
    # "Flowers, nursery & Christmas tree farms"
    # (A weird grouping, but assuming these are most likely to be tree-like)
    CLASS == "T" & SUBCLASS %in% c(16)     ~ "temperate.deciduous",
    
    ## Whole-class assignments
    CLASS %in% c("F", "G", "T")       ~ "annual_crop", # field crops, grains/hay, truck crops
    CLASS %in% c("P")                 ~ "grass", # perennial pasture grass; annual grasses in G
    CLASS %in% c("D", "C", "V", "YP") ~ "temperate.deciduous", # deciduous, citrus, vineyard, young perennial
    CLASS %in% c("R")                 ~ "grass", # Rice; TODO update when rice PFT is created
    CLASS %in% c("X", "I")            ~ "annual_crop", # fallow, not cropped, or unclassified
      # TODO maybe this should just get soil PFT or be skipped during site selection?
      # Logic for defaulting to annual crop here:
      # Temporarily idle/fallow likely to grow small amount annual weeds;
      # If no plant/harv events, annual will grow very little. 

    # Urban, industrial, native vegetation, semi-agricultural, vacant, etc
    TRUE ~ NA_character_
  )
}

#' Look up parcel IDs from harmonized DWR California crop map
#'
#' @param df dataframe with at least columns `lat` and `lon`
#'  Any other columns will be passed through unchanged
#'
#' @return dataframe with `parcel_id` column added
#'
#' @examples
#' point_to_dwr_parcelid(
#'   c(32.18, 32.22),
#'   c(-122.22, -123.18),
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

  df |>
  dplyr::mutate(parcel_id = parcel_geo$parcel_id[nearest_parcels$to_id])
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
    cropdat <- cropdat |> dplyr::filter(.data$year %in% years)
  }
  if (!is.null(seasons)) {
    cropdat <- cropdat |> dplyr::filter(.data$season %in% seasons)
  }

  dplyr::collect(cropdat)
}


design_pts <- read.csv(args$location_file)
pts_matched <- point_to_dwr_parcelid(design_pts)
crop_2016 <- dwr_parcelid_to_crop(pts_matched$parcel_id, years = 2016, seasons = 2) |>
  dplyr::select("parcel_id", "CLASS", "SUBCLASS")

site_info <- pts_matched |>
  left_join(crop_2016, by = "parcel_id") |>
  rename(id = parcel_id) |> # TODO propagate `parcel_id` convention further downstream?
  # OR rethink naming: id vs site_id vs something else?
  mutate(
    site.pft = dwr_crop_to_pft(CLASS, SUBCLASS),
    field_id = id
  ) |>
  
  # TODO
  # - retain field_id or drop now that it's equal to id in this case?
  # - 
  select(-CLASS, -SUBCLASS)

write.csv(site_info, args$out_file, row.names = FALSE)
