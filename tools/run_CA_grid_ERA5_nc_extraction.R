#!/usr/bin/env Rscript

# Extract 0.5-degree-gridded ERA5 met for all of California
#
# Ran on BU cluster as:
# qsub -pe omp 28 -l mem_per_core=4G -o prep_getERA5_CAgrid_met.log -j y \
#   run_CA_grid_ERA5_nc_extraction.R

library(terra)

print(paste("start at", Sys.time()))


ca_shp <- vect("~/cur/ccmmf/workflows/data_raw/ca_outline_shp/")

ca_bboxgrid <- expand.grid(
  lon = seq(from = -124.5, to = -114, by = 0.5),
  lat = seq(from = 32.5, to = 42, by = 0.5)
) |>
  mutate(id = paste0(lat, "N_", abs(lon), "W"))
ca_gridcell_ids <- ca_bboxgrid |>
  vect(crs = "epsg:4326") |>
  project(ca_shp) |>
  buffer(27778) |> # 1/4 degree in meters
  intersect(ca_shp) |>
  _$id
ca_grid <- ca_bboxgrid |>
  filter(id %in% ca_gridcell_ids)

PEcAn.data.atmosphere::extract.nc.ERA5(
  slat = ca_grid$lat,
  slon = ca_grid$lon,
  in.path = "/projectnb/dietzelab/dongchen/anchorSites/ERA5",
  start_date = "2016-01-01",
  end_date = "2024-12-31",
  outfolder = "/projectnb/dietzelab/chrisb/ERA5_nc_CA_grid",
  in.prefix = "ERA5_",
  newsite = ca_grid$id,
  ncores = 27
)

print(paste("done at", Sys.time()))
