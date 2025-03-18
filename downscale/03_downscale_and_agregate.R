#' ---
#' Title: Downscale and Agregate Woody Crop SOC stocks
#' author: "David LeBauer"
#' ---
#'

#'
#' # Overview
#'
#' This workflow will:
#'
#' - Use environmental covariates to predict SIPNET estimated SOC for each woody crop field in the LandIQ dataset
#'   - Uses Random Forest [maybe change to CNN later] trained on site-scale model runs.
#'   - Build a model for each ensemble member
#' - Write out a table with predicted biomass and SOC to maintain ensemble structure, ensuring correct error propagation and spatial covariance.
#' - Aggregate County-level biomass and SOC inventories
#'
## ----setup--------------------------------------------------------------------
# remotes::install_github("dlebauer/pecan@ensemble_downscaling", subdir = "modules/assim.sequential", ref = "da96331")
library(tidyverse)
library(sf)
library(terra)
devtools::load_all(here::here("../pecan/modules/assim.sequential/"))
# library(PEcAnAssimSequential)
basedir <- "/projectnb/dietzelab/ccmmf/ccmmf_phase_1b_98sites_20reps_20250312"
outdir <- file.path(basedir, "out")
options(readr.show_col_types = FALSE)

library(furrr)
no_cores <- parallel::detectCores(logical = FALSE)
plan(multicore, workers = no_cores - 1)

#' ## Get Site Level Outputs
ensemble_file <- file.path(outdir, "efi_ens_long.csv.gz")
ensemble_data <- readr::read_csv(ensemble_file) 

#' ### Random Forest using PEcAn downscale workflow
## -----------------------------------------------------------------------------
design_points <- read_csv(here::here("data/design_points.csv")) |>
  dplyr::distinct()

covariates <- readRDS(here::here("data/data_for_clust_with_ids.rds")) |>
  rename(site = id) |>
  select(
    site, where(is.numeric),
    -ends_with("id") # drop crop_id, climregion_id columns
  )

d <- function(date, carbon_pool) {
  filtered_ens_data <- subset_ensemble(
    ensemble_data = ensemble_data,
    site_coords   = design_points,
    date          = date,
    carbon_pool   = carbon_pool
  )

  # Downscale the data
  downscale_output <- downscale(
    ensemble_data = filtered_ens_data,
    site_coords   = design_points,
    covariates    = covariates,
    model_type    = "rf",
    seed          = 123
  )
  return(downscale_output)
}

cpools <- c("TotSoilCarb", "AGB")
library(furrr)
plan(multisession)

downscale_output <- purrr::map( # not using furrr b/c it is used inside downscale
  cpools,
  ~ d(date = "2018-12-31", carbon_pool = .x)
) |>
  purrr::set_names(cpools)


## Save to make it easier to restart
save(downscale_output, file = here::here("cache/downscale_output.rda"))


metrics <- downscale_metrics(downscale_output)
# could compute stats here e.g. mean, CI for ea. metric
print(metrics)

#'
#'
#' ## Aggregate to County Level
#'
## -----------------------------------------------------------------------------
library(sf)
library(dplyr)


# ca_fields <- readr::read_csv(here::here("data/ca_field_attributes.csv")) |>
#   dplyr::select(id, lat, lon) |>
#   rename(site = id)

ca_fields_full <- sf::read_sf(here::here("data/ca_fields.gpkg"))

ca_fields <- ca_fields_full |>
  select(site = id, county, area_ha)  

# Convert list to table with predictions and site identifier
get_downscale_preds <- function(downscale_output) {
  purrr::map(
    downscale_output$predictions,
    ~ tibble(site = covariates$site, prediction = .x)
  ) |>
    bind_rows(.id = "ensemble") |>
    left_join(ca_fields, by = "site") 
}

downscale_preds <- purrr::map(downscale_output, get_downscale_preds) |>
  dplyr::bind_rows(.id = "carbon_pool") |>
  # Convert kg / ha to tonne (Mg) / field level totals
  # first convert scale
  mutate(c_density = PEcAn.utils::ud_convert(prediction, "kg/m2", "Tg/ha")) |>
  mutate(total_c = c_density * area_ha)

ens_county_preds <- downscale_preds |>
  # Now aggregate to get county level totals for each pool x ensemble
  group_by(carbon_pool, county, ensemble) |>
  summarize(
    total_c = sum(total_c)
  ) |>
  arrange(carbon_pool, county, ensemble)

county_summaries <- ens_county_preds |>
    group_by(carbon_pool, county) |>
    summarize(
      n = n(),
      mean_total_c = mean(total_c),
      median_total_c = median(total_c),
      sd_total_c = sd(total_c)
    )
  
# Lets plot the results!

county_boundaries <- st_read(here::here("data/counties.gpkg")) |>
  filter(state_name == "California") |>
  select(name)

co_preds_to_plot <- county_summaries |>
  right_join(county_boundaries, by = c("county" = "name")) |>
  arrange(county, carbon_pool) |>
  pivot_longer(
    cols = c(mean_total_c, median_total_c, sd_total_c),
    names_to = "stat",
    values_to = "value"
  )

# now plot map of county-level predictions with total carbon
p <- purrr::map(cpools, function(pool) {
  .p <- ggplot(
    co_preds_to_plot |> filter(carbon_pool == pool),
    aes(geometry = geom, fill = value)
  ) +
    geom_sf(data = county_boundaries, fill = "lightgrey", color = "black") +
    geom_sf() +
    scale_fill_viridis_c(option = "plasma") +
    theme_minimal() +
    labs(
      title = paste0(pool, "-C by County"),
      fill = "Total Carbon (Tg)"
    ) +
    facet_grid(~stat)

  ggsave(
    plot = .p,
    filename = here::here(paste0("county_total_", pool, ".png")),
    width = 10, height = 5,
    bg = "white"
  )
return(.p)
})


# Load CA county boundaries
# # These are provided by Cal-Adapt as 'Areas of Interest'
# 

# # check if attributes has county name
# # Append county name to predicted table
# grid_with_counties <- st_join(ca_grid, county_boundaries, join = st_intersects)

# # Calculate county-level mean, median, and standard deviation.
# county_aggregates <- grid_with_counties |>
#   st_drop_geometry() |> # drop geometry for faster summarization
#   group_by(county_name) |> # replace with your actual county identifier
#   summarize(
#     mean_biomass   = mean(predicted_biomass, na.rm = TRUE),
#     median_biomass = median(predicted_biomass, na.rm = TRUE),
#     sd_biomass     = sd(predicted_biomass, na.rm = TRUE)
#   )

# print(county_aggregates)

# For state-level, do the same but don't group_by county

#' ````
