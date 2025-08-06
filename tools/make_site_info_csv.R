#!/usr/bin/env Rscript

# A very quick hack for converting design points into site info for this run.

# This was used to create the committed site_info.csv;
# no need to rerun it unless design_points.csv changes upstream AND
# you want to propagate those changes into the run.

# Note: Assumes we want all columns from the design points

read.csv("data/design_points.csv", colClasses = c(UniqueID = "character")) |>
  dplyr::distinct() |> # TODO dupes in design points are a bug
  # dplyr::slice_sample(n = 3) |>
  dplyr::mutate(
    name = site_id,
    pft = dplyr::case_when(
      pft == "annual crop" ~ "grass",
      pft == "woody perennial crop" ~ "temperate.deciduous",
      TRUE ~ NA_character_
    )
  ) |>
  dplyr::rename(
    id = site_id,
    field_id = UniqueID,
    site.pft = pft) |>
  write.csv("site_info.csv", row.names = FALSE)
