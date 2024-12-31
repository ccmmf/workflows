 # CCMMF phase 1a: Single-site almond MVP


 This workflow shows PEcAn running Sipnet hindcast simulations of an almond orchard in Kern County, CA. Starting from estimated initial conditions at orchard planting in 1999, we simulate 14 years of growth using PEcAn's existing Sipnet parameterization for a temperate deciduous forest, with no management activities included.

 The workflow has three components, run in this order:

 * `get_ERA5_met.R` extracts site met data from a locally downloaded copy of the ERA5 ensemble and writes it in Sipnet's clim format.
 * `ic_build.R` extracts initial aboveground carbon from a locally downloaded LandTrendr biomass map, retrieves initial soil moisture anbd soil organic carbon, and samples from all of these to create initial condition files.
 * `workflow.R` and its input file `single_site_almond.xml` runs an ensemble of 100 Sipnet simulations sampling from the uncertainty in weather, initial biomass and soil conditions, and parameter values. It also performs a one-at-a-time sensitivity analysis on the parameters and creates visualizations of the results.

 TK: validation comparisons between the model predictions and site-level measurements of SOC, NPP, and ET
