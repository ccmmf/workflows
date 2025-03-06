#!/usr/bin/env Rscript

## --------- edit for your system and site ----------------------------

# Path to your existing ERA5 data
#
# These should be whole-year ensemble netcdfs as downloaded from ECWMF,
# with dimensions (latitude, longitude, number [aka ensemble member], time).
# Files must be named '<raw_era5_path>/ERA5_<year>.nc'
#
# In concept you can download these using
# `PEcAn.data.atmosphere::download.ERA5.old()`, but in practice the ECMWF API
# has changed and we are waiting for it to stabilize again before we devote
# time to update the code.
# Meanwhile, consider manually downloading locations/years of interest via web:
# https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels
raw_era5_path <- "/projectnb/dietzelab/dongchen/anchorSites/ERA5"


# Path to save intermediate format:
# Single site, single-year netcdfs, in subdirectories per ensemble member.
# Files named '<site_era5_path>/ERA5_<siteid>_<ensid>/ERA5.<ensid>.<year>.nc'
site_era5_path <- "/projectnb/dietzelab/chrisb/ERA5_nc"

# Output path:
# single-site, multi-year Sipnet clim files, one per ensemble member.
# Files named <site_sipnet_met_path>/<siteid>/ERA5.<ensid>.<start>.<end>.clim
site_sipnet_met_path <- "/projectnb/dietzelab/chrisb/ERA5_SIPNET"

# location and time to extract
site_info <- read.csv("site_info.csv")
site_info$start_date <- "2016-01-01"
site_info$end_date <- "2024-12-31"


# Usage notes:
# I'm hoping this is a one-off, so I ran it on the BU cluster
# (because that's where the raw files are) without trying to
# generalize to Slurm.
#
# 0. setup:
# The files I want are scattered across several branches today --
# I sure hope this branch-juggling is one-time even if we keep using ERA5 data.
#   cd /projectnb/dietzelab/<myname>/ccmmf
#   git clone https://github.com/ccmmf/workflows && cd workflows
#   git checkout 1b && cp data/design_points.csv design_points.csv
#   git checkout era5-for-1b && cd phase_1b_ca_woody
#   mv ../design_points.csv data/design_points.csv
#
# 1. initial interactive run:
#   qrsh
#   cd /projectnb/dietzelab/chrisb/ccmmf/workflows/phase_1b_ca_woody/
#   module load R
#   Rscript tools/make_site_info_csv.R
#   time Rscript tools/prep_getERA5_met.R
# I should have called `screen` first to protect against connection timeouts.
# It ran for about 4 hours, apparently extracting about one site per hour,
# then terminated when my session dropped.
#
# 2. Batch job
# I modified the script below to run in parallel if there are cores available,
# then put module commands and SGE directives into a quick bash script:
# qsub tools/run_getERA5.sh


future::plan("multisession", workers = as.numeric(Sys.getenv("NSLOTS")) - 1)


# ----------- end system-specific ---------------------------------


options(
  repos = c(
    getOption("repos"), # to keep your existing CRAN mirror
    PEcAn = "pecanproject.r-universe.dev", # for PEcAn packages
    ropensci = "ropensci.r-universe.dev" # for deps `traits` and `taxize`
  )
)

if (!requireNamespace("PEcAn.data.atmosphere", quietly = TRUE)) {
  print("installing PEcAn.data.atmosphere")
  install.packages("PEcAn.data.atmosphere")
}

if (!requireNamespace("PEcAn.SIPNET", quietly = TRUE)) {
  print("Installing PEcAn.SIPNET")
  install.packages("PEcAn.SIPNET")
}


furrr::future_pwalk(
  site_info,
  function(id, lat, lon, start_date, end_date, ...) {
    PEcAn.data.atmosphere::extract.nc.ERA5(
      slat = lat,
      slon = lon,
      in.path = raw_era5_path,
      start_date = start_date,
      end_date = end_date,
      outfolder = site_era5_path,
      in.prefix = "ERA5_",
      newsite = id
    )
  }
)



file_info <- site_info |>
  dplyr::rename(site_id = id) |>
  dplyr::cross_join(data.frame(ens_id = 1:10))

if (!dir.exists(site_sipnet_met_path)) {
  dir.create(site_sipnet_met_path, recursive = TRUE)
}
furrr::future_pwalk(
  file_info,
  function(site_id, start_date, end_date, ens_id, ...) {
    PEcAn.SIPNET::met2model.SIPNET(
      in.path = file.path(
        site_era5_path,
        paste("ERA5", site_id, ens_id, sep = "_")
      ),
      start_date = start_date,
      end_date = end_date,
      in.prefix = paste0("ERA5.", ens_id),
      outfolder = file.path(site_sipnet_met_path, site_id)
    )
  }
)
