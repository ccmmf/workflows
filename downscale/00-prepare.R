#' ---
#' title: "Workflow Setup and Data Preparation"
#' author: "David LeBauer"
#' ---
#' 
#' 
#' # Overview
#' 
#' - Prepare Inputs
#'   - Harmonized LandIQ dataset of woody California cropland from 2016-2023
#'   - SoilGrids soil properties (clay, ?)
#'   - CalAdapt climatology (mean annual temperature, mean annual precipitation)
#' - Use LandIQ to query covariates from SoilGrids and CalAdapt and create a table that includes crop type, soil properties, and climatology for each woody crop field
#' 
#' ## TODO
#' 
#' - Use consistent projection(s):
#'   - California Albers EPSG:33110 for joins and spatial operations
#'   - WGS84 EPSG:4326 for plotting, subsetting rasters?
#' - Clean up domain code
#' - Create a bunch of tables and join all at once at the end
#' - Disambiguate the use of 'ca' in object names; currently refers to both California and Cal-Adapt
#' - decide if we need both Ameriflux shortnames and full names in anchor_sites.csv
#'    (prob. yes, b/c both are helpful); if so, come up w/ better name than 'location'
#' - make sure anchor_sites_ids.csv fields are defined in README 
library(tidyverse)
library(sf)
library(terra)
library(caladaptr)

# moved to 000-config.R?
data_dir <- "/projectnb2/dietzelab/ccmmf/data"
raw_data_dir <- "/projectnb2/dietzelab/ccmmf/data_raw"
ca_albers_crs <- 3310

PEcAn.logger::logger.info("Starting Data Preparation Workflow")

#source(here::here("downscale", "000-config.R"), local = TRUE)
#' ### LandIQ Woody Polygons
#' 
#' The first step is to convert LandIQ to a open and standard (TBD) format.
#' 
#' We will use a GeoPackage file to store geospatial information and 
#' associated CSV files to store attributes associated with the LandIQ fields.
#' 
#' The `site_id` field is the unique identifier for each field.
#' 
#' The landiq2std function will be added to the PEcAn.data.land package, and has been implemented in a Pull Request https://github.com/PecanProject/pecan/pull/3423. The function is a work in progress. Two key work to be done. First `landiq2std` does not currently perform all steps to get from the original LandIQ format to the standard format - some steps related to harmonizing LandIQ across years have been completed manually. Second, the PEcAn 'standard' for such data is under development as we migrate from a Postgres database to a more portable GeoPackage + CSV format.
#' 
## Convert SHP to Geotiff`

input_file = file.path(raw_data_dir, 'i15_Crop_Mapping_2016_SHP/i15_Crop_Mapping_2016.shp')
ca_fields_gpkg <- file.path(data_dir, 'ca_fields.gpkg')
ca_attributes_csv = file.path(data_dir, 'ca_field_attributes.csv')
if(!file.exists(ca_fields_gpkg) & !file.exists(ca_attributes_csv)) {
  landiq2std(input_file, ca_fields_gpkg, ca_attributes_csv) # if landiq2std isnt available, see software section of README
  PEcAn.logger::logger.info(paste0("Created ca_fields.gpkg and ca_field_attributes.csv in ", data_dir))
} else {
   PEcAn.logger::logger.info("ca_fields.gpkg and ca_field_attributes.csv already exist in ", data_dir)
}

ca_fields <- sf::st_read(ca_fields_gpkg) |>
  sf::st_transform(crs = ca_albers_crs)
ca_attributes <- readr::read_csv(ca_attributes_csv)

#' ##### Subset Woody Perennial Crop Fields
#'
#' Phase 1 focuses on Woody Perennial Crop fields.
#'
#' Next, we will subset the LandIQ data to only include woody perennial crop fields.
#' At the same time we will calculate the total percent of California Croplands that are woody perennial crop.
#'
## -----------------------------------------------------------------------------

ca_woody_gpkg <- file.path(data_dir, 'ca_woody.gpkg')
if(!file.exists(ca_woody_gpkg)) {
  ca_fields |>
    left_join(
      ca_attributes |>
        filter(pft == "woody perennial crop") |>
        select(site_id, pft),
      by = c("site_id")
    ) |>
    sf::st_transform(crs = ca_albers_crs) |>
    dplyr::select(site_id, geom) |>
    sf::st_write(
      file.path(data_dir, 'ca_woody.gpkg'),
      delete_dsn = TRUE
    )
  PEcAn.logger::logger.info("Created ca_woody.gpkg with woody perennial crop fields in ", data_dir)
} else {
  PEcAn.logger::logger.info("ca_woody.gpkg already exists in ", data_dir)
}

#' ### Create California bounding box and polygon for clipping
#'  

#' ### Convert Polygons to Points.
#'
#' For Phase 1, we will use points to query raster data.
#' In later phases we will evaluate the performance of polygons and how querying environmental data using polygons will affect the performance of clustering and downscaling algorithms.
#'

ca_fields_pts <- ca_fields |>
  dplyr::select(-lat, -lon) |>
  left_join(ca_attributes, by = "site_id") |>
  sf::st_centroid() |>
  # and keep only the columns we need
  dplyr::select(site_id, crop, pft, geom)

#' 
#' ## Environmental Covariates
#' 
#' ### SoilGrids
#' 
#' #### Load Prepared Soilgrids GeoTIFF
#' 
#' Using already prepared SoilGrids layers. 
#' TODO: move a copy of these files to data_dir
#' 
## ----load-soilgrids-----------------------------------------------------------
soilgrids_north_america_clay_tif <- '/projectnb/dietzelab/dongchen/anchorSites/NA_runs/soil_nc/soilgrids_250m/clay/clay_0-5cm_mean/clay/clay_0-5cm_mean.tif'
soilgrids_north_america_ocd_tif <- '/projectnb/dietzelab/dongchen/anchorSites/NA_runs/soil_nc/soilgrids_250m/ocd/ocd_0-5cm_mean/ocd/ocd_0-5cm_mean.tif'
## if we want to clip to CA
## use terra to read in that file and then extract values for each location

soilgrids_north_america_clay_rast <- terra::rast(soilgrids_north_america_clay_tif)
soilgrids_north_america_ocd_rast <- terra::rast(soilgrids_north_america_ocd_tif)

#' 
#' #### Extract clay and carbon stock from SoilGrids
#' 
## ----sg-clay-ocd--------------------------------------------------------------

clay <- terra::extract(
  soilgrids_north_america_clay_rast,
  terra::vect(ca_fields_pts |>
    sf::st_transform(crs = sf::st_crs(soilgrids_north_america_clay_rast)))) |>
  dplyr::select(-ID) |>
  dplyr::pull() / 10

ocd <- terra::extract(
  soilgrids_north_america_ocd_rast,
  terra::vect(ca_fields_pts |>
    sf::st_transform(crs = sf::st_crs(soilgrids_north_america_ocd_rast)))) |>
  dplyr::select(-ID) |>
  dplyr::pull()

ca_fields_pts_clay_ocd <- cbind(ca_fields_pts,
                               clay = clay,
                               ocd = ocd)

#' 
#' ### Topographic Wetness Index
#' 
## ----twi----------------------------------------------------------------------
twi_tiff <- '/projectnb/dietzelab/dongchen/anchorSites/downscale/TWI/TWI_resample.tiff'
twi_rast <- terra::rast(twi_tiff) 

twi <- terra::extract(
  twi_rast,
  terra::vect(ca_fields_pts |>
    sf::st_transform(crs = sf::st_crs(twi_rast)))) |>
  dplyr::select(-ID) |>
  dplyr::pull()

ca_fields_pts_clay_ocd_twi <- cbind(ca_fields_pts_clay_ocd, twi = twi)

#' 
#' ### ERA5 Met Data
#' 
## -----------------------------------------------------------------------------
era5met_dir <- "/projectnb/dietzelab/dongchen/anchorSites/NA_runs/GridMET/"

# List all ERA5_met_*.tiff files for years 2012-2021
raster_files <- list.files(
  path = era5met_dir,
  pattern = "^ERA5_met_\\d{4}\\.tiff$",
  full.names = TRUE
)

# Read all rasters into a list of SpatRaster objects
rasters_list <- purrr::map(
  raster_files,
  ~ terra::rast(.x))

years <- purrr::map_chr(rasters_list, ~ {
  source_path <- terra::sources(.x)[1]
  stringr::str_extract(source_path, "\\d{4}")
})  |>
  as.integer()

names(rasters_list) <- years

extract_clim <- function(raster, points_sf) {
  terra::extract(
    raster, 
    points_sf |> 
      sf::st_transform(crs = sf::st_crs(raster))
    ) |>
    tibble::as_tibble() |>
    select(-ID) |>
    mutate(site_id = points_sf$site_id) |>
    select(site_id, temp, prec, srad, vapr)
}

.tmp <-  rasters_list |>
  furrr::future_map_dfr(
    ~ extract_clim(.x, ca_fields_pts),
      .id = "year"
      )

clim_summaries <- .tmp |>
  dplyr::mutate(
    precip = PEcAn.utils::ud_convert(prec, "second-1", "year-1")
) |>
  dplyr::group_by(site_id) |>
  dplyr::summarise(
    temp = mean(temp),
    precip = mean(precip),
    srad = mean(srad),
    vapr = mean(vapr)
  )

#' 
## ----join_and_subset----------------------------------------------------------
.all <- clim_summaries  |>
  dplyr::left_join(ca_fields_pts_clay_ocd_twi, by = "site_id")

assertthat::assert_that(
  nrow(.all) == nrow(clim_summaries) &&
    nrow(.all) == nrow(ca_fields_pts_clay_ocd_twi),
  msg = "join was not 1:1 as expected"
)

#' Append CA Climate Region
#'
## Add Climregions
# load climate regions for mapping
#' ### Cal-Adapt Climate Regions
#'
#' Climate Region will be used as a factor
#' in the hierarchical clustering step. 
## ----caladapt_climregions-----------------------------------------------------

ca_field_climregions <- ca_fields |>
  sf::st_join(
    caladaptr::ca_aoipreset_geom("climregions") |>
      sf::st_transform(crs = ca_albers_crs),
    join = sf::st_within
  ) |>
  dplyr::select(
    site_id,
    climregion_id = id,
    climregion_name = name
  )

# This returns a point geometry. 
# To return the **polygon** geometry from ca_fields, 
# drop geometry from .all instead of from ca_field_climregions
.all2 <- .all |>
  dplyr::left_join(
    ca_field_climregions  |> st_drop_geometry(),
    by = "site_id"
  )

site_covariates <- .all2 |>
  na.omit() |>
  mutate(across(where(is.numeric), ~ signif(., digits = 3))) 

PEcAn.logger::logger.info(
  round(100 * (1 - nrow(site_covariates) / nrow(ca_fields)), 0), "% of LandIQ polygons (sites) have at least one missing environmental covariate"
)

# takes a long time
# knitr::kable(skimr::skim(site_covariates))

readr::write_csv(site_covariates, file.path(data_dir, "site_covariates.csv"))

# Final output for targets; if not in targets, suppress return
if (exists("IN_TARGETS") && IN_TARGETS) {
  site_covariates
} else {
  invisible(site_covariates)
}

#'
#' ## Anchor Sites
#'
## ----anchor-sites-------------------------------------------------------------
# Anchor sites from UC Davis, UC Riverside, and Ameriflux.
anchor_sites <- readr::read_csv("data_raw/anchor_sites.csv")
anchor_sites_pts <- anchor_sites |>
  sf::st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
  sf::st_transform(crs = ca_albers_crs)

# Join with ca_fields: keep only the rows associated with anchor sites
# spatial join find ca_fields that contain anchor site points
#     takes ~ 1 min on BU cluster w/ "Intel(R) Xeon(R) CPU E5-2670 0 @ 2.60GHz"

# Note: in the next step, pfts are removed from the anchorsites dataframe 
# and kept pfts from site_covariates 
# the ones in the sites_covariates were generated by the landiq2std function
# TODO we will need to make sure that pfts are consistent b/w landiq and anchorsites
# by identifying and investigating discrepancies

# First subset ca_fields to only include those with covariates
#     (approx.  )

ca_fields_with_covariates <- ca_fields |>
  dplyr::right_join(site_covariates |> select(site_id), by = "site_id")

anchor_sites_with_ids <- anchor_sites_pts |>
  sf::st_join(ca_fields_with_covariates,
    join = sf::st_within
  )

# Handle unmatched anchor sites
unmatched_anchor_sites <- anchor_sites_with_ids |>
  dplyr::filter(is.na(site_id))
matched_anchor_sites <- anchor_sites_with_ids |>
  dplyr::filter(!is.na(site_id))

if (nrow(unmatched_anchor_sites) > 0) {
  # TODO Consider if it is more efficient and clear to match all anchor sites using 
  # st_nearest_feature rather than st_within
  nearest_indices <- sf::st_nearest_feature(unmatched_anchor_sites, ca_fields)

  # Get nearest ca_fields
  nearest_ca_fields <- ca_fields |> dplyr::slice(nearest_indices)

  # Assign site_id and calculate distances
  unmatched_anchor_sites <- unmatched_anchor_sites |>
    dplyr::mutate(
      site_id = nearest_ca_fields$site_id,
      lat = nearest_ca_fields$lat,
      lon = nearest_ca_fields$lon,
      distance_m = sf::st_distance(geometry, nearest_ca_fields, by_element = TRUE)
    )
  threshold <- units::set_units(250, "m")
  if (any(unmatched_anchor_sites$distance_m > threshold)) {
    PEcAn.logger::logger.warn(
      "The following anchor sites are more than 250 m away from the nearest landiq field:",
      paste(unmatched_anchor_sites |> filter(distance_m > threshold) |> pull(site_name), collapse = ", "),
      "Please check the distance_m column in the unmatched_anchor_sites data.",
      "Consider dropping these sites or expanding the threshold."
    )
  }

  # Combine matched and unmatched anchor sites
  anchor_sites_with_ids <- dplyr::bind_rows(
    matched_anchor_sites,
    unmatched_anchor_sites |> select(-distance_m)
  )
}

# Check for missing site_id, lat, or lon
if (any(is.na(anchor_sites_with_ids |> select(site_id, lat, lon)))) {
  PEcAn.logger::logger.warn(
    "Some anchor sites **still** have missing site_id, lat, or lon!"
  )
}

# Check for anchor sites with any covariate missing
n_missing <- anchor_sites_with_ids |>
  left_join(site_covariates, by = "site_id") |>
  dplyr::select(
    site_id, lat, lon,
    clay, ocd, twi, temp, precip
  ) |>
  filter(if_any(
    everything(),
    ~ is.na(.x)
  )) |> nrow()

if (n_missing > 0) {
  PEcAn.logger::logger.warn(
    "Some anchor sites have missing environmental covariates!"
  )
}


# Save processed anchor sites
anchor_sites_with_ids |>
  sf::st_drop_geometry() |>
  dplyr::select(site_id, lat, lon, external_site_id, site_name, crops, pft) |>
  # save lat, lon with 5 decimal places 
  dplyr::mutate(
    lat = round(lat, 5),
    lon = round(lon, 5)
  ) |>
  readr::write_csv(file.path(data_dir, "anchor_sites_ids.csv"))

