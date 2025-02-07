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
design_points <- read_csv('data/final_design_points.csv') 
covariates <- load("data/data_for_clust_with_ids.rda") |> get()

design_point_covs <- design_points |> 
  left_join(sf::st_drop_geometry(covariates), by = 'id')

#' 
#' ### Run SIPNETWOPET
#' 
## -----------------------------------------------------------------------------
set.seed(8675.309)
design_point_results <- design_point_covs |> 
  dplyr::rowwise() |> 
  dplyr::mutate(result = list(sipnetwopet(temp, precip, clay, ocd, twi))) |> 
  tidyr::unnest(result) |> 
  dplyr::select(id, lat, lon, soc, agb, ensemble_id)


ensemble_data <- design_point_results |>
  dplyr::group_by(ensemble_id) |>
  dplyr::summarize(
    SOC = list(soc),
    AGB = list(agb),
    .groups = "drop"
  )

saveRDS(design_point_results, 'cache/design_point_results.rds')

class(covariates)
write_csv(design_point_results, 'cache/sipnetwopet_design_point_results.csv')

#' 
#' 
#' ### SIPNETWOPET Example
#' 
## ----sipnetwopet-demo, eval=FALSE---------------------------------------------
# # Example dataset
# n <- 100
# set.seed(77.77)
# example_sites <- tibble::tibble(
#   mean_temp = rnorm(n, 16, 2),
#   precip = rweibull(n, shape = 2, scale = 4000),
#   clay = 100 * rbeta(n, shape1 = 2, shape2 = 5),
#   ocd = rweibull(n, shape = 2, scale = 320),
#   twi = rweibull(n, shape = 2, scale = 15)
# )
# 
# # Apply function using rowwise mapping
# example_results <- example_sites |>
#   dplyr::rowwise() |>
#   dplyr::mutate(result = list(sipnetwopet(mean_temp, precip, clay, ocd, twi))) |>
#   tidyr::unnest(result)
# 
# print(example_results)
# pairs(example_results)

