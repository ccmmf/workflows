library(tidyverse)
library(terra)

# Generates a CSV containing the mapped orchard type and year of planting for
# sites in the design point list that were growing orange, almond, pistachio,
# or walnut in 2016 (start of simulations), along with annotation on whether
# they were still growing in 2023 (end of simulations).

# I use this file during validation to do comparisons between modeled and
# allometric biomass.

# Requires geodatabases for the 2020 and 2023 CA crop maps, available from
# https://data.cnra.ca.gov/dataset/statewide-crop-mapping
# I read from the 2020 map because it is the first year that contains
# planting year data, then filter to sites whose planting year is <= 2016.

# Note that sites which went on to be cleared or replanted between 2020 and
# 2023 (still_present_2023 = FALSE) are OK to include in the model <> allometry
# comparison because neither of those account for replanting,
# but comparing cleared sites to the 2023 LandTrender data is _not_ valid.

site_info <- read.csv("site_info.csv") |>
  rowid_to_column("rowid")

site_vec <- site_info |>
  vect(crs = "epsg:4326") |>
  project("epsg:4269")

planting_2020 <- vect("data_raw/crop_maps/i15_Crop_Mapping_2020.gdb/") |>
  project("epsg:4269") |>
  extract(site_vec) |>
  rename(rowid = id.y) |>
  left_join(site_info) |>
  filter(YR_PLANTED <= 2016, YR_PLANTED > 0)

planting_2023 <- vect("data_raw/crop_maps/i15_Crop_Mapping_2023_Provisional_20241127.gdb/") |>
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
