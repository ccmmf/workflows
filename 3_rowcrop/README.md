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

### 0. Copy prebuilt artifacts

TODO. Should include:
	- PFT definitions including new row crop PFT
	- ERA5 data as nc (clim conversion runs locally)
		- ca_half_degree_grid.csv too?
	- initial conditions
		- Decide: deliver full files, site-level mean/sd, or other?
	- site_info.csv
	- validation info. Key constraint: datapoints are private,
		probably need a "drop into this directory with this format"
		step.

### 1. Convert climate driver files

TODO show how to pass n_cores from host_args
(NSLOTS? SLURM_CPUS_PER_TASK?)

```{sh}
[host_args] ./01_ERA5_nc_to_clim.R \
	--site-era5-path="data_raw/ERA5_CA_nc" \
	--site_sipnet_met_path="data/ERA5_CA_SIPNET" \
	--site-info-file="data/ca_half_degree_grid.csv" \
	--start_date="2016-01-01" \
	--end_date="2025-12-31" \
	--n_cores=7
```

### 2. Generate initial site conditions

```{sh}
[host_args] ./02_ic_build.R
```

### 3. generate settings file

```{sh}
[host_args] ./03_xml_build.R
```


## References

[1] Fer I, R Kelly, P Moorcroft, AD Richardson, E Cowdery, MC Dietze. 2018. Linking big models to big data: efficient ecosystem model calibration through Bayesian model emulation. Biogeosciences 15, 5801–5830, 2018 https://doi.org/10.5194/bg-15-5801-2018

[2] Dokoohaki H, BD Morrison, A Raiho, SP Serbin, K Zarada, L Dramko, MC Dietze. 2022. Development of an open-source regional data assimilation system in PEcAn v. 1.7.2: application to carbon cycle reanalysis across the contiguous US using SIPNET. Geoscientific Model Development 15, 3233–3252. https://doi.org/10.5194/gmd-15-3233-2022
