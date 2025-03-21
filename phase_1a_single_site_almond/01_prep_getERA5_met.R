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
raw_era5_path <- "/projectnb/dietzelab/hamzed/ERA5/Data/Ensemble"


# Path to save intermediate format:
# Single site, single-year netcdfs, in subdirectories per ensemble member.
# Files named '<site_era5_path>/ERA5_<siteid>_<ensid>/ERA5.<ensid>.<year>.nc'
site_era5_path <- "/projectnb/dietzelab/chrisb/ERA5_losthills"

# Output path:
# single-site, multi-year Sipnet clim files, one per ensemble member.
# Files named <site_sipnet_met_path>/ERA5.<ensid>.<startdate>.<enddate>.clim
site_sipnet_met_path <- "/projectnb/dietzelab/chrisb/ERA5_losthills_SIPNET"

# location and time to extract
site_info <- list(
  site_id = "losthills",
  lat = 35.5103,
  lon = -119.6675,
  start_date = "1999-01-01",
  end_date = "2012-12-31"
)


# ----------- end system-specific ---------------------------------


options(
  repos = c(
    getOption("repos"), # to keep your existing CRAN mirror
    PEcAn = "pecanproject.r-universe.dev", # for PEcAn packages
    ropensci = "ropensci.r-universe.dev" # for deps `traits` and `taxize`
  )
)

if (!requireNamespace("PEcAn.all", quietly = TRUE)) {
  print("installing PEcAn.all")
  install.packages("PEcAn.all")
}

if (!requireNamespace("PEcAn.SIPNET", quietly = TRUE)) {
  print("Installing PEcAn.SIPNET")
  install.packages("PEcAn.SIPNET")
}

PEcAn.data.atmosphere::extract.nc.ERA5(
  slat = site_info$lat,
  slon = site_info$lon,
  in.path = raw_era5_path,
  start_date = site_info$start_date,
  end_date = site_info$end_date,
  outfolder = site_era5_path,
  in.prefix = "ERA5_",
  newsite = site_info$site_id
)
purrr::walk(
  1:10, # ensemble members
  ~PEcAn.SIPNET::met2model.SIPNET(
    in.path = file.path(site_era5_path,
                        paste("ERA5", site_info$site_id, ., sep = "_")),
    start_date = site_info$start_date,
    end_date = site_info$end_date,
    in.prefix = paste0("ERA5.", .),
    outfolder = site_sipnet_met_path
  )
)
