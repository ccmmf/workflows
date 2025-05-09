# CCMMF phase 1a: Single-site almond MVP


 This workflow shows PEcAn running Sipnet hindcast simulations of an almond orchard in Kern County, CA[1]. Starting from estimated initial conditions at orchard planting in 1999, we simulate 14 years of growth using PEcAn's existing SIPNET parameterization for a temperate deciduous forest, with no management activities included.

 The workflow has the following components, run in this order:

* Installation and system setup.
  - You will need at least a compiled SIPNET binary from https://github.com/PecanProject/sipnet, a working installation of R and the PEcAn R packages from https://github.com/PecanProject/pecan or from https://pecanproject.r-universe.org, and some system libraries these depend on.
  - See below for more instructions.
* Input prep steps, for which we provide output files in `00_ccmmf_phase_1a_artifacts.tgz` that can be recreated or altered using these scripts plus the prerequisite files documented [below](#artifacts-needed-before-running-the-model).
  - `01_prep_get_ERA5_met.R` extracts site met data from a locally downloaded copy of the ERA5 ensemble and writes it to new files in SIPNET's `clim` input format.
  - `02_prep_add_precip_to_clim_files.sh` artificially adds precipitation to the SIPNET clim files, crudely approximating irrigation.
  - `03_prep_ic_build.R` extracts initial aboveground carbon from a locally downloaded LandTrendr biomass map, retrieves initial soil moisture anbd soil organic carbon, and samples from all of these to create initial condition files.
* Run SIPNET on the prepared inputs.
  - `04_run_model.R` and its input file `single_site_almond.xml` runs an ensemble of 100 SIPNET simulations sampling from the uncertainty in weather, initial biomass and soil conditions, and parameter values. It also creates visualizations of the results, and can perform a one-at-a-time sensitivity analysis on the parameters (but this is turned off by default for speed. To enable it, uncomment the `sensitivity.analysis` section of `single_site.almond.xml`).
* Analyze the results.
  - `05_validation.Rmd` shows validation comparisons between the model predictions and site-level measurements of SOC, biomass, NPP, and ET.
* Archive run outputs.
  - `tools/compress_output.sh` creates a compressed tarball of the `outputs/` directory, the compiled validation notebook, and any log files.


## System setup

This workflow has been tested on a laptop running MacOS 14.7 and a Linux cluster running Rocky Linux 8.10, both using PEcAn revision f184978397 and SIPNET revision 592700c, which were the most recent commits in the PEcAn `develop` branch and SIPNET `master` branch on 2025-02-10.

We show here two options for installation onto an HPC cluster: **direct installation** or **container-based** using apptainer. Direct installation is more flexible and allows you to use your own R and PEcAn installations; container based provides a preconfigured computing environment that is more deeply tested (PEcAn's CI system uses the same containers) but version options are limited to those provided by the PEcAn team.

The installation process on other machine types should be similar to what is shown here, but may need modification; for example if installing on a laptop you may not have/want modules (so skip `module load...` steps) or a job queue (so type `cmd [cmd-options]` where these instructions say `sbatch [slurm-options] cmd [cmd-options]`).

Please report any trouble you encounter during installation or execution so that we can help fix it.

### Steps common to both direct and container-based installation methods

* Starting in the directory of your choice, clone this repository onto your machine.
  - `git clone https://github.com/ccmmf/workflows`
* All remaining steps use the phase a1 directory as their workdir:
  - `cd workflows/phase_a1_single_site_almond/`
* Download and unpack input files into the working directory:
  - `curl -L -o 00_cccmmf_phase_1a_input_artifacts.tgz 'https://drive.usercontent.google.com/download?id=1sDOp_d3OIdSnTj1S4a4LWFLHXWlQO7Zm&export=download&confirm=t'`
  - `tar xf 00_cccmmf_phase_1a_input_artifacts.tgz`

Now choose _either_ Direct or Container based installation instructions below. 

### Direct installation

* Install SIPNET (fast; seconds): `srun ./tools/install_sipnet.sh ~/sipnet/ ~/sipnet_binaries/ ./sipnet.git`
  - The 3 arguments are: path into which to clone the SIPNET repo, dir in which to store compiled binaries, and path for a symlink to the binary.
  - If you change the last argument, update the `<binary>sipnet.git</binary>` line of `single_site_almond.xml` to match.
* Install PEcAn (slow; hours): `sbatch -o install_pecan.out ./tools/install_pecan.sh`
  - Installs more than 300 R packages! On our test system this took about 2 hours
  - Defaults to using 4 CPUs to compile packages in parallel. If you have more cores, adjust `sbatch`'s `--cpus-per-task` parameter.

### Container-based installation

```{sh}
module load apptainer
apptainer pull docker://pecan/model-sipnet-git:develop
```

This will compile an image file named `model-sipnet-git_develop.sif`. Typical usage will look like `apptainer run <options> model-sipnet-git_develop.sif <pecan_command>`.

## Guide to the input files

As described above, the inputs to this workflow were generated by the three `prep` scripts and can be regenerated with them, but these rely on several upstream artifacts that are very large and/or inconvenient to download (raw ERA5 data, LandTrendr tiles). Future phases of the project will streamline these steps, but for simplicity today we provide the prepared files as a single archive named `00_cccmmf_phase_1a_input_artifacts.tgz`. When unpacked into the project directory (`cd your/path/to/phase_1a_single_site_almond && tar xf 00_cccmmf_phase_1a_input_artifacts.tgz`) it will place its files at the paths documented below.

### 1. Posterior files for PFT-specific model parameters

These were generated by PEcAn, but we treat them as prerequisites here because running calibration to set parameter distributions is a complex offline process. The posterior files used here were calibrated in Fer et al 2018[2] and are the Dietze lab's standard posterior for simulations of temperate deciduous woody plants:

* `pfts/temperate/post.distns.Rdata`, md5 = 8783b81a32665b0a1f3405e4711124f6
* `pfts/temperate/trait.mcmc.Rdata`, md5 = 8cd3f36a64d9005ed1aeba3f2fd537bd

To relocate these paths or use a different posterior file, edit `settings$pfts$pft$posterior.files`.


### 2. Site-specific climate driver files for SIPNET

Climate drivers are in a single flat folder that contains ten `*.clim` files, one per ERA5 ensemble member; PEcAn will sample from these to choose the met input for each SIPNET ensemble member.

If you have raw ERA5 data in hand, you can generate these files with `01_prep_get_ERA5_met.R` -- See there for details. We provide them as artifacts because at this writing the official ERA5 data API is unstable in both availability and returned file format and has been that way for at least three months, so we decided a tarball of clim files would be more reproducible than a download script.

Here we use `data/ERA5_losthills_dailyrain/*.clim`:
```
MD5 (ERA5.1.1999-01-01.2012-12-31.clim) = e61481d71dfa39533932e0c1bcdb35fb
MD5 (ERA5.10.1999-01-01.2012-12-31.clim) = 45e096d5ff23f59d5fedc653f6bef654
MD5 (ERA5.2.1999-01-01.2012-12-31.clim) = 484b84269f5fc41f8808ad4321cf6188
MD5 (ERA5.3.1999-01-01.2012-12-31.clim) = 1f1e3a53c98aff3f2f1fa0f3e234c5e5
MD5 (ERA5.4.1999-01-01.2012-12-31.clim) = fc90db406522a94d47b66a20e16c9f5e
MD5 (ERA5.5.1999-01-01.2012-12-31.clim) = 0b6ad1e96b1bd30d61800880fa0e37ef
MD5 (ERA5.6.1999-01-01.2012-12-31.clim) = 1844ac3be2d3b9fea17b471c77908df1
MD5 (ERA5.7.1999-01-01.2012-12-31.clim) = bee6b863d2e23d55211e9f5df4e70fa5
MD5 (ERA5.8.1999-01-01.2012-12-31.clim) = 0be2f00cad34562bd5b6823a445034f3
MD5 (ERA5.9.1999-01-01.2012-12-31.clim) = ac18e8d57a68e6aa5457cd7cf7e6892b
```

To relocate these files or use different ones, edit the input path in `02_prep_add_precip_to_clim_files.sh`, or if not altering precip then edit the paths in `settings$inputs$met$path`.


### 3. Site-specific initial condition files

Create as many as you need to capture the variability in known/assumed site conditions at the start of the run.
The number of IC files need not be the same as the ensemble size; each ensemble member samples with replacement to select initial conditions.
Generate these with `03_prep_ic_build.R`, which sets
  - Aboveground biomass from LandTrendr
    (You must first download raw LandTrendr tiles and specify the path to them)
  - Soil moisture from Copernicus 0.25 degree gridded multi-satellite data
    (You must first set up a CDS API key, then this script handles download)
  - 0-30 cm soil organic carbon stock from SoilGrids 250m data
    (this script handles download)
See `03_prep_ic_build.R` for details.

Here we store:
* Initial condition files in `IC_files/losthills/*.nc`, whose collective md5 hash (i.e. `md5 IC_files/losthills/*.nc | md5`) is da8efa69af2d5e22efcdc4541942ee64
* Source data for aboveground biomass in `data_raw/LandTrendr_AGB/`
```
MD5 (LandTrendr_AGB/aboveground_biomass_landtrendr.csv) = 60b264c272656af7149c00813f17f97c
MD5 (LandTrendr_AGB/conus_biomass_ARD_tile_h02v08.tif) = 41aeada58b5224ccf450fa22536edd67
MD5 (LandTrendr_AGB/conus_biomass_ARD_tile_h03v10.tif) = 716488ac4befc35be3b11973700da92a
MD5 (LandTrendr_AGB/conus_biomass_ARD_tile_h03v11.tif) = 5afceed07c8836a82e3e8f25e7f3e76b
```
* Source data for soil moisture in `data/IC_prep/soil_moisture/`
```
MD5 (soil_moisture/sm.csv) = ea064b8eb8be77a4a1669f52062bf48c
MD5 (soil_moisture/surface_soil_moisture.1999-01-01.nc) = 70fad74c167e1809fe6b35a0baa0b004
MD5 (soil_moisture/surface_soil_moisture.1999-01-02.nc) = 03052e99496f95e76e462385ff14e875
MD5 (soil_moisture/surface_soil_moisture.1999-01-03.nc) = ebf9eeb15fb01e0f3faafd937b1992bf
MD5 (soil_moisture/surface_soil_moisture.1999-01-04.nc) = c2337eaa91d96d3f55222e289326fe02
MD5 (soil_moisture/surface_soil_moisture.1999-01-05.nc) = 05dbc0a64eda1b255d39629d3d0ac052
MD5 (soil_moisture/surface_soil_moisture.1999-01-06.nc) = 5866d52333c9486ae2bed6431182bbf7
MD5 (soil_moisture/surface_soil_moisture.1999-01-07.nc) = afbc760887d752037ed0af1b5a32dab1
MD5 (soil_moisture/surface_soil_moisture.1999-01-08.nc) = ecd332b20d87d31a03a23d22cddb0844
MD5 (soil_moisture/surface_soil_moisture.1999-01-09.nc) = 4870a69bd7594e41d9015888dd50d116
MD5 (soil_moisture/surface_soil_moisture.1999-01-10.nc) = 2337043bee7e185a957cd8cb92062234
```
* compiled soil C stock data in `data/IC_prep/soilgrids_soilC_data.csv`, MD5 = cc03b81f5a636b9584ee1b03a7a9ed3e


### tar command

For the record, we packaged all of the above inputs using:

```
tar czf 00_cccmmf_phase_1a_input_artifacts.tgz \
  pfts/temperate/ \
  data/ERA5_losthills_dailyrain/ \
  IC_files/losthills/
```

## Run workflow

Choose the method that matches your installation: Directly installed or containerized.

Known limitations of this prototype:
  - We show a single-threaded run (`sbatch -n1 --cpus-per-task=1`); in future phases we will distribute model execution across the available cores.
  - Does not rerun cleanly. If an `output/` directory exists from a previous run, move it aside before invoking `04_run_models.R` to avoid cryptic errors about "duplicate 'row.names' are not allowed".


### Directly installed

```{sh}
module load r/4.4.0

# If running prep scripts directly, run them here.
# Wait for each step to complete before starting the next.
# (Skip these if you unpacked 00_cccmmf_phase_1a_input_artifacts.tgz during installation)
#   sbatch ... 01_prep_get_ERA5_met.R
#   sbatch ... 02_prep_add_precip_to_clim_files.sh
#   sbatch ... 03_prep_ic_build.R

sbatch -n1 --mem-per-cpu=1G --time=01:00:00 \
  --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%j.log" \
  ./04_run_model.R --settings=single_site_almond.xml

srun -n1 --mem-per-cpu=4G \
  --output=pecan_validation_"$(date +%Y%m%d%H%M%S)_%j.log" \
  Rscript -e 'rmarkdown::render("05_validation.Rmd")'

sbatch ./tools/compress_output.sh

# [copy ccmmf_output_<date>_<time>.tgz to your archive]
```

### Containerized

The apptainer workflow is _almost_ a matter of inserting `apptainer run model-sipnet-git_develop.sif` into each command shown above, with two complications discussed below.


```{sh}
# If running prep scripts directly, run them here.
# Wait for each step to complete before starting the next.
# (Skip these if you unpacked 00_cccmmf_phase_1a_input_artifacts.tgz during installation)
#   sbatch ... apptainer run model-sipnet-git_develop.sif 01_prep_get_ERA5_met.R
#   sbatch ... 02_prep_add_precip_to_clim_files.sh
#   sbatch ... apptainer run model-sipnet-git_develop.sif 03_prep_ic_build.R
```

Complication one: The `model-sipnet-git` container has its own copy of Sipnet stored at a different path than the one `single_site_almond.xml` is expecting. You can edit the XML directly, or do as shown here and create a `sipnet.git` symlink in the run directory, pointing to a path that (probably) doesn't exist on your host system but that does work when apptainer is active.
**Note:** This will overwrite any existing link created by `tools/install_sipnet.sh`, so beware if switching back and forth between native and container runs in the same directory.

```{sh}
APPTAINER_SIPNET_PATH=$(apptainer run model-sipnet-git_develop.sif which sipnet.git)
ln -sf "$APPTAINER_SIPNET_PATH" sipnet.git

sbatch -n1 --mem-per-cpu=1G --time=01:00:00 \
  --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%j.log" \
  apptainer run model-sipnet-git_develop.sif \
    ./04_run_model.R --settings=single_site_almond.xml
```

Complication two: When passing R commands as a string to the validation rendering call, we need some extra quote-escaping.

```{sh}
srun -n1 --mem-per-cpu=4G \
  --output=pecan_validation_"$(date +%Y%m%d%H%M%S)_%j.log" \
  apptainer run model-sipnet-git_develop.sif \
    Rscript -e 'rmarkdown::render(\"05_validation.Rmd\")'
```

```{sh}
sbatch ./tools/compress_output.sh

# [copy ccmmf_output_<date>_<time>.tgz to your archive]
```

It would be fine to run the shell script steps using apptainer as well, but it isn't necesary because they use only standard portable unix tools.


## Directory layout

The files for this project are arranged as follows. Note that some of these are created at runtime and will not be visible when looking at the project code on GitHub.

* `data/`: Clean, processed datasets used for model input and validation. Files in this directory can be recreated with the appropriate prep script.
* `data_raw/`: Datasets that were created by workflows external to this project, potentially including manual compilation. Files in this directory should be treated as artifacts that would be a lot of work to recreate.
* `IC_files/`: Initial conditions for the site(s) to be modeled, stored as netCDF files. Each file contains a single starting value for each variable, drawn from the distributions estimated in the `ic_build` script. Each model invocation (ensemble member) then begins from the initial conditions in one file.
* `output/`: Created by PEcAn at run time. Contains:
  - `ensemble.analysis.<id>.<variable>.<years>.pdf`: histograms and boxplots of the time-averaged ensemble values of each variable.
  - `ensemble.output.<id>.<variable>.<years>.Rdata`: The extracted datapoints used to make the matching PDFs.
  - `ensemble.ts.<id>.<variable>.<years>.pdf`: Time series plots showing mean and 95% CI of each variable throughout the run.
  - `ensemble.ts.<id>.<variable>.<years>.Rdata`: The extracted datapoints used to make the timeseries PDFs.
  - `out/`: Model outputs, with subdirectories for each ensemble member containing:
    * `<year>.nc`: One PEcAn-standard netCDF per year containing all requested output variables at the same timestep as the input weather data
    * `<year>.nc.var`: One plain text file per year containing a list of the variables included in `<year>.nc`. In this case all years have the same variables, but PEcAn is capable of simulations where variables differ from year to year.
    * `logfile.txt`: Console output from the model run. Note that SIPNET itself is not very chatty, so for successful runs this usually shows only the PEcAn output from the process of converting the output to netCDF.
    * `README.txt`: Reports some metadata about the model run including site, input files, run dates, etc.
    * `sipnet.out`: Raw SIPNET output, with all years and variables in one file
  - `pecan.CONFIGS.xml`: Settings for the run, as recorded just after writing config files and before starting the SIPNET runs (In this workflow only one XML file is written; in other PEcAn applications the settings might be recorded at other stages of the run as well, giving e.g. `pecan.CHECKED.xml`, `pecan.TRAIT.xml`, `pecan.METPROCESS.xml`, and so on).
  - `run/`: Working directories for the execution of each model, with subdirectories for each ensemble member containing:
    * `job.sh`: A bash script that controls the execution of SIPNET and relocates outputs to the `out/` directory
    * `README.txt`: Metadata about the model run; identical to the copy in `out/`
    * `sipnet.clim`: a *link to* the weather data used for this model invocation.
    * `sipnet.in`, `sipnet.param-spatial`: Configuration files used by SIPNET. These are identical for each run, copied into every run directory because SIPNET expects to find them there.
    * `sipnet.param`: Values for SIPNET model parameters, set by starting from SIPNET's default parameter set and updating parameters set in the chosen PFT by taking draws from the PFT's parameter distributions.
  - `samples.Rdata`: The draws from requested parameter distributions that were used to set the SIPNET parameterization of each model in the run.
  - `STATUS`: A plain text file containing start and end timestamps and statuses for each phase of the workflow.
  - If a sensitivity analysis is requested (by uncommenting the `<sensitivity.analysis>` block in `single_site_almond.xml`), it will add these additional components:
    * `pft/`: Parameter sensitivity and variance decomposition plots from the sensitivity analysis, placed here because PEcAn's sensitivity analysis can be requested for many PFTs at once and is run separately for each one.
    * `sensitivity.output.<id>.<variable>.<years>.Rdata`: Results from the sensitivity analysis, processed and ready for visualization.
    * `sensitivity.results.<id>.<variable>.<years>.Rdata`: Results from the sensitivity simulations, extracted and set up for analysis.
    * `sensitivity.samples.<id>.Rdata`: The parameter values selected for the one-at-a-time sensitivity analysis, with each variable taken at its PFT median plus or minus the standard deviations specified in the settings XML. Note that these same values are also part of `samples.Rdata`.
* `tools`: Scripts for occasional use that may or may not be part of every workflow run. At this writing it contains installation scripts for setting up SIPNET and PEcAn on an HPC cluster and for archiving run output; others may be added later.


## References

[1] Nichols, Patrick K., Sharon Dabach, Majdi Abu-Najm, Patrick Brown, Rebekah Camarillo, David Smart, and Kerri L. Steenwerth. 2024. “Alternative Fertilization Practices Lead to Improvements in Yield-Scaled Global Warming Potential in Almond Orchards.” Agriculture Ecosystems and Environment 362 (March):108857. https://doi.org/10.1016/j.agee.2023.108857.

[2] Fer I, R Kelly, P Moorcroft, AD Richardson, E Cowdery, MC Dietze. 2018. Linking big models to big data: efficient ecosystem model calibration through Bayesian model emulation. Biogeosciences 15, 5801–5830, 2018 https://doi.org/10.5194/bg-15-5801-2018
