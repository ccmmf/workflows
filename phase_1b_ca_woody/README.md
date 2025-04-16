# Statewide woody crop modeling for CCMMF phase 1b

Here we build on the single-site simulations from phase 1a to model tree growth between 2016 and 2023 in 98 orchards across California. In addition to adding sites, this run improves functionality by:

* Adding initial support for modeling irrigation events directly in Sipnet by specifying irrigation dates and amounts in file `sipnet.event`. For this run we use the same schedule for all sites, applying a fixed 1512 mm of water in the form of 2.8 cm every 4 days between April and Octobor of each year. Future phases will use remote sensed information to compute the irrigation schedule for each model run.
* Including MODIS-derived LAI in the initial conditions for each site.
* Moving most model setup tasks into prep scripts, minimizing the need for manual XML edits. Site-specific model details are now provided as `site_info.csv` and inserted into the settings file by running `xml_build.R`.
* Adding support for running models as job arrays in a Slurm cluster environment.

The workflow we discuss here is the _model execution_ workflow. Phase 1b also delivers a _model downscaling_ workflow that creates statewide carbon maps from the model outputs; we document these separately for simplicity but expect you'll usually want to run them as a set.


The model execution workflow has the following components:

* Installation
* Input prep
* Model execution
* Archive results
* Validation analysis

All instructions below assume you are working on a Linux cluster that uses Slurm as its scheduler; adjust the batch parameters as needed for your system. Many of the scripts are also configurable by editing designated lines at the top of the script; the explanations in these sections are worth reading and understanding even if you find the default configuration to be suitable.


## Installation: Sipnet, PEcAn, prebuilt input files

```{sh}
sbatch 00_install.sh
```

This will do three tasks:

### Compile Sipnet with support for irrigation events

The code to simulate irrigation events has been merged into the development version of Sipnet, but is (so far) turned off by default. `tools/install_sipnet.sh` handles turning it on as part of installation, or you can manually edit `[path/to/sipnet]/src/sipnet/modelStructures.h` to define `EVENT_HANDLER` as 1 before compiling. To adjust Sipnet installation locations, edit the `SIPNET_*` variables at the top of `00_install.sh`.

### Install or update PEcAn

If this is a brand-new installation, expect this step to take a few hours to download and compile more than 300 R packages. If you've installed PEcAn on this machine before, expect it to be just a few minutes of updating only the PEcAn packages and any dependencies whose version requirement has changed.

### Copy prebuilt input artifacts

Some files needed as inputs are time-consuming to create or require data that is tedious to retrieve; for this phase we provide these already computed as a gzipped tarball via Google Drive. Future runs will likely switch to another delivery method. Edit the `ARTIFACT_*` variables at the top of `00_install.sh` as needed.


## Create IC files

Once installation is done, complete setup by running these prep scripts:

```{sh}
module load r
sbatch -n1 --cpus-per-task=4 01_ERA5_nc_to_clim.R
srun ./02_ic_build.R
srun ./03_xml_build.R
```

### Model execution

Now run Sipnet on the prepared settings + IC files.

(Note: The 10 hour `--time` limit shown here is definitely excessive; my test runs took about half an hour of wall time on one 4-processor node).

```{sh}
module load r
sbatch --mem-per-cpu=1G --time=10:00:00 \
  --output=ccmmf_phase_1b_"$(date +%Y%m%d%H%M%S)_%j.log" \
  ./04_run_model.R -s settings.xml
```

### Archive results

Now tar up outputs + run log + selected inputs for archiving / analysis.

(Note that for filesize efficiency, this archive doesn't currently include the weather files)

```
# assumes the log I care about is the newest one as sorted by -t...
runlog=$(ls -1t ccmmf_phase_1b*.log | head -n1)
tarname=${runlog/log/tgz}
srun --mem-per-cpu=5G --time=5:00:00 \
	tar czf "$tarname" \
	"$runlog" settings.xml site_info.csv \
	output IC_files data/IC_prep
```

### Run validation analysis

Note that this requires 2023 LandTrendr outputs to be present in `data_raw/ca_composite_2023_median.tif`.

I ran this locally after copying results back to my laptop; to run it on the cluster, prefix the command below with `module load r && srun`, and to include the compiled result in the output archive edit `output IC_files data/IC_prep` to  `output IC_files data/IC_prep validate.html` in the archive step above.

```{sh}
Rscript -e 'rmarkdown::render("validate.Rmd")'
```



## Guide to the input files

We gathered static versions of required run inputs by (first running the prep scripts documented below and then) running `tools/create_input_tarball.sh`, producing a 741 MB file with MD5 hash `72870a32c3f1fc3506c67f1405dbc022`. As detailed above, download and unpack it with

```{sh}
curl -L -o cccmmf_phase_1b_input_artifacts.tgz 'https://drive.usercontent.google.com/download?id=15DVcJy-faUfLThon7ScqMwAsy_fxuLe_&export=download&confirm=t'
tar xf cccmmf_phase_1b_input_artifacts.tgz
```

which should create the following files and folders:

- `data/IC_prep/`: CSV files that were created by running `ic_build.R`. All can be recreated by rerunning it, but you'll need raw LandTrendr output (not provided here for space efficiency) to be present in `data_raw/`. To generate IC files for all sites from `IC_means.csv`, run `ic_build.R` again after unpacking them.
- `data/sipnet.event`: The event file used to specify irrigation for all sites in the run, created by running `tools/write_sipnet_event_file.R`. Should be easy to recreate any time; it's included here for convenience rather than because it's troublesome to create.
- `data_raw/ERA5_nc/`: PEcAn-formatted NetCDFs of ERA5 2016-2023 weather ensembles for each site. These were generated with `tools/prep_getERA5_met.R` and need to be converted to clim files using `tools/ERA5_nc_to_clim.R` before model run. (Why didn't we distribute the finished clim files in the input tarball? Because the netCDFs are more compact even after compression.)
- `pfts/temperate/`: posterior files for temperate deciduous woody plants as calibrated in Fer et al 2018[1]. These are the same pft used in phase 1a.
- `site_info.csv`: ID, location, and PFT assignment of each selected design point, used by all other prep scripts to find site-specific values. You can add arbitrary additional columns to track other site-level characteristics.

## Guide to the helper scripts

Scripts in the root directory whose names start with a numeral are the core workflow, intended to be run in sequence once per run of the workflow.

Scripts in `tools/` are intended to do a defined task and be run whenever that task arises. For some tasks this will be << 1x per workflow run (e.g. scripts used to create the prebuilt input files), others are used multiple times (e.g. submission scripts used once for every array job submitted to the scheduler). See each script file for a more detailed description, but briefly they are:

* `create_input_tarball.sh`: Creates `cccmmf_phase_1b_input_artifacts.tgz`. Run manually when needed
* `extract_ERA5_met.R`: Converts raw ERA5 to PEcAn standard met files. Run manually when needed
* `install_sipnet.sh`, `install_pecan.sh`: What the names say. Called by `00_install.sh`
* `make_site_info_csv.R`: Regenerates `site_info.csv` from design points. Run manually when needed
* `run_extract_ERA5_met.R`: Wrapper for `extract_ERA5_met.R` using BU cluster's scheduler settings. Run manually when needed
* `read_mapped_planting_year.R`: Creates `data/site_planting_years.csv`. Run manually when needed
* `slurm_array_submit.sh`: Sends sets of models to the Slurm scheduler. Called indirectly by `04_run_model.R`
* `write_sipnet_event_file.R`: Creates `data/sipnet.event`. Run manually when needed


## References
[1] Fer I, R Kelly, P Moorcroft, AD Richardson, E Cowdery, MC Dietze. 2018. Linking big models to big data: efficient ecosystem model calibration through Bayesian model emulation. Biogeosciences 15, 5801–5830, 2018 https://doi.org/10.5194/bg-15-5801-2018
