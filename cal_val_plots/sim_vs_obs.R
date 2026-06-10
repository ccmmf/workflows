#!/usr/bin/env Rscript
# Sim-vs-obs plots for the 3 BU SIPNET ensembles


suppressPackageStartupMessages({
  library(ncdf4)
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(purrr)
  library(stringr)
  library(lubridate)
  library(tibble)
})

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
WORKBOOK_DIR <- Sys.getenv(
  "WORKBOOK_DIR",
  unset = "/projectnb2/dietzelab/ccmmf/usr/adey2/workflows"
)

MAGIC_MAIN    <- file.path(WORKBOOK_DIR, "MAGiC Calibration Validation Dataset(1).xlsx")
MAGIC_RUSSELL <- file.path(WORKBOOK_DIR, "MAGiC Calibration Validation Data_ Russell Ranch.xlsx")

SITES <- list(
  list(name        = "Salinas SOCS",
       short       = "salinas",
       site_id     = "9f296becf416ce87",
       treatment   = "socs_sys1",
       start_year  = 2003,
       end_year    = 2011,
       run_dir     = "/projectnb2/dietzelab/ccmmf/usr/adey2/runs/salinas-socs",
       workbook    = MAGIC_MAIN),
  list(name        = "Modesto Nichols",
       short       = "modesto",
       site_id     = "9cb08ca2174bede7",
       treatment   = "compost",
       start_year  = 2018,
       end_year    = 2019,
       run_dir     = "/projectnb2/dietzelab/ccmmf/usr/adey2/runs/modesto-nichols",
       workbook    = MAGIC_MAIN),
  list(name        = "Russell Ranch",
       short       = "russell",
       site_id     = "ec0e8b4d92044f52",
       treatment   = "conv_corn_tomato",
       start_year  = 2000,
       end_year    = 2014,
       run_dir     = "/projectnb2/dietzelab/ccmmf/usr/adey2/runs/russell-ranch",
       workbook    = MAGIC_RUSSELL)
)
OUT_DIR  <- Sys.getenv("OUT_DIR", unset = "plots")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

# Read a single PEcAn-style NetCDF (one year file) and return a tibble with
# posix + the requested variable. Time is encoded in the standard CF way
# (units = "days since YYYY-01-01" or similar).
read_one_nc <- function(nc_path, variable) {
  nc <- tryCatch(nc_open(nc_path), error = function(e) NULL)
  if (is.null(nc)) return(NULL)
  on.exit(nc_close(nc), add = TRUE)
  if (!(variable %in% names(nc$var))) return(NULL)

  vals <- ncvar_get(nc, variable)
  t_units <- ncatt_get(nc, "time", "units")$value
  t_vals  <- ncvar_get(nc, "time")

  origin <- sub("^[^0-9]*", "", t_units)
  origin <- sub(" .*$", "", origin)
  origin_date <- suppressWarnings(as.Date(origin))
  if (is.na(origin_date)) {
    origin_date <- as.Date(sub(".*since +", "", t_units))
  }
  if (grepl("seconds", t_units)) {
    posix <- as.POSIXct(origin_date) + t_vals
  } else if (grepl("hours", t_units)) {
    posix <- as.POSIXct(origin_date) + t_vals * 3600
  } else {
    posix <- as.POSIXct(origin_date) + t_vals * 86400
  }

  tibble::tibble(posix = posix, !!variable := as.numeric(vals))
}

# Load ensemble output across all ENS-* dirs for one site and one variable.
# Returns a tibble: ens_num, posix, year, <variable>.
read_ensemble <- function(run_dir, variable, start_year, end_year) {
  out_root <- file.path(run_dir, "output", "out")
  if (!dir.exists(out_root)) {
    message("  no output dir: ", out_root)
    return(NULL)
  }
  ens_dirs <- list.files(out_root, pattern = "^ENS-",
                         full.names = TRUE, include.dirs = TRUE)
  if (length(ens_dirs) == 0) {
    message("  no ENS-* dirs in: ", out_root)
    return(NULL)
  }
  rows <- purrr::map_dfr(ens_dirs, function(d) {
    ens_num <- as.integer(stringr::str_extract(basename(d), "(?<=ENS-)\\d+"))
    nc_files <- list.files(d, pattern = "^[0-9]{4}\\.nc$", full.names = TRUE)
    year_in_range <- function(p) {
      y <- as.integer(sub("\\.nc$", "", basename(p)))
      !is.na(y) && y >= start_year && y <= end_year
    }
    nc_files <- nc_files[vapply(nc_files, year_in_range, logical(1))]
    if (length(nc_files) == 0) return(NULL)
    df <- purrr::map_dfr(nc_files, read_one_nc, variable = variable)
    if (nrow(df) == 0) return(NULL)
    df$ens_num <- ens_num
    df
  })
  if (nrow(rows) == 0) return(NULL)
  rows
}

# Per-year ensemble quantiles (q05, q95, mean) at end-of-year.
ensemble_quantiles <- function(ens_df, variable) {
  ens_df |>
    dplyr::mutate(year = lubridate::year(posix)) |>
    dplyr::group_by(ens_num, year) |>
    dplyr::summarise(value = mean(.data[[variable]], na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      mean = mean(value, na.rm = TRUE),
      q05  = quantile(value, 0.05, na.rm = TRUE),
      q95  = quantile(value, 0.95, na.rm = TRUE),
      .groups = "drop"
    )
}
