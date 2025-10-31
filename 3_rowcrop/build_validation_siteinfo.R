#!/usr/bin/env Rscript

library(terra)
library(tidyverse)

set.seed(20251029)

# Validation data is primarily from Healthy Soil Program demonstration sites,
# and is used with site owner permission granted to CARB and CDFA for nonpublic
# research purposes only. Do not release data or publish in any form that makes
# datapoints identifiable.
# Contact chelsea.carey@arb.ca.gov for more information.
data_dir <- "data_raw/private/HSP/"
soc_file <- "Harmonized_Data_Croplands.csv"
mgmt_file <- "Harmonized_SiteMngmt_Croplands.csv"

# can't use datapoints from before our simulations start
min_yr <- 2016

# TODO using 2018 for compatibility with field ids used in IC script;
# still need to harmonize IDs with those in data_raw/crop_map/ca_fields.gpkg
field_map <- "data_raw/dwr_map/i15_Crop_Mapping_2018.gdb"

# For first pass, selecting only the control/no-treatment plots.
# TODO: revisit this as we build more management into the workflow.
site_ids <- read.csv(file.path(data_dir, mgmt_file)) |>
  filter(Treatment_Control %in% c("Control", "None")) |>
  distinct(ProjectName, BaseID)

site_locs <- read.csv(file.path(data_dir, soc_file)) |>
  filter(Year >= min_yr) |>
  # some IDs in site_locs contain spaces stripped in site_id; let's match
  mutate(BaseID = gsub("\\s+", "", BaseID)) |>
  distinct(ProjectName, BaseID, Latitude, Longitude) |>
  rename(lat = Latitude, lon = Longitude) |>
  inner_join(site_ids)

dwr_fields <- terra::vect(field_map)
site_dwr_ids <- site_locs |>
  terra::vect(crs = "epsg:4326") |>
  terra::project(dwr_fields) |>
  terra::nearest(dwr_fields) |>
  as.data.frame() |>
  mutate(
    ProjectName = site_locs$ProjectName[from_id],
    BaseID = site_locs$BaseID[from_id],
    field_id = dwr_fields$UniqueID[to_id],
    crop_class = dwr_fields$SYMB_CLASS[to_id]
  )
stopifnot(nrow(site_dwr_ids) == nrow(site_locs))

site_locs |>
  left_join(site_dwr_ids, by = c("ProjectName", "BaseID")) |>
  mutate(
    id = paste(ProjectName, BaseID, lat, lon) |>
      purrr::map_chr(rlang::hash),
    pft = dplyr::case_when(
      crop_class %in% c("G", "F", "P", "T") ~ "grass",
      crop_class %in% c("D", "C", "V", "YP") ~ "temperate.deciduous",
      # TODO later: R = rice, T19 & T28 = woody berries
      TRUE ~ NA_character_
    )
  ) |>
  # TODO is this desirable?
  # In production, may be better to complain if no PFT match
  drop_na(pft) |>
  # Temporary hack:
  # Where multiple treatments share a location,
  # use only one of them
  group_by(lat, lon, pft) |>
  slice_sample(n = 1) |>
  ungroup() |>
  select(id, field_id, lat, lon, site.pft = pft, name = BaseID) |>
  write.csv("validation_site_info.csv", row.names = FALSE)
