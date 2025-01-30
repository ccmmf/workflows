 # CCMMF phase 1a: Single-site almond MVP


 This workflow shows PEcAn running Sipnet hindcast simulations of an almond orchard in Kern County, CA. Starting from estimated initial conditions at orchard planting in 1999, we simulate 14 years of growth using PEcAn's existing Sipnet parameterization for a temperate deciduous forest, with no management activities included.

 The workflow has five components, run in this order:

 * `1_prep_get_ERA5_met.R` extracts site met data from a locally downloaded copy of the ERA5 ensemble and writes it in Sipnet's clim format.
 * `2_prep_add_precip_to_clim_files.sh` artificially adds precipitation to the Sipnet clim files, crudely approximating irrigation.
 * `3_prep_ic_build.R` extracts initial aboveground carbon from a locally downloaded LandTrendr biomass map, retrieves initial soil moisture anbd soil organic carbon, and samples from all of these to create initial condition files.
 * `4_run_model.R` and its input file `single_site_almond.xml` runs an ensemble of 100 Sipnet simulations sampling from the uncertainty in weather, initial biomass and soil conditions, and parameter values. It also performs a one-at-a-time sensitivity analysis on the parameters and creates visualizations of the results. Run it as `./4_run_model.R --settings=single_site_almond.xml 2>&1 | tee pecan_workflow_runlog.txt`
 * `5_validation.Rmd` shows validation comparisons between the model predictions and site-level measurements of SOC, biomass, NPP, and ET.


You will also need a compiled Sipnet binary from github.com/PecanProject/sipnet, a working installation of the PEcAn R packages from github.com/PecanProject/pecan or from pecanproject.r-universe.org, and some system libraries they depend on. Instructions for obtaining these are TK.
