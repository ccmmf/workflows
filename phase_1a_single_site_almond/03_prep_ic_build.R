#!/usr/bin/env Rscript

## ---------------------------------------------------------
# Inputs: Update these for your site(s)

# Names and locations for sites of interest
site_info <- tibble::tribble(
  ~site_id, ~site_name, ~lat, ~lon, ~landsat_ARD_tile,
  "losthills", "losthills", 35.5103, -119.6675, "h03v11",
  "wolfskill", "wolfskill", 38.5032, -121.9808, "h02v08"
)

# For now, start date must be same for all sites,
# and some download/extraction functions rely on this.
# TODO add support for diff start dates per site
# Workaround: Call this script separately for sites whose dates differ
site_info$start_date <- "1999-01-01"


data_dir <- "data/IC_prep"
ic_outdir <- "IC_files"

# The LandTrendr data used here are distributed through an interactive portal,
# with no obvious ability to automate download.
# Manually download the geotiffs that contain your sites
# [e.g. paste0(conus_biomass_ARD_tile_", site_info$landsat_ARD_tile, ".tif)]
# from https://emapr.ceoas.oregonstate.edu/pages/data/viz/index.html
# and specify the path to them here
landtrendr_raw_data_dir <- "data_raw/LandTrendr_AGB"

ic_ensemble_size <- 100




## ---------------------------------------------------------
# Remainder of this script should work with no edits
# for any CA location(s) in site_info

set.seed(6824625)

# Do parallel processing in separate R processes instead of via forking
# (without this the {furrr} calls inside soilgrids_soilC_extract
# 	were crashing for me. TODO check if this is machine-specific)
op <- options(parallelly.fork.enable = FALSE)
on.exit(options(op))

if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)

PEcAn.logger::logger.info("Getting estimated soil carbon from SoilGrids 250m")
# NB this takes several minutes to run
# csv filename is hardcoded by fn
soilc_csv_path <- file.path(data_dir, "soilgrids_soilC_data.csv")
if (file.exists(soilc_csv_path)) {
  PEcAn.logger::logger.info("using existing soil C file", soilc_csv_path)
  soil_carbon_est <- read.csv(soilc_csv_path, check.names = FALSE)
} else {
  soil_carbon_est <- PEcAn.data.land::soilgrids_soilC_extract(
    site_info,
    outdir = data_dir
  )
}



PEcAn.logger::logger.info("Soil moisture")
sm_outdir <- file.path(data_dir, "soil_moisture") |> normalizePath()
sm_csv_path <- file.path(sm_outdir, "sm.csv") # name is hardcorded by fn
if (file.exists(sm_csv_path)) {
  PEcAn.logger::logger.info("using existing soil moisture file", sm_csv_path)
  soil_moisture_est <- read.csv(sm_csv_path)
} else {
  if (!dir.exists(sm_outdir)) dir.create(sm_outdir)
  soil_moisture_est <- PEcAn.data.land::extract_SM_CDS(
    site_info = site_info,
    time.points = as.Date(site_info$start_date[[1]]),
    in.path = sm_outdir,
    out.path = sm_outdir, # file name is hardcoded to "sm.csv"
    allow.download = TRUE
  )
}

# PEcAn.logger::logger.info("LAI")
# Skipping this for now -- the MODIS source data don't start until March 2000,
# plus this is a deciduous system and will start the year at zero.
# lai_est <- PEcAn.data.remote::MODIS_LAI_prep(
# 	site_info,
# 	as.Date(site_info$start_date[[1]]),
# 	outdir = data_dir)



PEcAn.logger::logger.info("Aboveground biomass from LandTrendr")
#
# The approach used here takes a simple SD of the spatial variability of the
# LandTrendr pixel estimates, ignoring covariance and model uncertainty
# TODO: Get/create uncertainty layer (may need to run landtrendr for ourselves?
#   then revisit this using existing functions in PEcAn.data.remote
#
# Requires manual download of the relevant geotiffs from
#   https://emapr.ceoas.oregonstate.edu/pages/data/viz/index.html
#   before running this script
landtrendr_agb_outdir <- data_dir
landtrendr_data_paths <- file.path(
  landtrendr_raw_data_dir,
  paste0("conus_biomass_ARD_tile_", site_info$landsat_ARD_tile, ".tif")
)
stopifnot(all(file.exists(landtrendr_data_paths)))

naive_landtrendr_AGB <- function(site_info, geotiff_paths, buffer = 400) {
  ## get coordinates and provide spatial info
  site_coords <- data.frame(site_info$lon, site_info$lat)
  names(site_coords) <- c("Longitude", "Latitude")
  coords_latlong <- sp::SpatialPoints(site_coords)
  sp::proj4string(coords_latlong) <- sp::CRS("+init=epsg:4326")

  # load gridded AGB data
  # Bands 1-28 are years 1990-2017
  yr <- lubridate::year(as.Date(site_info$start_date))
  stopifnot(all(yr >= 1990 & yr <= 2017)) # landtrendr data range
  raster_data <- mapply(FUN = raster::raster,
                        x = geotiff_paths,
                        band = yr - 1989) |>
    Reduce(f = raster::merge)

  ## reproject Lat/Long site coords to AGB Albers Equal-Area
  coords_AEA <- sp::spTransform(coords_latlong,
                                raster::crs(raster_data))
  ## extract
  agb_pixel <- raster::extract(
    x = raster_data,
    y = coords_AEA,
    buffer = buffer,
    df = FALSE
  ) |> setNames(site_info$site_id)

  agb_pixel |>
    purrr::map_dfr(getpx_naive, .id = "site_id")
}

# Here's the naive part!
# This version of the landtrendr data doesn't come with an uncertainty layer.
# For a horrifying approximation, we take the SD of all pixels in the buffer.
# This ignores correlation, conflates spatial heterogeneity with model
# uncertainty, and is generally a bad idea.
# TODO: Replace this.
getpx_naive <- function(pixel) {
  px <- pixel[pixel >= 0] # missing data are -9999
  data.frame(AGB_Mg_ha = mean(px), SD_AGB = sd(px))
}

landtrendr_csv_path <- file.path(landtrendr_agb_outdir,
                                 "aboveground_biomass_landtrendr.csv")
if (file.exists(landtrendr_csv_path)) {
  PEcAn.logger::logger.info("using existing LandTrendr AGB file",
                            landtrendr_csv_path)
  agb_est <- read.csv(landtrendr_csv_path)
} else {
  agb_est <- naive_landtrendr_AGB(
    site_info,
    geotiff_paths = landtrendr_data_paths
  )
  write.csv(agb_est, landtrendr_csv_path, row.names = FALSE)
}








# ---------------------------------------------------------
# Great, we have estimates for some variables.
# Now let's make IC files!

PEcAn.logger::logger.info("Building IC files")

initial_condition_estimated <- dplyr::bind_rows(
  soil_organic_carbon_content = soil_carbon_est |>
    dplyr::select(site_id = Site_ID,
                  mean = `Total_soilC_0-30cm`,
                  sd = `Std_soilC_0-30cm`) |>
    dplyr::mutate(lower_bound = 0,
                  upper_bound = Inf),
  SoilMoistFrac = soil_moisture_est |>
    dplyr::select(site_id = site.id,
                  mean = sm.mean,
                  sd = sm.uncertainty) |>
    # Note that we pass this as a percent -- yes, Sipnet wants a fraction,
    # but write.configs.SIPNET hardcodes a division by 100.
    # TODO consider modifying write.configs.SIPNET
    #   to not convert when 0 > SoilMoistFrac > 1
    dplyr::mutate(lower_bound = 0,
                  upper_bound = 100),
  AbvGrndWood = agb_est |> # NB this assumes AGB ~= AGB woody
    dplyr::select(site_id = site_id,
                  mean = AGB_Mg_ha,
                  sd = SD_AGB) |>
    dplyr::mutate(across(
      c("mean", "sd"),
      ~PEcAn.utils::ud_convert(.x * 0.48, # approximate biomass to C conversion
                               "Mg ha-1",
                               "kg m-2")
    )) |>
    dplyr::mutate(lower_bound = 0,
                  upper_bound = Inf),
  .id = "variable"
)
write.csv(
  initial_condition_estimated,
  file.path(data_dir, "IC_means.csv"),
  row.names = FALSE
)




ic_sample_draws <- function(df, n = 100, ...) {
  stopifnot(nrow(df) == 1)

  data.frame(
    replicate = seq_len(n),
    sample = truncnorm::rtruncnorm(n = n,
                                   a = df$lower_bound,
                                   b = df$upper_bound,
                                   mean = df$mean,
                                   sd = df$sd)
  )
}

ic_samples <- initial_condition_estimated |>
  dplyr::group_by(site_id, variable) |>
  dplyr::group_modify(ic_sample_draws, n = ic_ensemble_size) |>
  tidyr::pivot_wider(names_from = variable, values_from = sample) |>
  # Hack: Passing AGB to both AbvGrndWood and wood_carbon_content.
  # in Dongchen's IC files AbvGrndWood appears to be sum of
  # wood_carbon_content and leaf_carbon_content;
  # I'm assuming here leaf_carbon_content should be zero when LAI = 0;
  dplyr::mutate(wood_carbon_content = AbvGrndWood)

file.path(ic_outdir, site_info$site_id) |>
  unique() |>
  purrr::walk(dir.create, recursive = TRUE)

ic_samples |>
  dplyr::group_by(site_id, replicate) |>
  dplyr::group_walk(
    ~PEcAn.SIPNET::veg2model.SIPNET(
       outfolder = file.path(ic_outdir, .y$site_id),
       poolinfo = list(dims = list(time = 1),
                       vals = .x),
       siteid = .y$site_id,
       ens = .y$replicate
    )
  )

PEcAn.logger::logger.info("IC files written to", ic_outdir)
PEcAn.logger::logger.info("Done")
