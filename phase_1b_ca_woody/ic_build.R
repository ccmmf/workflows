#!/usr/bin/env Rscript

## ---------------------------------------------------------
# Inputs: Update these for your site(s)

# Names and locations for sites of interest
site_info <- read.csv("site_info.csv")

# For now, start date must be same for all sites,
# and some download/extraction functions rely on this.
# TODO add support for diff start dates per site
# Workaround: Call this script separately for sites whose dates differ
site_info$start_date <- "2016-01-01"
site_info$LAI_date <- "2016-07-01"


data_dir <- "data/IC_prep"
ic_outdir <- "IC_files"

# Using Landtrandr biomass requires manual download of the relevant geotiffs
# from Kennedy group at Oregon State. Medians are available by anonymous FTP at
#   islay.ceoas.oregonstate.edu
# and by web (but possibly this is a different version?) from
#   https://emapr.ceoas.oregonstate.edu/pages/data/viz/index.html
# The uncertainty layer was formerly distributed by FTP but I cannot find it
# on the ceoas server at the moment.
# TODO find out whether this is available from a supported source.
#
# Here I am using a subset (just year 2016 clipped to the CA state boundaries)
# of the 30-m CONUS median and stdev maps that are stored on the Dietze lab
# server.
#
# Code below expects exactly one "*median.tif" and one "*stdv.tif".
landtrendr_raw_files <- file.path(
  "data_raw/",
  paste0("ca_biomassfiaald_2016_", c("median", "stdv"), ".tif")
)

ic_ensemble_size <- 100

# PFT-specific parameters used to convert LAI to leaf carbon estimates.
# Future versions will want to read these directly from an appropriate PFT file,
# but keeping as an input for MVP.
#
# These value are from the `temperate.deciduous` PFT,
# so should be representative for deciduous tree crops like almond
specific_leaf_area <- list(mean = 15.18, sd = 0.97) # units m2/kg
leaf_carbon_fraction <- list(mean = 0.466, sd = 0.00088) # units g/g
# OK, this one's not in the PFT -- just my estimate!
# TODO update from a citeable source
wood_carbon_fraction <- list(mean = 0.48, sd = 0.005)


## ---------------------------------------------------------
# Remainder of this script should work with no edits
# for any CA location(s) in site_info

set.seed(6824625)
library(tidyverse)

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
    site_info |> select(site_id = id, site_name = name, lat, lon),
    outdir = data_dir
  )
}



PEcAn.logger::logger.info("Soil moisture")
sm_outdir <- file.path(data_dir, "soil_moisture") |> normalizePath()
sm_csv_path <- file.path(data_dir, "sm.csv") # name is hardcorded by fn
if (file.exists(sm_csv_path)) {
  PEcAn.logger::logger.info("using existing soil moisture file", sm_csv_path)
  soil_moisture_est <- read.csv(sm_csv_path)
} else {
  if (!dir.exists(sm_outdir)) dir.create(sm_outdir)
  soil_moisture_est <- PEcAn.data.land::extract_SM_CDS(
    site_info = site_info |> dplyr::select(site_id = id, lat, lon),
    time.points = as.Date(site_info$start_date[[1]]),
    in.path = sm_outdir,
    out.path = dirname(sm_csv_path),
    allow.download = TRUE
  )
}

PEcAn.logger::logger.info("LAI")
# Note that this currently creates *two* CSVs:
# - "LAI.csv", with values from each available day inside the search window
#   (filename is hardcoded inside MODIS_LAI_PREP())
# - this path, aggregated to one row per site
# TODO consider cleaning this up -- eg reprocess from LAI.csv on the fly?
lai_csv_path <- file.path(data_dir, "LAI_bysite.csv")
if (file.exists(lai_csv_path)) {
  PEcAn.logger::logger.info("using existing LAI file", lai_csv_path)
  lai_est <- read.csv(lai_csv_path)
} else {
  lai_res <- PEcAn.data.remote::MODIS_LAI_prep(
    site_info = site_info |> dplyr::select(site_id = id, lat, lon),
    time_points = as.Date(site_info$LAI_date[[1]]),
    outdir = data_dir,
    export_csv = TRUE
  )
  lai_est <- lai_res$LAI_Output
  write.csv(lai_est, lai_csv_path, row.names = FALSE)
}


PEcAn.logger::logger.info("Aboveground biomass from LandTrendr")

landtrendr_agb_outdir <- data_dir

landtrendr_csv_path <- file.path(
  landtrendr_agb_outdir,
  "aboveground_biomass_landtrendr.csv"
)
if (file.exists(landtrendr_csv_path)) {
  PEcAn.logger::logger.info(
    "using existing LandTrendr AGB file",
    landtrendr_csv_path
  )
  agb_est <- read.csv(landtrendr_csv_path)
} else {
  lt_med_path <- grep("_median.tif$", landtrendr_raw_files, value = TRUE)
  lt_sd_path <- grep("_stdv.tif$", landtrendr_raw_files, value = TRUE)
  stopifnot(
    all(file.exists(landtrendr_raw_files)),
    length(lt_med_path) == 1,
    length(lt_sd_path) == 1
  )
  lt_med <- terra::rast(lt_med_path)
  lt_sd <- terra::rast(lt_sd_path)

  lt_points <- site_info |>
    terra::vect(crs = "epsg:4326") |>
    terra::project(lt_med) |>
    # TODO: is 200m radius a reasonable default?
    terra::buffer(width = 200)

  agb_est <- terra::extract(x = lt_med, y = lt_points, fun = mean, bind = TRUE) |>
    terra::extract(x = lt_sd, y = _, fun = mean, bind = TRUE) |>
    as.data.frame() |>
    dplyr::select(
      site_id = id,
      AGB_median_Mg_ha = ends_with("median"),
      AGB_sd = ends_with("stdv")
    )
  write.csv(agb_est, landtrendr_csv_path, row.names = FALSE)
}








# ---------------------------------------------------------
# Great, we have estimates for some variables.
# Now let's make IC files!

PEcAn.logger::logger.info("Building IC files")

initial_condition_estimated <- dplyr::bind_rows(
  soil_organic_carbon_content = soil_carbon_est |>
    dplyr::select(
      site_id = Site_ID,
      mean = `Total_soilC_0-30cm`,
      sd = `Std_soilC_0-30cm`
    ) |>
    dplyr::mutate(
      lower_bound = 0,
      upper_bound = Inf
    ),
  SoilMoistFrac = soil_moisture_est |>
    dplyr::select(
      site_id = site.id,
      mean = sm.mean,
      sd = sm.uncertainty
    ) |>
    # Note that we pass this as a percent -- yes, Sipnet wants a fraction,
    # but write.configs.SIPNET hardcodes a division by 100.
    # TODO consider modifying write.configs.SIPNET
    #   to not convert when 0 > SoilMoistFrac > 1
    dplyr::mutate(
      lower_bound = 0,
      upper_bound = 100
    ),
  LAI = lai_est |>
    dplyr::select(
      site_id = site_id,
      mean = ends_with("LAI"),
      sd = ends_with("SD")
    ) |>
    dplyr::mutate(
      lower_bound = 0,
      upper_bound = Inf
    ),
  AbvGrndWood = agb_est |> # NB this assumes AGB ~= AGB woody
    dplyr::select(
      site_id = site_id,
      mean = AGB_median_Mg_ha,
      sd = AGB_sd
    ) |>
    dplyr::mutate(across(
      c("mean", "sd"),
      ~ PEcAn.utils::ud_convert(
        .x * 0.48, # approximate biomass to C conversion
        "Mg ha-1",
        "kg m-2"
      )
    )) |>
    dplyr::mutate(
      lower_bound = 0,
      upper_bound = Inf
    ),
  # variables passed through from script inputs, not site-specific
  SLA = tibble::tibble(
    site_id = site_info$id,
    mean = specific_leaf_area$mean,
    sd = specific_leaf_area$sd,
    lower_bound = 0,
    upper_bound = Inf
  ),
  leaf_carbon_fraction = tibble::tibble(
    site_id = site_info$id,
    mean = leaf_carbon_fraction$mean,
    sd = leaf_carbon_fraction$sd,
    lower_bound = 0,
    upper_bound = 1
  ),
  wood_carbon_fraction = tibble::tibble(
    site_id = site_info$id,
    mean = wood_carbon_fraction$mean,
    sd = wood_carbon_fraction$sd,
    lower_bound = 0,
    upper_bound = 1
  ),
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
    sample = truncnorm::rtruncnorm(
      n = n,
      a = df$lower_bound,
      b = df$upper_bound,
      mean = df$mean,
      sd = df$sd
    )
  )
}

ic_samples <- initial_condition_estimated |>
  dplyr::group_by(site_id, variable) |>
  dplyr::group_modify(ic_sample_draws, n = ic_ensemble_size) |>
  tidyr::pivot_wider(names_from = variable, values_from = sample) |>
  dplyr::mutate(
    leaf_carbon_content = LAI / SLA * leaf_carbon_fraction,
    wood_carbon_content = AbvGrndWood - leaf_carbon_content
  )

ic_names <- colnames(ic_samples)
std_names <- c("site_id", "replicate", PEcAn.utils::standard_vars$Variable.Name)
nonstd_names <- ic_names[!ic_names %in% std_names]
if (length(nonstd_names) > 0) {
  PEcAn.logger::logger.debug(
    "Not writing these nonstandard variables to the IC files:", nonstd_names
  )
  ic_samples <- ic_samples |> dplyr::select(-any_of(nonstd_names))
}

file.path(ic_outdir, site_info$id) |>
  unique() |>
  purrr::walk(dir.create, recursive = TRUE)

ic_samples |>
  dplyr::group_by(site_id, replicate) |>
  dplyr::group_walk(
    ~ PEcAn.SIPNET::veg2model.SIPNET(
      outfolder = file.path(ic_outdir, .y$site_id),
      poolinfo = list(
        dims = list(time = 1),
        vals = .x
      ),
      siteid = .y$site_id,
      ens = .y$replicate
    )
  )

PEcAn.logger::logger.info("IC files written to", ic_outdir)
PEcAn.logger::logger.info("Done")
