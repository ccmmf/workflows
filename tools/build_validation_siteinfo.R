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

# parcel ID lookup
field_map <- "data_raw/management/crops/v4.1/parcels-consolidated.gpkg"
field_pft_info <- "data_raw/management/crops/v4.1/crops_all_years.parq"

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
dwr_field_pfts <- arrow::read_parquet(field_pft_info) |>
  dplyr::filter(year == min_yr, season == 2) |>
  select(parcel_id, crop_class = CLASS)
site_dwr_ids <- site_locs |>
  terra::vect(crs = "epsg:4326") |>
  terra::project(dwr_fields) |>
  terra::nearest(dwr_fields) |>
  as.data.frame() |>
  mutate(
    ProjectName = site_locs$ProjectName[from_id],
    BaseID = site_locs$BaseID[from_id],
    parcel_id = dwr_fields$parcel_id[to_id],
  ) |>
  left_join(dwr_field_pfts)

stopifnot(nrow(site_dwr_ids) == nrow(site_locs))

site_locs |>
  left_join(site_dwr_ids, by = c("ProjectName", "BaseID")) |>
  mutate(
    id = paste(ProjectName, BaseID, lat, lon) |>
      purrr::map_chr(rlang::hash),
    pft = dplyr::case_when(
      crop_class %in% c("F", "G", "T") ~ "annual_crop", # TODO assumes all G are annual. Refine?
      crop_class %in% c("P", "T") ~ "grass",
      crop_class %in% c("D", "C", "V", "YP") ~ "temperate.deciduous",
      # TODO later: R = rice, T19 & T28 = woody berries, T16 = flowers/nursery/xmastrees
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
  select(id, field_id = parcel_id, lat, lon, site.pft = pft) |>
  write.csv("validation_site_info.csv", row.names = FALSE)
