#!/bin/bash

# compress all input files for CA woody simulation (ccmmf phase 1b)
# to be copied to other machines

# TODO:
#  - may eventually build site_info.csv from design points on the fly
#  - Skip copying IC? ic_build.R should run anywhere from scratch, just slow.
#  - ERA5 will be replaced by caladapt

tar czf cccmmf_phase_1b_input_artifacts.tgz \
  pfts/temperate/ \
  data_raw/ERA5_nc \
  data/IC_prep/*.csv \
  data/sipnet.event \
  site_info.csv
