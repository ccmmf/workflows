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
PEcAn.logger::logger.info("Downscaling complete")

PEcAn.logger::logger.info("Downscaling model results for each ensemble member:")
metrics <- lapply(downscale_output_list, downscale_metrics)
knitr::kable(metrics)

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

PEcAn.logger::logger.info("Median downscaling model metrics:")
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
PEcAn.logger::logger.info("Aggregating to County Level")

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
  # Convert kg/m2 to Mg/ha using PEcAn.utils::ud_convert
  mutate(c_density_Mg_ha = PEcAn.utils::ud_convert(prediction, "kg/m2", "Mg/ha")) |>
  # Calculate total Mg per field: c_density_Mg_ha * area_ha
  mutate(total_c_Mg = c_density_Mg_ha * area_ha)

ens_county_preds <- downscale_preds |>
  # Now aggregate to get county level totals for each pool x ensemble
  group_by(carbon_pool, county, ensemble) |>
  summarize(
    n = n(),
    total_c_Mg = sum(total_c_Mg),      # total Mg C per county
    total_ha = sum(area_ha)
  ) |>
  ungroup() |>
  mutate(
    total_c_Tg = PEcAn.utils::ud_convert(total_c_Mg, "Mg", "Tg"),
    mean_c_density_Mg_ha = total_c_Mg / total_ha
  ) |>
  arrange(carbon_pool, county, ensemble)

# Check number of ensemble members per county/carbon_pool
ens_county_preds |>
  group_by(carbon_pool, county) |>
  summarize(n_vals = n_distinct(total_c_Mg)) |>
  pull(n_vals) |>
  unique()


county_summaries <- ens_county_preds |>
    group_by(carbon_pool, county) |>
    summarize(
      n = max(n), # Number of fields in county should be same for each ensemble member
      co_mean_c_total_Tg = mean(total_c_Tg),
      co_sd_c_total_Tg = sd(total_c_Tg),
      co_mean_c_density_Mg_ha = mean(mean_c_density_Mg_ha),
      co_sd_c_density_Mg_ha = sd(mean_c_density_Mg_ha)
    )

readr::write_csv(
  county_summaries,
  file.path(outdir, "county_summaries.csv")
)
PEcAn.logger::logger.info("County summaries written to", file.path(outdir, "county_summaries.csv"))

## Plot the results!
PEcAn.logger::logger.info("Plotting County Level Summaries")
county_boundaries <- st_read(here::here("data/counties.gpkg")) |>
  filter(state_name == "California") |>
  select(name)

co_preds_to_plot <- county_summaries |>
  right_join(county_boundaries, by = c("county" = "name")) |>
  arrange(county, carbon_pool) |>
  pivot_longer(
    cols = c(mean_total_c_Tg, sd_total_c_Tg, mean_c_density_Mg_ha, sd_c_density_Mg_ha),
    names_to = "stat",
    values_to = "value"
  ) |>
  mutate(units = case_when(
    str_detect(stat, "total_c") ~ "Carbon Stock (Tg)",
    str_detect(stat, "c_density") ~ "Carbon Density (Mg/ha)"
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
    ifelse(unit == "Carbon Density (Mg/ha)", "density", NA)
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

# TODO consider separating out plotting 
####---Create checkpoint---####
# system.time(save(downscale_output_list, importance_summary, covariates, cpools# these are ~500MB
#   file = file.path(outdir, "checkpoint.RData"),
#   compress = FALSE
# ))
# outdir <- "/projectnb/dietzelab/ccmmf/ccmmf_phase_1b_20250319064759_14859/output/out"
# load(file.path(outdir, "checkpoint.RData"))
#### ---End checkpoint---####

covariate_names <- names(covariates |> select(where(is.numeric)))
covariates_df <- as.data.frame(covariates) |>
  # TODO pass scaled covariates from ensemble_downscale function
  #    this will ensure that the scaling is the same.
  mutate(covariates, across(all_of(covariate_names), scale))

##### Subset data for plotting (speed + visible rug plots) #######
subset_inputs <- TRUE
# Subset data for testing / speed purposes
if (subset_inputs) {
  # cpools <- c("AGB")

  # Subset covariates for testing (take only a small percentage of rows)
  n_test_samples <- min(5000, nrow(covariates_df))
  set.seed(123) # For reproducibility
  test_indices <- sample(1:nrow(covariates_df), n_test_samples)
  covariates_full <- covariates_df
  covariates_df <- covariates_df[test_indices, ]

  # For each model, subset the predictions to match the test indices
  for (cp in cpools) {
    if (length(downscale_output_list[[cp]]$predictions) > 0) {
      downscale_output_list[[cp]]$predictions <-
        lapply(downscale_output_list[[cp]]$predictions, function(x) x[test_indices])
    }
  }
}

##### End Subsetting Code#######

##### Importance Plots #####


for (cp in cpools) {
  png(
    filename = here::here("downscale/figures", paste0(cp, "_importance_partial_plots.png")),
    width = 14, height = 6, units = "in", res = 300, bg = "white"
  )

  # Variable importance plot
  cp_importance <- importance_summary |>
    filter(carbon_pool == cp)
  with(
    cp_importance,
    dotchart(median_importance,
      labels = reorder(predictor, median_importance),
      xlab = "Median Increase MSE (SD)",
      main = paste("Importance -", cp),
      pch = 19, col = "steelblue", cex = 1.2
    )
  )
  with(
    cp_importance,
    segments(lcl_importance,
      seq_along(predictor),
      ucl_importance,
      seq_along(predictor),
      col = "gray50"
    )
  )
  dev.off()
}

##### Importance and Partial Plots #####

## Using pdp + ggplot2
# # Loop over carbon pools
# for (cp in cpools) {
#   # Top 2 predictors for this carbon pool
#   top_predictors <- importance_summary |>
#     filter(carbon_pool == cp) |>
#     arrange(desc(median_importance)) |>
#     slice_head(n = 2) |>
#     pull(predictor)

#   # Retrieve model and covariate data
#   model <- downscale_output_list[[cp]][["model"]][[1]]
#   cov_df <- covariates_df # Already scaled

#   ## 1. Create Variable Importance Plot with ggplot2
#   cp_importance <- importance_summary |>
#     filter(carbon_pool == cp)

#   p_importance <- ggplot(cp_importance, aes(x = median_importance, y = reorder(predictor, median_importance))) +
#     geom_point(color = "steelblue", size = 3) +
#     geom_errorbarh(aes(xmin = lcl_importance, xmax = ucl_importance),
#       height = 0.2,
#       color = "gray50"
#     ) +
#     labs(
#       title = paste("Importance -", cp),
#       x = "Median Increase in MSE (SD)",
#       y = ""
#     ) +
#     theme_minimal()

#   ## 2. Create Partial Dependence Plot for the top predictor
#   pd_data1 <- pdp::partial(
#     object = model,
#     pred.var = top_predictors[1],
#     pred.data = cov_df,
#     train = cov_df,
#     plot = FALSE
#   )
#   ## Partial dependence for predictor 1
#   p_partial1 <- ggplot(pd_data1, aes_string(x = top_predictors[1], y = "yhat")) +
#     geom_line(color = "steelblue", size = 1.2) +
#     geom_rug(
#       data = cov_df, aes_string(x = top_predictors[1]),
#       sides = "b", alpha = 0.5
#     ) +
#     labs(
#       title = paste("Partial Dependence -", top_predictors[1]),
#       x = top_predictors[1],
#       y = paste("Predicted", cp)
#     ) +
#     theme_minimal()

#   ## Partial dependence for predictor 2
#   pd_data2 <- pdp::partial(
#     object = model,
#     pred.var = top_predictors[2],
#     pred.data = cov_df,
#     plot = TRUE,
#     train = cov_df,
#     parallel = TRUE
#   )

#   p_partial2 <- ggplot(pd_data2, aes_string(x = top_predictors[2], y = "yhat")) +
#     geom_line(color = "steelblue", size = 1.2) +
#     geom_rug(
#       data = cov_df, aes_string(x = top_predictors[2]),
#       sides = "b", alpha = 0.5
#     ) +
#     labs(
#       title = paste("Partial Dependence -", top_predictors[2]),
#       x = top_predictors[2],
#       y = paste("Predicted", cp)
#     ) +
#     theme_minimal()

#   combined_plot <- p_importance + p_partial1 + p_partial2 + plot_layout(ncol = 3)

#   output_file <- here("downscale/figures", paste0(cp, "_importance_partial_plots.png"))
#   ggsave(
#     filename = output_file,
#     plot = combined_plot,
#     width = 14, height = 6, dpi = 300, bg = "white"
#   )

#   # also save pdp-generated plot 
#   pdp_plots <- p_data1 + p_data2
#   ggsave(pdp_plots,
#     filename = here::here("downscale/figures", paste0(cp, "_PDP_", 
#       top_predictors[1], "_", top_predictors[2], ".png")),
#     width = 6, height = 4, dpi = 300, bg = "white"
#   )
# }

## Using randomForest::partialPlot()
# Combined importance + partial plots for each carbon pool


# for (cp in cpools) {
#   # Top 2 predictors for this carbon pool
#   top_predictors <- importance_summary |>
#     filter(carbon_pool == cp) |>
#     arrange(desc(median_importance)) |>
#     slice_head(n = 2) |>
#     pull(predictor)

#   # Prepare model and subset of covariates for plotting
#   model <- downscale_output_list[[cp]][["model"]][[1]]
#   cov_df <- covariates_df

#   # Set up PNG for three panel plot
#   png(
#     filename = here::here("downscale/figures", paste0(cp, "_importance_partial_plots.png")),
#     width = 14, height = 6, units = "in", res = 300, bg = "white"
#   )
#   par(mfrow = c(1, 3))

#   # Panel 1: Variable importance plot
#   cp_importance <- importance_summary |> filter(carbon_pool == cp)
#   par(mar = c(5, 10, 4, 2))
#   with(
#     cp_importance,
#     dotchart(median_importance,
#       labels = reorder(predictor, median_importance),
#       xlab = "Median Increase MSE (SD)",
#       main = paste("Importance -", cp),
#       pch = 19, col = "steelblue", cex = 1.2
#     )
#   )
#   with(
#     cp_importance,
#     segments(lcl_importance,
#       seq_along(predictor),
#       ucl_importance,
#       seq_along(predictor),
#       col = "gray50"
#     )
#   )

#   # Panel 2: Partial plot for top predictor
#   par(mar = c(5, 5, 4, 2))
#   randomForest::partialPlot(model,
#     pred.data = cov_df,
#     x.var = top_predictors[1],
#     main = paste("Partial Dependence -", top_predictors[1]),
#     xlab = top_predictors[1],
#     ylab = paste("Predicted", cp),
#     col = "steelblue",
#     lwd = 2
#   )

#   # Panel 3: Partial plot for second predictor
#   randomForest::partialPlot(model,
#     pred.data = cov_df,
#     x.var = top_predictors[2],
#     main = paste("Partial Dependence -", top_predictors[2]),
#     xlab = top_predictors[2],
#     ylab = paste("Predicted", cp),
#     col = "steelblue",
#     lwd = 2
#   )
#   dev.off() # Save combined figure
# }
