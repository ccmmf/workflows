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


#' Construct a list of paths to ensemble files
#'
#' Where by "ensemble" we really mean sets of files whose names differ only
#' by a replicate ID, and that should all be inserted into a PEcAn settings
#' as one block of the form
#' ```
#' <path>
#'   <path1>path/to/siteA/file.1.ext</path1>
#'   <path2>path/to/siteA/file.2.ext</path2>
#'   [...]
#'   <path[n]>path/to/siteA/file.[n].ext</path[n]>
#' </path>
#' ```
#'
#' @param id site identifier
#' @param n vector of replicate ids
#' @param glue_str Specification of how to interpolate variables into the
#'  paths, as a `glue::glue()` input (see examples)
#' @param ... other variables to be interpolated into the path
#' @examples
#' build_path("3ab23f", 1:3, "IC/{id}/IC_{id}_{n}.nc")
#' build_path("2ce800", 1:3, yr = 2003, "ERA5/{id}/ERA5_{yr}_{n}.clim")
build_paths <- function(id, n, glue_str = "./{id}_{n}.nc", ...) {
  glue::glue(glue_str, id = id, n = n, ...) |>
    as.list() |>
    setNames(glue::glue("path{n}", n = n))
}


site_info <- read.csv("site_info.csv")
stopifnot(length(unique(site_info$id)) == nrow(site_info))

settings <- read.settings("template.xml") |>
  setDates(start_date, end_date) |>
  createMultiSiteSettings(site_info)


for (siteid in site_info$id) {
  sid_str <- paste0("site.", siteid)
  settings$run[[sid_str]]$inputs$met$path <- build_paths(
    id = siteid,
    n = seq_len(n_met),
    path = met_dir,
    d1 = start_date,
    d2 = end_date,
    "{path}/{id}/caladapt.{id}.{n}.{d1}.{d2}.nc"
  )
  settings$run[[sid_str]]$inputs$poolinitcond$path <- build_paths(
    id = siteid,
    n = seq_len(n_ens),
    path = ic_dir,
    "{path}/{id}/IC_site_{id}_{n}.nc"
  )
}

# settings$run[[sid_str]]$inputs$met$path <-
  # paste("caladapt", siteid, seq_len(n_met),
  #       start_date, end_date, "nc", sep = ".") |>
  # file.path(met_dir, siteid, f = _) |>
  # name_paths_for_xml()
# settings$run[[sid_str]]$inputs$poolinitcond$path <-
  # paste0("IC_site_", siteid, "_", seq_len(n_ens), ".nc") |>
  # file.path(ic_dir, siteid, f = _) |>
  # name_paths_for_xml()


write.settings(settings, outputfile = "pecan_with_sites.xml", outputdir = ".")
