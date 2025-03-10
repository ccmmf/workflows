#!/usr/bin/env Rscript

## --------- edit for your system and site ----------------------------

# Path to your existing ERA5 data in PEcAn CF format:
# Single site, single-year netcdfs, in subdirectories per ensemble member.
# Files named '<site_era5_path>/ERA5_<siteid>_<ensid>/ERA5.<ensid>.<year>.nc'
site_era5_path <- "data_raw/ERA5_nc"

# Output path:
# single-site, multi-year Sipnet clim files, one per ensemble member.
# Files named <site_sipnet_met_path>/<siteid>/ERA5.<ensid>.<start>.<end>.clim
site_sipnet_met_path <- "data/ERA5_SIPNET"

# location and time to extract
site_info <- read.csv("site_info.csv")
site_info$start_date <- "2016-01-01"
site_info$end_date <- "2023-12-31"


future::plan("multisession", workers = 4)


# ----------- end system-specific ---------------------------------


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
