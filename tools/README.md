# Tools for setting up MAGiC workflows

The scripts in this directory are intended to do a defined task and be run
whenever that task arises.
For most tasks "whenever the task arises" will be <= 1x per workflow run
(e.g. scripts used to create the prebuilt input files);
We have found that scripts called many times each workflow are usually either
specific to that workflow(in which case it lives in that workflow's directory)
or generic enough to not be specific to MAGiC (in which case we add it to PEcAn).

See each script file for a more detailed description, but briefly they are:

* `compress_output.sh`: Pack up workflow output into a tarball for delivery/archiving.
* `create_input_tarball.sh`: Creates `cccmmf_phase_1b_input_artifacts.tgz`. TODO: update to be phase-agnostic
* `ERA5_met_extract.R`: Converts raw ERA5 to PEcAn standard met files
* `install_sipnet.sh`, `install_pecan.sh`: What the names say
* `make_site_info_csv.R`: Regenerates `site_info.csv` from design points
* `run_extract_ERA5_met.R`: Wrapper for `extract_ERA5_met.R` using BU cluster's scheduler settings
* `read_mapped_planting_year.R`: Creates `data/site_planting_years.csv`
* `write_sipnet_event_file.R`: Creates `data/events.in` with a fixed 1500-mm-per-year irrigation schedule
