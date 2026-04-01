# Simulating row crop management: MAGiC phase 3

With full support for agronomic events now implemented in the Sipnet model,
this set of simulations demonstrates incorporating such events into the PEcAn
framework and evaluating their effect on predicted carbon dynamics in a
cropping landscape that can now be resolved into three plant functional types:

* Woody perennials such as orchards or vineyards (Fer et al 2015)[1],
* Nonwoody perennials such as hay, haylage, grazing land, etc
	(Dookohaki et al 2022)[2],
* Annually planted, actively managed row crops. These are initially represented
	as a single "nonwoody annual" plant functional type with parameters derived
	from the nonwoody perennial PFT by turning off internal phenology so that
	greenup and browndown are controlled by the externally prescribed planting
	and harvest dates.

Representing all row crops as one single PFT is a major simplification, so one
key goal of this phase is to prepare the simulation framework for a detailed
uncertainty analysis, which can then be used to inform decisions about further
dividing crop types as data become available to calibrate them.

Statewide runs continue to use the 198 sites evaluated in phase 2.
We also introduce focused validation runs using the subset of sites where
direct observations of soil carbon and/or biomass are available during the
simulation period.


## Caveats

TODO UPDATE when no longer true

This simulation is under active development and all the notes below are subject
to change as we update the code.
For now, instructions assume a local run on MacOS and will be updated for a
Linux + Slurm + Apptainer HPC environment as we finish testing and deployment.

Aspirationally, any command prefixed with `[host_args]` is one that ought to
work on HPC by "just" adding a system-specific prefix, e.g.
`./01_ERA4_nc_to_clim.R --start_date=2016-01-01` on my machine becomes
`sbatch -n16 --mem=12G --mail-type=ALL --uid=jdoe \
	./01_ERA4_nc_to_clim.R --start_date=2016-01-01` on yours.


## Running the workflow

### 0. Copy prebuilt artifacts and set up validation data

TODO. Should include:
	- PFT definitions including new row crop PFT
	- ERA5 data as nc (clim conversion runs locally)
	- ca_half_degree_grid.csv too
	- data/events/
	- data_raw/management, copied from s3://carb/management/
	- DWR map?
	- initial conditions
		- Decide: deliver full files, site-level mean/sd, or other?
	- site_info.csv
	- validation info. Key constraint: datapoints are private,
		probably need a "drop into this directory with this format"
		step. do NOT include validation_site_info.csv

#### Validation data

To set up validation runs, you need access to the cropland soil carbon data
files `Harmonized_SiteMngmt_Croplands.csv` and `Harmonized_Data_Croplands.csv`.

These were shared for this project by CARB and CDFA, who in turn obtained them
from stakeholders (primarily Healthy Soils Program grant recipients) who
consented to use of their data for internal research purposes but explicitly
did not consent to public distribution of the data.
Contact chelsea.carey@arb.ca.gov for more information about the dataset.

Once obtained, place them in `data_raw/private/HSP` and run
```{sh}
../tools/build_validation_siteinfo.R
```
to create `validation_site_info.csv`.


### 1. Convert climate driver files

TODO 1: current development version of PEcAn.sipnet still writes 13-col
	clim files with constants for grid index and soil water. Document which version writes correctly.

TODO 2: show how to pass n_cores from host_args
(NSLOTS? SLURM_CPUS_PER_TASK?)

```{sh}
[host_args] ./01_ERA5_nc_to_clim.R \
	--site_era5_path=data_raw/ERA5_CA_nc \
	--site_sipnet_met_path=data/ERA5_CA_SIPNET \
	--site_info_file=data_raw/ca_half_degree_grid.csv \
	--start_date=2016-01-01 \
	--end_date=2025-12-31 \
	--n_cores=7
```

### 2. Generate initial site conditions

We'll run this twice, once for validation sites and once for statewide anchors.
It would also be fine to put both together in the same input and run it once.

NOTE: ECMWF soil moisture data calls were failing when I tried to run this for anchor sites on 2025-12-08,
so I symlinked `data/IC_prep_val/soil_moisture/` to `data/IC_prep/soil_moisture/`. On a day the server is up, this _should_ not be needed... but also isn't a problem, since that subdirectory contains global 0.25 degree/25 km soil moisture data for the first 10 days of 2016 and can be expected to be identical from one downloading to the next. The fact that we cache that output here is a quirk of how `PEcAn.data.land::extract_SM_CDS` is implemented, not a designed part of the IC workflow.


```{sh}
[host_args] ./02_ic_build.R \
	--site_info_path=validation_site_info.csv \
	--pft_dir=data_raw/pfts \
	--data_dir=data/IC_prep_val \
	--ic_outdir=data/IC_files
[host_args] ./02_ic_build.R \
	--site_info_path=site_info.csv \
	--pft_dir=data_raw/pfts \
	--data_dir=data/IC_prep \
	--ic_outdir=data/IC_files
```

### 3. generate settings file

```{sh}
[host_args] ./03_xml_build.R \
	--ic_dir=data/IC_files \
	--site_file=validation_site_info.csv \
	--output_file=validation_settings.xml \
	--output_dir_name=val_out
```

### 4. Set up model run directories

TODO: Yes, it's unintuitive that we can't rename the output dir at this
stage instead of in xml_build.

```{sh}
[host_args] ./04_set_up_runs.R --settings=validation_settings.xml
```

### 5. Run model

```{sh}
export NCPUS=8
ln -s [your/path/to]/sipnet/sipnet sipnet.git
[host_args] ./05_run_model.R --settings=val_out/pecan.CONFIGS.xml


### 6. Validate

```{sh}
[host_args] ./validate.R \
	--model_dir=val_out \
	--output_dir=validation_results_$(date '+%s')
```


## References

[1] Fer I, R Kelly, P Moorcroft, AD Richardson, E Cowdery, MC Dietze. 2018. Linking big models to big data: efficient ecosystem model calibration through Bayesian model emulation. Biogeosciences 15, 5801–5830, 2018 https://doi.org/10.5194/bg-15-5801-2018

[2] Dokoohaki H, BD Morrison, A Raiho, SP Serbin, K Zarada, L Dramko, MC Dietze. 2022. Development of an open-source regional data assimilation system in PEcAn v. 1.7.2: application to carbon cycle reanalysis across the contiguous US using SIPNET. Geoscientific Model Development 15, 3233–3252. https://doi.org/10.5194/gmd-15-3233-2022
