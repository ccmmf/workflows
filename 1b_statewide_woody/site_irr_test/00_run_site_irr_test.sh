#!/bin/bash

set -e

# set up inputs (already prepared for 1b workflow)
ln -sf $(realpath ../IC_files/) IC_files
ln -sf $(realpath ../pfts/) pfts
ln -sf $(realpath ../data/ERA5_SIPNET/) data/ERA5_SIPNET
ln -sf $(realpath ../data/sipnet.event ) data/sipnet.event
ln -sf $(realpath ../sipnet.git) sipnet.git
# not needed to run PEcAn, but used by the analysis notebook
ln -sf $(realpath ../data_raw/) data_raw

# Remove "prerun" line from model run settings.
# It copies in a fixed Sipnet events file at run time,
# bu instead we'll copy site-specific ones during setup.
sed -e '/<prerun>/d' ../template.xml > template.xml

# Extract site ids from names of available event files,
# then filter site_info.csv to just the rows matching them.
# (`grep -f -` treats stdin as a list of patterns to match)
ls data/irrigation_event_files \
	| sed -E 's/^.*eventfile_(.*).txt/\1/' \
	| grep -e '^"id","lat"' -f - ../site_info.csv \
	> site_info.csv

# construct settings.xml from template.xml and site_info.csv
../03_xml_build.R

# run once with fixed and once with by-site irrigation
# (if --event_dir not passed, uses `data/sipnet.event`)
./00a_run_model_siteirr.R --settings settings.xml && \
	mv output output_static_irri
./00a_run_model_siteirr.R --settings settings.xml \
	--event_dir data/irrigation_event_files && \
	mv output output_site_irri

# Now you can examine results by compiling the notebook:
# Rscript -e 'rmarkdown::render("compare_site_vs_static_irrigation_20250519.Rmd")'
