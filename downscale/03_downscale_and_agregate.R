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
#'   - Uses Random Forest [may change to CNN later] trained on site-scale model runs.
#'   - Build a model for each ensemble member
#' - Write out a table with predicted biomass and SOC to maintain ensemble structure, ensuring correct error propagation and spatial covariance.
#' - Aggregate County-level biomass and SOC inventories
#'
## ----setup--------------------------------------------------------------------
library(tidyverse)
library(sf)
library(terra)
library(furrr)
library(patchwork) # for combining plots

no_cores <- parallel::detectCores(logical = FALSE)
plan(multicore, workers = no_cores - 1)

# while developing PEcAn:
# devtools::load_all(here::here("../pecan/modules/assim.sequential/"))
#remotes::install_git("../pecan@ensemble_downscaling",
remotes::install_github("dlebauer/pecan@ensemble_downscaling",
  subdir = "modules/assim.sequential", upgrade = FALSE
)
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
  ) |>
  mutate(units = case_when(
    str_detect(stat, "total_c") ~ "Carbon Stock (Tg)",
    str_detect(stat, "c_density") ~ "Carbon Density (kg/m2)"
  ), stat = case_when(
    str_detect(stat, "mean") ~ "Mean",
    str_detect(stat, "sd") ~ "SD"
  ))

# now plot map of county-level predictions with total carbon
units <- rep(unique(co_preds_to_plot$units), each = length(cpools))
pool_x_units <- co_preds_to_plot |>
  select(carbon_pool, units) |>
  distinct() |>
  # remove na
  filter(!is.na(carbon_pool)) |> # why is one field in SF county NA?
  arrange(carbon_pool, units)

p <- purrr::map2(pool_x_units$carbon_pool, pool_x_units$units, function(pool, unit) {
  .p <- ggplot(
    co_preds_to_plot |> filter(carbon_pool == pool & units == unit),
    aes(geometry = geom, fill = value)
  ) +
    geom_sf(data = county_boundaries, fill = "lightgrey", color = "black") +
    geom_sf() +
    scale_fill_viridis_c(option = "plasma") +
    theme_minimal() +
    facet_grid(carbon_pool ~ stat) +
    labs(
      title = paste("County-Level Predictions for", pool, unit),
      fill = "Value"
    )

  unit <- ifelse(unit == "Carbon Stock (Tg)", "stock",
    ifelse(unit == "Carbon Density (kg/m2)", "density", NA)
  )

  plotfile <- here::here("downscale/figures", paste0("county_", pool, "_carbon_", unit, ".png"))
  print(plotfile)
  ggsave(
    plot = .p,
    filename = plotfile,
    width = 10, height = 5,
    bg = "white"
  )
  return(.p)
})

# Variable Importance and Partial Dependence Plots

# First, calculate variable importance summary as before
importance_summary <- map_dfr(cpools, function(cp) {
  # Extract the importance for each ensemble model in the carbon pool
  importances <- map(1:20, function(i) {
    model <- downscale_output_list[[cp]][["model"]][[i]]
    randomForest::importance(model)[, "%IncMSE"]
  })

  # Turn the list of importance vectors into a data frame
  importance_df <- map_dfr(importances, ~ tibble(importance = .x), .id = "ensemble") |>
    group_by(ensemble) |>
    mutate(predictor = names(importances[[1]])) |>
    ungroup()

  # Now summarize median and IQR for each predictor across ensembles
  summary_df <- importance_df |>
    group_by(predictor) |>
    summarize(
      median_importance = median(importance, na.rm = TRUE),
      lcl_importance = quantile(importance, 0.25, na.rm = TRUE),
      ucl_importance = quantile(importance, 0.75, na.rm = TRUE)
    ) |>
    mutate(carbon_pool = cp)

  summary_df
})

# Create importance plot
p_importance <- ggplot(importance_summary, aes(x = reorder(predictor, median_importance), y = median_importance)) +
  geom_errorbar(aes(ymin = lcl_importance, ymax = ucl_importance), width = 0.2, color = "gray50") +
  geom_point(size = 4, color = "steelblue") +
  coord_flip() +
  facet_wrap(~carbon_pool, scales = "free_y") +
  labs(
    title = "Variable Importance",
    x = "Predictor",
    y = "Median Increase MSE (SD)"
  ) +
  theme_minimal()

# Save importance plot
ggsave(p_importance, filename = here::here("downscale/figures", "importance_summary.png"),
  width = 10, height = 5, bg = "white"
)

# Now create and save combined importance + partial plots for each carbon pool
for (cp in cpools) {
  # Find top 2 predictors for this carbon pool
  top_predictors <- importance_summary |>
    filter(carbon_pool == cp) |>
    arrange(desc(median_importance)) |>
    slice_head(n = 2) |>
    pull(predictor)
  
  # Set up a 3-panel plot
  png(filename = here::here("downscale/figures", paste0(cp, "_importance_partial_plots.png")),
      width = 14, height = 6, units = "in", res = 300, bg = "white")
  
  par(mfrow = c(1, 3))
  
  # Panel 1: Show only this carbon pool's importance plot
  # Extract just this carbon pool's data
  cp_importance <- importance_summary |> filter(carbon_pool == cp)
  
  # Create importance plot for just this carbon pool
  par(mar = c(5, 10, 4, 2)) # Adjust margins for first panel
  with(cp_importance, 
       dotchart(median_importance, 
                labels = reorder(predictor, median_importance),
                xlab = "Median Increase MSE (SD)",
                main = paste("Variable Importance -", cp),
                pch = 19, col = "steelblue", cex = 1.2))
  
  # Add error bars
  with(cp_importance, 
       segments(lcl_importance, 
                seq_along(predictor), 
                ucl_importance, 
                seq_along(predictor),
                col = "gray50"))
  
  # Panels 2 & 3: Create partial plots for top 2 predictors
  model <- downscale_output_list[[cp]][["model"]][[1]]
  
  # First top predictor partial plot
  par(mar = c(5, 5, 4, 2)) # Reset margins for other panels
  randomForest::partialPlot(model, 
                           pred.data = covariates, 
                           x.var = top_predictors[1], 
                           main = paste("Partial Dependence Plot for", top_predictors[1]),
                           xlab = top_predictors[1], 
                           ylab = paste("Predicted", cp),
                           col = "steelblue", 
                           lwd = 2)
  
  # Second top predictor partial plot
  randomForest::partialPlot(model, 
                           pred.data = covariates, 
                           x.var = top_predictors[2], 
                           main = paste("Partial Dependence Plot for", top_predictors[2]),
                           xlab = top_predictors[2], 
                           ylab = paste("Predicted", cp),
                           col = "steelblue", 
                           lwd = 2)
  
  dev.off()
}

print(p_importance)
