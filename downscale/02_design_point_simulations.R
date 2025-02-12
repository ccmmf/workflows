#' ---
#' title: "Design Point Selection"
#' author: "David LeBauer"
#' ---
#'
#' # Overview
#'
#' In the future, this workflow will:
#'
#' - Use SIPNET to simulate SOC and biomass for each design point.
#' - Generate a dataframe with site_id, lat, lon, soil carbon, biomass
#' - (Maybe) use SIPNETWOPET to evaluate downscaling model skill?
#'
#' Curently, we will use a surrogate model, SIPNETWOPET, to simulate SOC and biomass for each design point.
#'
#' ## SIPNETWOPET [surrogate model]
#'
#'
#'
#' ## SIPNETWOPET Simulation of Design Points
#'
#' We introduce a new model, SIPNETWOPET, the "Simpler Photosynthesis and EvapoTranspiration model, WithOut Photosynthesis and EvapoTranspiration".
#'
## -----------------------------------------------------------------------------
library(tidyverse)
source("downscale/sipnetwopet.R")

#'
#'
#' ### Join Design Points with Covariates
#'
## -----------------------------------------------------------------------------
design_points <- read_csv("data/final_design_points.csv")
covariates <- load("data/data_for_clust_with_ids.rda") |> get()

# Remove duplicate entries using 'id'
covariates_df <- sf::st_drop_geometry(covariates)


design_point_covs <- design_points |>
  left_join(covariates_df, by = "id")

#'
#' ### Run SIPNETWOPET
#'
## -----------------------------------------------------------------------------
set.seed(8675.309)
design_point_results <- design_point_covs |>
  dplyr::rowwise() |>
  dplyr::mutate(result = list(sipnetwopet(temp, precip, clay, ocd, twi))) |>
  tidyr::unnest(result) |>
  dplyr::select(id, ensemble_id, SOC = soc, AGB = agb)

# Transform long to wide format, unwrapping SOC list to numeric value
design_point_wide <- design_point_results |>
  tidyr::pivot_wider(
    id_cols = id,
    names_from = ensemble_id,
    values_from = SOC,
    names_prefix = "ensemble"
  ) |>
  dplyr::mutate(across(starts_with("ensemble"), ~ unlist(.)))

# Save ensemble_data as a list with date naming, matching the expected shape
ensemble_data <- list("2020-01-01" = design_point_wide)

saveRDS(ensemble_data, "cache/ensemble_data.rds")
