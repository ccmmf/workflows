# Test-run of site-level irrigation files from the monitoring framework

This subdirectory contains a quick test of prototype event files that specify irrigation as a function of daily remote-sensed water balance at 34 locations across California. If successful, the algorithm will be extended to all sites. 

This test uses initial condition, PFT, and climate files prepared for the Phase 1b statewide woody crop simulations, and is set up to run in a subdirectory of the phase 1b folder. If these file don't already exist in the immediate parent directory, see the phase 1b README for directions to create or obtain them.

Files for this experiment consist of:

* Prototype irrigation files, provided here as `data/irrigation_event_files/`. Ordinarily we prefer to keep raw data outside of Git, but these are few and small enough that providing them directly seemed easiest.
* One shell script (`00_run_site_irr_test.sh`) that copies files from the parent directory and manipulates them for this experiment, then runs the model via two calls to the PEcAn run script (described next).
* One R script (`00a_run_model_siteirr.R`) that is modified from the statewide workflow's `04_run_model.R` in three ways:
	- Accepts an runtime `--event_dir` argument to specify where irrigation files will be found. Note that this is handled in a way that probably only makes sense for this specific experiment and is _not_ yet a generalized method of passing event files.
	- Copies `events.in` files into each Sipnet run directory, using files from the `--event_dir` path if specified and from the hard-coded default `data/sipnet.event` if not.
	- Passes all Sipnet model invocations to the Unix `parallel` command instead of launching them with `PEcAn.workflow::runModule.start.model.runs()`. This was a one-off hack that can (should?) be removed.
* One Rmarkdown notebook (`compare_site_vs_static_irrigation_20250519.Rmd`) that reads in results and summarizes the performance of both approaches by computing RMSE of a regression between modeled aboveground biomass and aboveground biomass reported by LandTrendr.

To run the whole experiment, set your working directory to this folder and then call `./00_run_site_irr_test.sh` followed by `Rscript -e 'rmarkdown::render("compare_site_vs_static_irrigation_20250519.Rmd")'`.
