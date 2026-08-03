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


## Running the workflow

This example is driven by `./magic-ensemble` from the repo root. Copy
`example_user_config.yaml`, edit `run_dir` and any other overrides you need,
then run:

```sh
./magic-ensemble get-demo-data     --verbose --config <your config>
./magic-ensemble prepare-example-3 --verbose --config <your config>
./magic-ensemble run-ensembles     --verbose --config <your config>
```

* `get-demo-data` fetches all confirmed S3 sources into `run_dir`: the
  example-3 input tarball (site_info.csv, PFT posteriors, IC-prep caches), the
  CA-specific ERA5 archive, `parcels-consolidated.gpkg`/`crops_all_years.parq`,
  and the management event sources (harvest/irrigation/phenology/planting/tillage).
* `prepare-example-3` runs, in order: climate-driver conversion
  (`01_ERA5_nc_to_clim.R`), the canonical IC build (`workflow/02_ic_build.R`),
  management-event generation (`02a_build_events.R`), and settings assembly
  (`03_xml_build.R`), producing `settings.xml` in `run_dir`.
* `run-ensembles` dispatches ensemble members (Slurm or local, per
  `pecan_dispatch` in your config).

`site_info.csv` is not checked into this repo -- it ships pre-built inside the
get-demo-data tarball. It was generated once via
`tools/build_site_info.R --location_file=<design points> --out_file=site_info.csv`
against `parcels-consolidated.gpkg`/`crops_all_years.parq`; only rerun that
script if you need to change the set of design points.

### Validation data

To set up validation runs, you need access to the cropland soil carbon data
files `Harmonized_SiteMngmt_Croplands.csv` and `Harmonized_Data_Croplands.csv`.

These were shared for this project by CARB and CDFA, who in turn obtained them
from stakeholders (primarily Healthy Soils Program grant recipients) who
consented to use of their data for internal research purposes but explicitly
did not consent to public distribution of the data.
Contact chelsea.carey@arb.ca.gov for more information about the dataset.

Once obtained, place them in `data_raw/private/HSP` (inside `run_dir`) and run
```{sh}
../../tools/build_validation_siteinfo.R
```
to create `validation_site_info.csv`. Validation runs are not yet wired into
`magic-ensemble` -- rerun the relevant `prepare-example-3` steps by hand with
`--site_file=validation_site_info.csv` and a separate `--output_file`/
`--output_dir`, following the same pattern `03_xml_build.R --help` documents.

### Validate

```{sh}
[host_args] ./validate.R \
	--model_dir=val_out \
	--output_dir=validation_results_$(date '+%s')
```


## References

[1] Fer I, R Kelly, P Moorcroft, AD Richardson, E Cowdery, MC Dietze. 2018. Linking big models to big data: efficient ecosystem model calibration through Bayesian model emulation. Biogeosciences 15, 5801–5830, 2018 https://doi.org/10.5194/bg-15-5801-2018

[2] Dokoohaki H, BD Morrison, A Raiho, SP Serbin, K Zarada, L Dramko, MC Dietze. 2022. Development of an open-source regional data assimilation system in PEcAn v. 1.7.2: application to carbon cycle reanalysis across the contiguous US using SIPNET. Geoscientific Model Development 15, 3233–3252. https://doi.org/10.5194/gmd-15-3233-2022
