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

loc_tmp_file <- "validation_site_locs.csv"
output_file <- "validation_site_info.csv"

# can't use datapoints from before our simulations start
min_yr <- 2016

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
  mutate(
    val_id = paste(ProjectName, BaseID, Latitude, Longitude) |>
      purrr::map_chr(rlang::hash)
  ) |>
  inner_join(site_ids) |>
  select(val_id, lat = Latitude, lon = Longitude)

# Match against field IDs and crop codes using same script used on non-val files
# TODO avoid round trip to CSV here...
# I replaced a chunk of code that was redundant with `build_site_info.R`
# and this was faster than thinking how to refactor further
write.csv(site_locs, loc_tmp_file, row.names = FALSE)
callr::rscript(
  "../tools/build_site_info.R",
  cmdargs = c(paste0("--location_file=", loc_tmp_file),
              paste0("--out_file=", output_file))
)
read.csv(output_file) |>
  # TODO is this desirable?
  # In production, may be better to complain if no PFT match
  drop_na(site.pft) |>
  # Temporary hack:
  # Where multiple treatments share a location,
  # use only one of them
  group_by(lat, lon, site.pft) |>
  slice_sample(n = 1) |>
  ungroup() |>
  write.csv(output_file, row.names = FALSE)
