#' ---
#' Title: Downscale and Aggregate Woody Crop SOC stocks
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
library(pdp)       # for computing partial dependence plots

library(PEcAnAssimSequential)
datadir <- "/projectnb/dietzelab/ccmmf/data"
basedir <- "/projectnb/dietzelab/ccmmf/ccmmf_phase_1b_20250319064759_14859"
settings <- PEcAn.settings::read.settings(file.path(basedir, "settings.xml"))
outdir <- file.path(basedir, settings$modeloutdir)
options(readr.show_col_types = FALSE)
set.seed(123)


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
    c_density = total_c / total_ha
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

# Now create and save combined importance + partial plots for each carbon pool
for (cp in cpools) {
  
  # Filter importance data for carbon pool cp
  cp_importance <- importance_summary |>
    dplyr::filter(carbon_pool == cp)
  
  # Select top 2 predictors
  top_predictors <- cp_importance |>
    dplyr::arrange(dplyr::desc(median_importance)) |>
    dplyr::slice_head(n = 2) |>
    dplyr::pull(predictor)
  
  # Build variable importance plot for carbon pool cp
  p_importance_cp <- ggplot2::ggplot(cp_importance, 
                                     ggplot2::aes(x = reorder(predictor, median_importance),
                                                  y = median_importance)) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = lcl_importance, ymax = ucl_importance),
                           width = 0.2, color = "gray50") +
    ggplot2::geom_point(size = 4, color = "steelblue") +
    ggplot2::coord_flip() +
    ggplot2::labs(title = paste("Variable Importance -", cp),
                  x = "Predictor",
                  y = "Median Increase MSE (SD)") +
    ggplot2::theme_minimal()
  
  model <- downscale_output_list[[cp]][["model"]][[1]]
  
  # Bin top predictors in covariates to make partial dependence faster
  # Covariates is ~400k rows, so binning will speed up the process
  binned_covariates_df <- covariates |>
    dplyr::mutate(dplyr::across(dplyr::all_of(top_predictors), ~ cut(.x, breaks = 100, labels = FALSE))) |>
    as.data.frame()
  
  # Compute partial dependence for the top predictors,
  # explicitly supplying the predict function via an anonymous function.
  pd1 <- pdp::partial(object = model,
                 pred.var = top_predictors[1],
                 train = binned_covariates_df,
                 grid.resolution = 10,
                 .f = function(object, newdata) stats::predict(object, newdata))
  
  pd2 <- as.data.frame(
    pdp::partial(object = model,
                 pred.var = top_predictors[2],
                 train = binned_covariates_df,
                 grid.resolution = 10,
                 .f = function(object, newdata) stats::predict(object, newdata))
  )
  
  # Build ggplot-based partial dependence plots for each top predictor
  p_pd1 <- ggplot2::ggplot(pd1, ggplot2::aes(x = !!sym(top_predictors[1]), y = yhat)) +
    ggplot2::geom_line(linewidth = 1.2, color = "steelblue") +
    ggplot2::labs(title = paste("Partial Dependence for", top_predictors[1]),
                  x = top_predictors[1],
                  y = paste("Predicted", cp)) +
    ggplot2::theme_minimal()
  
  p_pd2 <- ggplot2::ggplot(pd2, ggplot2::aes(x = !!sym(top_predictors[2]), y = yhat)) +
    ggplot2::geom_line(linewidth = 1.2, color = "steelblue") +
    ggplot2::labs(title = paste("Partial Dependence for", top_predictors[2]),
                  x = top_predictors[2],
                  y = paste("Predicted", cp)) +
    ggplot2::theme_minimal()
  
  # Combine the importance and partial dependence plots using patchwork
  combined_plot <- p_importance_cp + p_pd1 + p_pd2 + 
    patchwork::plot_layout(ncol = 3)
  
   ggplot2::ggsave(filename = here::here("downscale/figures", paste0(cp, "_importance_partial_plots.png")),
                  plot = combined_plot,
                  width = 14, height = 6, bg = "white")
  
}
