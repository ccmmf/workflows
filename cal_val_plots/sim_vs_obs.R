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
