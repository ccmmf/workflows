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

OUT_DIR  <- Sys.getenv("OUT_DIR", unset = "plots")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
