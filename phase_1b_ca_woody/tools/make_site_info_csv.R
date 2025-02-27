#!/usr/bin/env Rscript

read.csv("data/design_points.csv") |>
  dplyr::distinct() |> # TODO dupes in design points are a bug
  dplyr::slice_sample(n = 3) |>
  dplyr::mutate(name = id, site.pft = "temperate.deciduous") |>
  write.csv("site_info.csv", row.names = FALSE)
