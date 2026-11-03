# Input files and instructions for MAGiC projections

2026-09-25

Chris Black
chris@poolsandfluxes.com


This directory contains the configuration files needed to run the MAGiC
inventory and projection pipelines on an HPC cluster. The process is shown here
using NCSA's Delta cluster via an NSF ACCESS-CI allocation, but should work the
same on any Slurm-based cluster after updating the config files to use
(1) your system's paths, and (2) Slurm arguments (--account, --partition, etc)
that are appropriate for your system.


## Prerequisites

See https://github.com/ccmmf/magic-training/blob/main/CARB-PEcAn-setup.md

* Conda environment `pecan-all-1.18`
* AWS tools configured with `AWS_PROFILE=magic` and auth keys working

```sh
conda activate pecan-all-1.18
export AWS_PROFILE=magic
export PROJECT_ROOT=/work/hdd/bgat/cblack3/magic/
export CONFIGS=/work/hdd/bgat/cblack3/magic/magic-ensemble-configs-20260925/delta_queue
cd "$PROJECT_ROOT"
```

## Download input data

* s3:/carb/management/: Management data from the MAGiC monitoring system
	- (I'm syncing each subfolder separately to avoid pulling some other large 
	folders that live alongside them; one 
	`aws s3 sync s3://carb/management/ data_raw/management/` will work too but 
	use more bandwidth and disk space)
* s3://carb/met/ERA5_CA_nc_2016_2024.tgz: Hourly ERA5 0.5-degree gridded met
	data for all of CA, 2016-2023.
* s3://carb/met/wrf_met_CA_45km_2024_2051.tgz: Hourly WRF 45-km gridded met data
	for all of CA, 2024-2051.
* s3://carb/IC/: raw files used for initial condition setup
* s3://carb/inventory/magic-ensemble-configs-20260925: The directory this
		README lives in, containing configuration files (`*.yaml`) for the
		magic-ensemble CLI along with `site_info.csv` declaring the site list for
		these simulations.
* https://github.com/ccmmf/workflows: The magic-ensemble CLI plus workflow
	scripts that it calls at each step

```sh
aws s3 sync s3://carb/management/crops/ data_raw/management/crops/
aws s3 sync s3://carb/management/harvest/ data_raw/management/harvest/
aws s3 sync s3://carb/management/planting/ data_raw/management/planting/
aws s3 sync s3://carb/management/phenology/ data_raw/management/phenology/
aws s3 sync s3://carb/management/tillage/ data_raw/management/tillage/
aws s3 sync s3://carb/management/irrigation/ data_raw/management/irrigation/
aws s3 sync s3://carb/management/fertilization/ \
  data_raw/management/fertilization/
aws s3 sync s3://carb/management/ncc/ data_raw/management/ncc/
aws s3 sync s3://carb/met/ data_raw/met/ # NB contains 13 GB raw wrf tarball
aws s3 sync s3://carb/IC/ data_raw/IC/
aws s3 sync s3://carb/pfts/magic_v1.2 data_raw/pfts/magic_v1.2
aws s3 cp s3://carb/inventory/magic-ensemble-configs-20260925.tgz .
tar xf magic-ensemble-configs-20260925.tgz
cd data_raw/met/
tar xf ERA5_CA_nc_2016_2024.tgz
tar xf wrf_met_CA_45km_2024_2051.tgz # NB expands to 17 GB
cd -
git clone https://github.com/ccmmf/workflows
```

## The temporary hacks you knew were coming

Here we manually implement a few updates that will be rolled into the steps
above soon: Fetch updates that are not yet merged into the Conda environment,
and move aside some QC files in the projection data

### Update code

Pull the changes merged into PEcAn since the release of pecan-all-1.18:

```sh
Rscript -e '
  options(repos = c(getOption("repos"), pecan= "pecanproject.r-universe.dev"))
  pecan_pkgs <- installed.packages() |>
    _[,"Package"] |>
    grep(pattern = "PEcAn", value = TRUE)
  install.packages(pecan_pkgs)
'
```

Pull changes for projection support in magic-ensemble:

```sh
cd workflows
git fetch
git checkout projections
cd "$PROJECT_ROOT"
```

## Run inventory

### Preparation steps

```sh
cd workflows
./magic-ensemble --verbose \
  --config ${CONFIGS}/inventory.yaml \
  prepare-example-3
```

This will run five scripted steps:
1. `stage-inputs`: Copy or symlink external files into the output directory,
	installing Sipnet if needed
2. `convert-clim`: Convert ERA5 weather ensemble data to Sipnet clim format
3. `build-ic`: Build an ensemble of initial condition files for each site
4. `build-events`: Convert management data from the MAGiC monitoring system into
	Sipnet event files
5. 	build-xml`: Construct a PEcAn settings file that will orchestrate ensemble
	simulations of all sites

When finished, verify that output directory `magic-inventory-20260925`
was created and contains:

* data/ERA5_SIPNET/: 117 subdirs with 10 `*.clim` files each
* data/events: 20 `events_ens_*,json`, 20 `ens_*` dirs each with 1000 
  `cycles-*.csv` and 1000 `events-*.in`
* `IC_files`: 1000 dirs each with 50 `IC_site_*.nc`
* `output/` will exist but be empty at this point
* `prepare-example-3-*.log` will contain console output from running preparation
  steps
* `settings.xml` exists and has
  - 8 blocks in its `<pfts>` section each pointing to a path in `data_raw/pfts/` 
  - `<model>` has `<binary>[path/to]/magic-inventory-20260925/sipnet.git</binary>`
  - `<run>` contains 1000 `<site.[id]>` blocks each with and `<inputs>` containing
	10 `<met><path>`, 50 `<poolinitcond?<path>`, 20 `<events><path>`,
	20 `<crop_changes><path>`
  - `<host><qsub>` contains a Slurm submission command with arguments appropriate
	for your system
  - `<host><rundir> and <host><outdir>` contain the same paths as `<rundir>` and
	`<outdir>`
* `sipnet.git` is a symlink to a working copy of Sipnet.
  If you cd into this directory and run `./sipnet.git -v`, you should see
  'SIPNET version 2.2.0 (v2.2.0)'
* site_info.csv should be identical to the copy in the input directory
* template.xml is modified from the version in the input directory, with the
  exact changes depending on details of your `workflow_parallelism_mode` and
  `pecan_parallelism_mode` config. Looking here is most useful for debugging any
  issues in the generated `settings.xml`.

### Run model

```sh
./magic-ensemble --verbose \
  --config ${CONFIGS}/inventory.yaml \
  run-ensembles
```

This will:
1. Create the full set of PEcAn runtime files:
	- a separate run directory and output directory for each model invocation.
		If an invocation will involve crop changes, the run directory contains
		subdirectories for each run segment that are each structured like an
		entire tiny PEcAn run.
	- `input_design.csv` and `samples.Rdata` preserve the parameter selection
		process for each model ensemble member
	- pecan.CONFIG.xml preserves modifications PEcAn made to `settings.xml`
		during setup
	- STATUS records timestamps for each setup and run step
	- runs_manfest.csv records the full set of models to be invoked
2. Run Sipnet at each site and collects each site's output to yearly netcdf
	files, optionally deleting run directories as each run finishes.
	Each run is submitted as a separate Slurm job and all can be run in parallel.

Future planned enhancements include postflight QC checks and automatic 
	packaging of outputs for archiving/passing to the downscaling process.

When finished, verify that:
* magic-inventory-20260925/output/ has been populated
* `run-ensembles-*.log` reports `PEcAn Workflow Complete` on its second-to-last
	line and no earlier lines include `ERROR` or `SEVERE`.
	If any `WARNING`s appear, read and understand them.
* All lines of `output/STATUS` end with "DONE"
* `output/out` has 20000(!) outfolders each with
	- 8 `YYYY.nc` for 2016-2023,
	- logfile.txt
	- README.txt
	- restart.out
	- for segmented runs, `segments.csv`
* If any `logfile.txt` contains "ERROR IN MODEL RUN", read and understand the log
	messages to determine if the output can be trusted
* Future revisions will add advice on understanding Sipnet "[WARNING]" messages
	in the logfile.

	Expect the raw output to take up about 110 GB before compression and contain
	approximately 250k files.

## Run projections

### Prepare run directories

First copy the end-of-inventory model state into a directory for archiving.
If desired we could skip this step and edit each projection's config to set 
`external_paths.link.in_place.prev_inventory_dir` to
`"[path/to/]magic-inventory-20260925"`, but that would mean we have to leave the
full inventory uncompressed while the projections run.
Saving restarts separately lets us clear more space in the run
directory before running the large projections.

```sh
./tools/collect_inventory_restarts_and_samples.R \
	--rundir "${PROJECT_ROOT}/magic-inventory-20260925" \
	--out "${PROJECT_ROOT}/magic-inventory-end-restarts-20260925"
```

Now set up the new run directories.

```sh
./magic-ensemble --verbose --config ${CONFIGS}/BAU.yaml prepare-projections
./magic-ensemble --verbose --config ${CONFIGS}/NBS.yaml prepare-projections
./magic-ensemble --verbose --config ${CONFIGS}/SSP585.yaml prepare-projections
```


This works much like the inventory preparation step. It runs four of the five
steps of the `prepare` command used for the inventory, skipping `build-ic`
(we will use the final state of the inventory runs as the initial condition for
the projections) using WRF 8-model ensemble weather projections instead of
ERA5 10-member reanalysis data, and using management projected by the MAGiC
scenario system instead of reported by the MAGiC monitoring system.

Verify that both `magic-projected-BAU-20260925` and `magic-projected-NBS-202609235
are created and populated as listed for the inventory.

### Run projections

Caution: Each projection output will be much larger than the inventory.
With today's configuration they're larger by a factor of 8 or so, because we run
the model for 2.75 times as long (22 vs 8 yr) at 3x as many timepoints per day
(ERA5 historical data are three-hourly while the WRF projections are hourly).

Expect each raw projection to weigh ~900 GB and contain ~550k files. 

```sh
./magic-ensemble --verbose --config ${CONFIGS}/BAU.yaml run-projections
./magic-ensemble --verbose --config ${CONFIGS}/NBS.yaml run-projections
./magic-ensemble --verbose --config ${CONFIGS}/SSP585.yaml run-projections
```



