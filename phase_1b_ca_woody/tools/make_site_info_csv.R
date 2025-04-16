#!/usr/bin/env Rscript

# A very quick hack for converting design points into site info for this run.

# This was used to create the committed site_info.csv;
# no need to rerun it unless design_points.csv changes upstream AND
# you want to propagate those changes into the run.

# Note: Assumes we want all columns from the design points
# and that all sites are woody.
# Will need refinement for multi-PFT runs in phase 2 and beyond.

read.csv("data/design_points.csv") |>
  dplyr::distinct() |> # TODO dupes in design points are a bug
  # dplyr::slice_sample(n = 3) |>
  dplyr::mutate(name = id, site.pft = "temperate.deciduous") |>
  write.csv("site_info.csv", row.names = FALSE)
