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
design_points <- read_csv("data/design_points.csv") |> distinct()
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

# Convert design_point_results into arrays using pivot_wider and as.array
arr_soc_matrix <- design_point_results |>
  select(id, ensemble_id, SOC) |>
  pivot_wider(names_from = ensemble_id, values_from = SOC) |>
  column_to_rownames("id") |>
  as.matrix()

arr_soc <- as.array(arr_soc_matrix)
dim(arr_soc) <- c(1, nrow(arr_soc_matrix), ncol(arr_soc_matrix))
dimnames(arr_soc) <- list(datetime = "2020-01-01",
                          site = rownames(arr_soc_matrix),
                          ensemble = colnames(arr_soc_matrix))

arr_agb_matrix <- design_point_results |>
  select(id, ensemble_id, AGB) |>
  pivot_wider(names_from = ensemble_id, values_from = AGB) |>
  column_to_rownames("id") |>
  as.matrix()

arr_agb <- as.array(arr_agb_matrix)
dim(arr_agb) <- c(1, nrow(arr_agb_matrix), ncol(arr_agb_matrix))
dimnames(arr_agb) <- list(datetime = "2020-01-01",
                          site = rownames(arr_agb_matrix),
                          ensemble = colnames(arr_agb_matrix))

ensemble_arrays <- list(SOC = arr_soc, AGB = arr_agb)
saveRDS(ensemble_arrays, "cache/efi_ensemble_arrays.rds")
