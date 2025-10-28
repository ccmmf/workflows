#!/usr/bin/env Rscript

# Creates initial condition (IC) files for each location in site_info,
# using values from data_dir if they are already present,
# or looking them up and writing them to data_dir if they are not.

options <- list(
  optparse::make_option("--site_info_path",
    default = "site_info.csv",
    help = "CSV giving ids, locations, and PFTs for sites of interest"
  ),
  optparse::make_option("--field_shape_path",
    default = "data_raw/dwr_map/i15_Crop_Mapping_2018.gdb",
    help = "file containing site geometries, used for extraction from rasters"
  ),
  optparse::make_option("--ic_ensemble_size",
    default = 100,
    help = "number of files to generate for each site"
  ),
  optparse::make_option("--run_start_date",
    default = "2016-01-01",
    help = paste(
      "Date to begin simulations.",
      "For now, start date must be same for all sites,",
      "and some download/extraction functions rely on this.",
      "Workaround: Call this script separately for sites whose dates differ"
    )
  ),
  optparse::make_option("--run_LAI_date",
    default = "2016-07-01",
    help = "Date to look near (up to 30 days each direction) for initial LAI"
  ),
  optparse::make_option("--ic_outdir",
    default = "IC_files",
    help = "Directory to write completed initial conditions as nc files"
  ),
  optparse::make_option("--data_dir",
    default = "data/IC_prep",
    help = "Directory to store data retrieved/computed in the IC build process"
  ),
  optparse::make_option("--pft_dir",
    default = "pfts",
    help = paste(
      "path to parameter distributions used for PFT-specific conversions",
      "from LAI to estimated leaf carbon.",
      "Must be path to a dir whose child subdirectory names match the",
      "`site.pft` column of site_info and that contain a file",
      "`post.distns.Rdata`"
    )
  ),
  optparse::make_option("--params_read_from_pft",
    default = "SLA,leafC", # SLA units are m2/kg, leafC units are %
    help = "Parameters to read from the PFT file, comma separated"
  ),
  optparse::make_option("--landtrendr_raw_files",
    default = paste0(
      "data_raw/ca_biomassfiaald_2016_median.tif,",
      "data_raw/ca_biomassfiaald_2016_stdv.tif"
    ),
    help = paste(
      "Paths to two geotiffs, with a comma between them.",
      "These should contain means and standard deviations of aboveground",
      "biomass on the start date.",
      "We used Landtrendr-based values from the Kennedy group at Oregon State,",
      "which require manual download.",
      "Medians are available by anonymous FTP at islay.ceoas.oregonstate.edu",
      "and by web (but possibly this is a different version?) from",
      "https://emapr.ceoas.oregonstate.edu/pages/data/viz/index.html",
      "The uncertainty layer was formerly distributed by FTP but I cannot find",
      "it on the ceoas server at the moment.",
      "TODO find out whether this is available from a supported source.",
      "",
      "Demo used a subset (year 2016 clipped to the CA state boundaries)",
      "of the 30-m CONUS median and stdev maps that are stored on the Dietze",
      "lab server"
    )
  ),
  optparse::make_option("--additional_params",
    # Wood C fraction isn't in these PFTs, so just using my estimate.
    # TODO update from a citeable source,
    # and consider adding to PFT when calibrating
    default =
      "varname=wood_carbon_fraction,distn=norm,parama=0.48,paramb=0.005",
    help = paste(
      "Further params not available from site or PFT data,",
      "as a comma-separated named list with names `varname`, `distn`,",
      "`parama`, and `paramb`. Currently used only for `wood_carbon_fraction`"
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

if (!dir.exists(args$data_dir)) dir.create(args$data_dir, recursive = TRUE)

# split up comma-separated options
params_read_from_pft <- strsplit(args$params_read_from_pft, ",")[[1]]
landtrendr_raw_files <- strsplit(args$landtrendr_raw_files, ",")[[1]]
additional_params <- args$additional_params |>
  str_match_all("([^=]+)=([^,]+),?") |>
  _[[1]] |>
  (\(x) setNames(as.list(x[, 3]), x[, 2]))() |>
  as.data.frame() |>
  mutate(across(starts_with("param"), as.numeric))

site_info <- read.csv(
  args$site_info_path,
  colClasses = c(field_id = "character")
)
site_info$start_date <- args$run_start_date
site_info$LAI_date <- args$run_LAI_date


PEcAn.logger::logger.info("Getting estimated soil carbon from SoilGrids 250m")
# NB this takes several minutes to run
# csv filename is hardcoded by fn
soilc_csv_path <- file.path(args$data_dir, "soilgrids_soilC_data.csv")
if (file.exists(soilc_csv_path)) {
  PEcAn.logger::logger.info("using existing soil C file", soilc_csv_path)
  soil_carbon_est <- read.csv(soilc_csv_path, check.names = FALSE)
  sites_needing_soilc <- site_info |>
    filter(!id %in% soil_carbon_est$Site_ID)
} else {
  soil_carbon_est <- NULL
  sites_needing_soilc <- site_info
}
nsoilc <- nrow(sites_needing_soilc)
if (nsoilc > 0) {
  PEcAn.logger::logger.info("Retrieving soil C for", nsoilc, "sites")
  new_soil_carbon <- PEcAn.data.land::soilgrids_soilC_extract(
    sites_needing_soilc |> select(site_id = id, site_name = name, lat, lon),
    outdir = args$data_dir
  )
  soil_carbon_est <- bind_rows(soil_carbon_est, new_soil_carbon) |>
    arrange(Site_ID)
  write.csv(soil_carbon_est, soilc_csv_path, row.names = FALSE)
}



PEcAn.logger::logger.info("Soil moisture")
sm_outdir <- file.path(args$data_dir, "soil_moisture") |>
  normalizePath(mustWork = FALSE)
sm_csv_path <- file.path(args$data_dir, "sm.csv") # name is hardcorded by fn
if (file.exists(sm_csv_path)) {
  PEcAn.logger::logger.info("using existing soil moisture file", sm_csv_path)
  soil_moisture_est <- read.csv(sm_csv_path)
  sites_needing_soilmoist <- site_info |>
    filter(!id %in% soil_moisture_est$site.id)
} else {
  soil_moisture_est <- NULL
  sites_needing_soilmoist <- site_info
}
nmoist <- nrow(sites_needing_soilmoist)
if (nmoist > 0) {
  PEcAn.logger::logger.info("Retrieving soil moisture for", nmoist, "sites")
  if (!dir.exists(sm_outdir)) dir.create(sm_outdir)
  new_soil_moisture <- PEcAn.data.land::extract_SM_CDS(
    site_info = sites_needing_soilmoist |>
      dplyr::select(site_id = id, lat, lon),
    time.points = as.Date(site_info$start_date[[1]]),
    in.path = sm_outdir,
    out.path = dirname(sm_csv_path),
    allow.download = TRUE
  )
  soil_moisture_est <- bind_rows(soil_moisture_est, new_soil_moisture) |>
    arrange(site.id)
  write.csv(soil_moisture_est, sm_csv_path, row.names = FALSE)
}

PEcAn.logger::logger.info("LAI")
# Note that this currently creates *two* CSVs:
# - "LAI.csv", with values from each available day inside the search window
#   (filename is hardcoded inside MODIS_LAI_PREP())
# - this path, aggregated to one row per site
# TODO consider cleaning this up -- eg reprocess from LAI.csv on the fly?
lai_csv_path <- file.path(args$data_dir, "LAI_bysite.csv")
if (file.exists(lai_csv_path)) {
  PEcAn.logger::logger.info("using existing LAI file", lai_csv_path)
  lai_est <- read.csv(lai_csv_path, check.names = FALSE) # TODO edit MODIS_LAI_prep to use valid colnames?
  sites_needing_lai <- site_info |>
    filter(!id %in% lai_est$site_id)
} else {
  lai_est <- NULL
  sites_needing_lai <- site_info
}
nlai <- nrow(sites_needing_lai)
if (nlai > 0) {
  PEcAn.logger::logger.info("Retrieving LAI for", nlai, "sites")
  lai_res <- PEcAn.data.remote::MODIS_LAI_prep(
    site_info = sites_needing_lai |> dplyr::select(site_id = id, lat, lon),
    time_points = as.Date(site_info$LAI_date[[1]]),
    outdir = args$data_dir,
    export_csv = TRUE,
    skip_download = FALSE
  )
  lai_est <- bind_rows(lai_est, lai_res$LAI_Output) |>
    arrange(site_id)
  write.csv(lai_est, lai_csv_path, row.names = FALSE)
}


PEcAn.logger::logger.info("Aboveground biomass from LandTrendr")

landtrendr_agb_outdir <- args$data_dir

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
  sites_needing_agb <- site_info |>
    filter(!id %in% agb_est$site_id)
} else {
  agb_est <- NULL
  sites_needing_agb <- site_info
}
nagb <- nrow(sites_needing_agb)
if (nagb > 0) {
  PEcAn.logger::logger.info("Retrieving aboveground biomass for", nagb, "sites")
  lt_med_path <- grep("_median.tif$", landtrendr_raw_files, value = TRUE)
  lt_sd_path <- grep("_stdv.tif$", landtrendr_raw_files, value = TRUE)
  stopifnot(
    all(file.exists(landtrendr_raw_files)),
    length(lt_med_path) == 1,
    length(lt_sd_path) == 1
  )
  lt_med <- terra::rast(lt_med_path)
  lt_sd <- terra::rast(lt_sd_path)
  field_shp <- terra::vect(args$field_shape_path)

  site_bnds <- field_shp[field_shp$UniqueID %in% sites_needing_agb$field_id, ] |>
    terra::project(lt_med)

  # Check for unmatched sites
  # TODO is stopping here too strict? Could reduce to warning if needed
  stopifnot(all(sites_needing_agb$field_id %in% site_bnds$UniqueID))

  new_agb <- lt_med |>
    terra::extract(x = _, y = site_bnds, fun = mean, bind = TRUE) |>
    terra::extract(x = lt_sd, y = _, fun = mean, bind = TRUE) |>
    as.data.frame() |>
    left_join(sites_needing_agb, by = c("UniqueID" = "field_id")) |>
    dplyr::select(
      site_id = id,
      AGB_median_Mg_ha = ends_with("median"),
      AGB_sd = ends_with("stdv")
    ) |>
    mutate(across(where(is.numeric), \(x) signif(x, 5)))
  agb_est <- bind_rows(agb_est, new_agb) |>
    arrange(site_id)
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
  AbvGrndBiomass = agb_est |> # NB this assumes AGB ~= AGB woody
    dplyr::select(
      site_id = site_id,
      mean = AGB_median_Mg_ha,
      sd = AGB_sd
    ) |>
    dplyr::mutate(across(
      c("mean", "sd"),
      ~ PEcAn.utils::ud_convert(.x, "Mg ha-1", "kg m-2")
    )) |>
    dplyr::mutate(
      lower_bound = 0,
      upper_bound = Inf
    ),
  .id = "variable"
)
write.csv(
  initial_condition_estimated,
  file.path(args$data_dir, "IC_means.csv"),
  row.names = FALSE
)



# read params from PFTs

sample_distn <- function(varname, distn, parama, paramb, ..., n) {
  if (distn == "exp") {
    samp <- rexp(n, parama)
  } else {
    rfn <- get(paste0("r", distn))
    samp <- rfn(n, parama, paramb)
  }

  data.frame(samp) |>
    setNames(varname)
}

sample_pft <- function(path,
                       vars = params_read_from_pft,
                       n_samples = args$ic_ensemble_size) {
  e <- new.env()
  load(file.path(path, "post.distns.Rdata"), envir = e)
  e$post.distns |>
    tibble::rownames_to_column("varname") |>
    dplyr::select(-"n") |> # this is num obs used in posterior; conflicts with n = ens size when sampling
    dplyr::filter(varname %in% vars) |>
    dplyr::bind_rows(additional_params) |>
    purrr::pmap(sample_distn, n = n_samples) |>
    purrr::list_cbind() |>
    tibble::rowid_to_column("replicate")
}

pft_var_samples <- site_info |>
  mutate(pft_path = file.path(args$pft_dir, site.pft)) |>
  nest_by(id) |>
  mutate(samp = purrr::map(data$pft_path, sample_pft)) |>
  unnest(samp) |>
  dplyr::select(-"data") |>
  dplyr::rename(site_id = id)




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
  dplyr::filter(site_id %in% site_info$id) |>
  dplyr::group_by(site_id, variable) |>
  dplyr::group_modify(ic_sample_draws, n = args$ic_ensemble_size) |>
  tidyr::pivot_wider(names_from = variable, values_from = sample) |>
  dplyr::left_join(pft_var_samples, by = c("site_id", "replicate")) |>
  dplyr::mutate(
    AbvGrndWood = AbvGrndBiomass * wood_carbon_fraction,
    leaf_carbon_content = tidyr::replace_na(LAI, 0) / SLA * (leafC / 100),
    wood_carbon_content = pmax(AbvGrndWood - leaf_carbon_content, 0)
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

file.path(args$ic_outdir, site_info$id) |>
  unique() |>
  purrr::walk(dir.create, recursive = TRUE)

ic_samples |>
  dplyr::group_by(site_id, replicate) |>
  dplyr::group_walk(
    ~ PEcAn.SIPNET::veg2model.SIPNET(
      outfolder = file.path(args$ic_outdir, .y$site_id),
      poolinfo = list(
        dims = list(time = 1),
        vals = .x
      ),
      siteid = .y$site_id,
      ens = .y$replicate
    )
  )

PEcAn.logger::logger.info("IC files written to", args$ic_outdir)
PEcAn.logger::logger.info("Done")
