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
library(tidyverse)
library(sf)
library(terra)
library(furrr)

no_cores <- parallel::detectCores(logical = FALSE)
plan(multicore, workers = no_cores - 1)

# while developing PEcAn:
# devtools::load_all(here::here("../pecan/modules/assim.sequential/"))
# remotes::install_git("dlebauer/pecan@ensemble_downscaling", subdir = "modules/assim.sequential")
remotes::install_git("../pecan@ensemble_downscaling", subdir = "modules/assim.sequential", upgrade = FALSE)
library(PEcAnAssimSequential)
datadir <- "/projectnb/dietzelab/ccmmf/data"
basedir <- "/projectnb/dietzelab/ccmmf/ccmmf_phase_1b_20250319064759_14859"
settings <- PEcAn.settings::read.settings(file.path(basedir, "settings.xml"))
outdir <- file.path(basedir, settings$modeloutdir)
options(readr.show_col_types = FALSE)


#' ## Get Site Level Outputs
ensemble_file <- file.path(outdir, "efi_ens_long.csv")
ensemble_data <- readr::read_csv(ensemble_file) 

#' ### Random Forest using PEcAn downscale workflow
## -----------------------------------------------------------------------------
design_pt_csv <- "https://raw.githubusercontent.com/ccmmf/workflows/46a61d58a7b0e43ba4f851b7ba0d427d112be362/data/design_points.csv"
design_points <- read_csv(design_pt_csv) |> #read_csv(here::here("data/design_points.csv")) |>
  dplyr::distinct()

covariates_csv <- file.path(datadir, "site_covariates.csv")
covariates <- read_csv(covariates_csv) |>
  select(
    site_id, where(is.numeric),
    -climregion_id
  )

downscale_carbon_pool <- function(date, carbon_pool) {
  filtered_ens_data <- subset_ensemble(
    ensemble_data = ensemble_data,
    site_coords   = design_points,
    date          = date,
    carbon_pool   = carbon_pool
  )

  # Downscale the data
  downscale_output <- ensemble_downscale(
    ensemble_data = filtered_ens_data,
    site_coords   = design_points,
    covariates    = covariates,
    seed          = 123
  )
  return(downscale_output)
}

cpools <- c("TotSoilCarb", "AGB")

downscale_output_list <- purrr::map( # not using furrr b/c it is used inside downscale
  cpools,
  ~ downscale_carbon_pool(date = "2018-12-31", carbon_pool = .x)
) |>
  purrr::set_names(cpools)

## Check variable importance

## Save to make it easier to restart
# saveRDS(downscale_output, file = here::here("cache/downscale_output.rds"))

metrics <- lapply(downscale_output_list, downscale_metrics)
print(metrics)

median_metrics <- purrr::map(metrics, function(m) {
  m |>
    select(-ensemble) |>
    summarise(#do equivalent of colmeans but for medians)
      across(
        everything(),
        list(median = ~ median(.x)),
        .names = "{col}"
      )
    )
})

bind_rows(median_metrics, .id = "carbon_pool") |>
  knitr::kable()

#'
#'
#' ## Aggregate to County Level
#'
## -----------------------------------------------------------------------------

# ca_fields <- readr::read_csv(here::here("data/ca_field_attributes.csv")) |>
#   dplyr::select(id, lat, lon) |>
#   rename(site = id)

ca_fields_full <- sf::read_sf(file.path(datadir, "ca_fields.gpkg"))

ca_fields <- ca_fields_full |>
  dplyr::select(site_id, county, area_ha)  

# Convert list to table with predictions and site identifier
get_downscale_preds <- function(downscale_output_list) {
  purrr::map(
    downscale_output_list$predictions,
    ~ tibble(site_id = covariates$site_id, prediction = .x)
  ) |>
    bind_rows(.id = "ensemble") |>
    left_join(ca_fields, by = "site_id") 
}

downscale_preds <- purrr::map(downscale_output_list, get_downscale_preds) |>
  dplyr::bind_rows(.id = "carbon_pool") |>
  # Convert kg / ha to tonne (Mg) / field level totals
  # first convert scale
  mutate(c_density = PEcAn.utils::ud_convert(prediction, "kg/m2", "Tg/ha")) |>
  mutate(total_c = c_density * area_ha)

ens_county_preds <- downscale_preds |>
  # Now aggregate to get county level totals for each pool x ensemble
  group_by(carbon_pool, county, ensemble) |>
  summarize(
    total_c = sum(total_c),
    total_ha = sum(area_ha)
  ) |>
  ungroup() |>
  mutate(
    c_density = PEcAn.utils::ud_convert(total_c / total_ha, "Tg/ha", "kg/m2")
  ) |>
  arrange(carbon_pool, county, ensemble)

county_summaries <- ens_county_preds |>
    group_by(carbon_pool, county) |>
    summarize(
      n = n(),
      mean_total_c = mean(total_c),
      #median_total_c = median(total_c),
      sd_total_c = sd(total_c),
      mean_c_density = mean(c_density),
      sd_c_density = sd(c_density)
    )

readr::write_csv(
  county_summaries,
  file.path(outdir, "county_summaries.csv")
)
  
# Lets plot the results!

county_boundaries <- st_read(here::here("data/counties.gpkg")) |>
  filter(state_name == "California") |>
  select(name)

co_preds_to_plot <- county_summaries |>
  right_join(county_boundaries, by = c("county" = "name")) |>
  arrange(county, carbon_pool) |>
  pivot_longer(
    cols = c(mean_total_c, sd_total_c, mean_c_density, sd_c_density),
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
    filename = here::here("downscale/figures",paste0("county_total_", pool, ".png")),
    width = 10, height = 5,
    bg = "white"
  )
return(.p)
})

## Variable Importance

# importance_summary <- map_dfr(cpools, function(cp) {
#   # Extract the importance for each ensemble model in the carbon pool
#   importances <- map(1:20, function(i) {
#     model <- downscale_output_list[[cp]][["model"]][[i]]
#     randomForest::importance(model)[, "%IncMSE"]
#   })

#   # Turn the list of importance vectors into a data frame
#   importance_df <- map_dfr(importances, ~ tibble(importance = .x), .id = "ensemble") |>
#     group_by(ensemble) |>
#     mutate(predictor = names(importances[[1]])) |>
#     ungroup()

#   # Now summarize median and IQR for each predictor across ensembles
#   summary_df <- importance_df |>
#     group_by(predictor) |>
#     summarize(
#       median_importance = median(importance, na.rm = TRUE),
#       sd_importance = sd(importance, na.rm = TRUE)
#     ) |>
#     mutate(carbon_pool = cp)

#   summary_df
# })

# library(ggplot2)
# library(dplyr)

# # Create the popsicle (lollipop) plot
# p <- ggplot(importance_summary, aes(x = reorder(predictor, median_importance), y = median_importance)) +
#   geom_errorbar(aes(ymin = median_importance - sd_importance, ymax = median_importance + sd_importance),
#     width = 0.2, color = "gray50"
#   ) +
#   geom_point(size = 4, color = "steelblue") +
#   coord_flip() +
#   facet_wrap(~carbon_pool, scales = "free_y") +
#   labs(
#     title = "Popsicle Plot of Variable Importance",
#     x = "Predictor",
#     y = "Median %IncMSE (<U+00B1> SD)"
#   ) +
#   theme_minimal()

# ggsave(p, filename = here::here("downscale/figures", "importance_summary.png"),
#   width = 10, height = 5,
#   bg = "white"
# )

# print(p)
