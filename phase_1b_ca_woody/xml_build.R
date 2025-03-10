#!/usr/bin/env Rscript

library(PEcAn.settings)

# Construct one multisite PEcAn XML file for statewide simulations

## Config section -- edit for your project
# TODO may want to read these from elsewhere eventually
ic_dir <- "IC_files"
met_dir <- "data/ERA5_SIPNET" # TODO switch to caladapt


n_ens <- 3 # TODO low for testing
n_met <- 10


start_date <- "2016-01-01"
end_date <- "2023-12-31" # TODO add 2024 when met avail


site_info <- read.csv("site_info.csv")
stopifnot(length(unique(site_info$id)) == nrow(site_info))

settings <- read.settings("template.xml") |>
  setDates(start_date, end_date)

settings$ensemble$size <- n_ens
settings$run$inputs$poolinitcond$ensemble <- n_ens
settings$host$modellauncher$mpirun <- sub(
  pattern = "@NJOBS@",
  replacement = nrow(site_info) * n_ens,
  x = settings$host$modellauncher$mpirun,
  fixed = TRUE
)

settings <- settings |>
  createMultiSiteSettings(site_info) |>
  setEnsemblePaths(
    n_reps = n_met,
    input_type = "met",
    path = met_dir,
    d1 = start_date,
    d2 = end_date,
    # TODO use caladapt when ready
    # path_template = "{path}/{id}/caladapt.{id}.{n}.{d1}.{d2}.nc"
    path_template = "{path}/{id}/ERA5.{n}.{d1}.{d2}.clim"
  ) |>
  setEnsemblePaths(
    n_reps = n_ens,
    input_type = "poolinitcond",
    path_template = "IC_files/{id}/IC_site_{id}_{n}.nc"
  )

write.settings(settings, outputfile = "settings.xml", outputdir = ".")
