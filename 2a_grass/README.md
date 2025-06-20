# Statewide crop modeling with two PFTs: MAGiC phase 2a

This simulation expands on phase 1b by introducing a non-woody PFT,
using generalized grassland parameters developed by Dookohaki et al (2022)[1].
As run here it is treated as a perennial to simulate hay and pasture land;
to simulate row crops we expect to use the same parameters in combination with
Sipnet's newly added planting and harvest event capabilities.

Here we generate model outputs for 198 locations:
The 98 orchards used in phase 1b, plus 100 nonwoody sites. These are then scaled and propagated to statewide carbon estimates using the MAGiC downscaling workflow (reported separately).

Further improvements compared to phase 1b include:

* Initial conditions for aboveground biomass are now averaged from all
	LandTrendr grid cells within the target DWR field polygon
	(previously used a fixed 90m point buffer)
* Initial condition calculations now read specific leaf area and leaf carbon
	concentration from the correct PFT for the site
	(previously hard-coded to values for woody plants)
* Runtime configuration parameters can now be set via command-line arguments
	(previously hard-coded at the top of each script file)
* Initial conditions script now checks for existing data one site at a time
	and only fetches data from sites not already present
	(previously had to fetch all sites for a parameter at once).
	This gives a substantial time savings when adding a few new sites to the
	existing set.



All instructions below assume you are working on a Linux cluster that uses Slurm as its scheduler; adjust the batch parameters as needed for your system. Many of the scripts are also configurable by editing designated lines at the top of the script; the explanations in these sections are worth reading and understanding even if you find the default configuration to be suitable.


## How to run the workflow

### Copy prebuilt input artifacts

Instructions to come -- at this writing we're working on the transition from Google Drive to a more accessible file server on our own infrastructure.


### Create IC files

```{sh}
module load r
sbatch -n1 --cpus-per-task=4 01_ERA5_nc_to_clim.R --n_cores=4
srun ./02_ic_build.R
srun ./03_xml_build.R
```


### Model execution

Now run Sipnet on the prepared settings + IC files.

(Note: The 10 hour `--time` limit shown here is definitely excessive; my test runs took about an hour of wall time).

```{sh}
module load r
sbatch --mem-per-cpu=1G --time=10:00:00 \
  --output=ccmmf_phase_1b_"$(date +%Y%m%d%H%M%S)_%j.log" \
  ./04_run_model.R -s settings.xml
```

## Sensitivity analysis

In addition to the statewide runs, we present in notebook
`parameter_sensitivity.Rmd` a one-at-a-time sensitivity analysis of the effects
of all parameters specified for each PFT (28 parameters for woody crops,
22 for nonwoody) on modeled aboveground biomass, NPP, evapotranspiration,
soil moisture, and soil carbon across the whole 2016-2023 simulation period. The analysis was repeated at each of 5 locations for each PFT.

The major takeaway from the sensitivity analysis is that leaf growth and specific leaf area account for a large fraction of the observed model response across sites, PFTs, and response variables, while photosynthetic rate parameters such as half-saturation PAR, Amax, and `Vm_low_temp` explain much of the productivity and water use response in woody plants but are less important for the nonwoody PFT. Parameters related to the temperature sensitivity of photosythesis (`Vm_low_temp`, `PsnTOpt`) were considerably more elastic (i.e. larger proportional change in model output per unit change in parameter value) than other parameters this was variable from site to site while most other responses were broadly similar across sites.

Note that this analysis considers parameter sensitivity only and not uncertainty around initial conditions, management, or environmental drivers.


## References

[1] Dokoohaki H, BD Morrison, A Raiho, SP Serbin, K Zarada, L Dramko, MC Dietze. 2022. Development of an open-source regional data assimilation system in PEcAn v. 1.7.2: application to carbon cycle reanalysis across the contiguous US using SIPNET. Geoscientific Model Development 15, 3233–3252. https://doi.org/10.5194/gmd-15-3233-2022