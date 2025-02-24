#!/usr/bin/env Rscript

library(PEcAn.settings)

# Construct one multisite PEcAn XML file for statewide simulations

## Config section -- edit for your project
# TODO may want to read these from elsewhere eventually
ic_dir <- "IC_files"
met_dir <- "data/caladapt_met"
n_ens <- 3 # TODO low for testing
n_met <- 3 # TODO low for testing
start_date <- "2016-01-01"
end_date <- "2024-12-31"



site_info <- read.csv("site_info.csv")
stopifnot(length(unique(site_info$id)) == nrow(site_info))

settings <- read.settings("template.xml") |>
  setDates(start_date, end_date) |>
  createMultiSiteSettings(site_info) |>
  setEnsemblePaths(
    n_reps = 10,
    input_type = "met",
    path = met_dir,
    d1 = start_date,
    d2 = end_date,
    path_template = "{path}/{id}/caladapt.{id}.{n}.{d1}.{d2}.nc"
  ) |>
  setEnsemblePaths(
    n_reps = 100,
    input_type = "poolinitcond",
    path_template = "IC_files/{id}/IC_site_{n}.nc"
  )

write.settings(settings, outputfile = "pecan_with_sites.xml", outputdir = ".")
