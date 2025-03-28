library(tidyverse)
library(terra)

# Identifying the year of planting and orchard type of sites in the design
# point list, for use in comparisons between modeled and allometric biomass.

# Using 2020 because it is the first year containing planting year data,
# and filtering to sites whose planting year is <= 2016.
# Note that some of these sites went on to be cleared or replanted between
# 2020 and 2023, but since neither model nor allometry account for replanting
# we can include those in the comparison anyway.
# (just be careful not to compare cleared sites to 2023 LandTrender)

site_info <- read.csv("site_info.csv") |>
  rowid_to_column("rowid")

site_vec <- site_info |>
  vect(crs = "epsg:4326") |>
  project("epsg:4269")

planting_2020 <- vect("data_raw/dwr_map/i15_Crop_Mapping_2020.gdb/") |>
  project("epsg:4269") |>
  extract(site_vec) |>
  rename(rowid = id.y) |>
  left_join(site_info) |>
  filter(YR_PLANTED <= 2016, YR_PLANTED > 0)

planting_2023 <- vect("data_raw/dwr_map/i15_Crop_Mapping_2023_Provisional_20241127.gdb/") |>
  project("epsg:4269") |>
  extract(site_vec) |>
  mutate(still_present_2023 = YR_PLANTED <= 2016 & YR_PLANTED > 0) |>
  select(rowid = id.y, still_present_2023)

planting_2020 |>
  left_join(planting_2023) |>
  select(
    id,
    planting_year = YR_PLANTED,
    still_present_2023,
    crop_code = MAIN_CROP
  ) |>
  write.csv(
    "data/site_planting_years.csv",
    row.names = FALSE,
    quote = FALSE
  )
