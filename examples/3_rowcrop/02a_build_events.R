#!/usr/bin/env Rscript

# Creates a single PEcAn-formatted `events.JSON` containing all management
# events from all years of all the locations in `site_info.csv`,
# then divides it into a Sipnet-formatted `events.in` for each site.

## ---------------------- parse command-line options --------------------------
options <- list(
  optparse::make_option("--site_info_path",
    default = "site_info.csv",
    help = "CSV giving ids, locations, and PFTs for sites of interest"
  ),
  optparse::make_option("--mgmt_file_dir",
    default = "data_raw/management",
    help = paste(
      "Directory containing management inputs in Parquet format.",
      "Note: Code currently looks for subpaths that include hard-coded",
      "version numbers for each management type."
    )
  ),
  optparse::make_option("--event_outdir",
    default = "data/events",
    help = "directory to write events-*.in, events.json, and phenology.csv"
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()

## -------------------------- end option parsing ------------------------------

library(tidyverse)

if (!dir.exists(args$event_outdir)) {
  dir.create(args$event_outdir, recursive = TRUE)
}

ids <- read.csv(
  args$site_info_path,
  colClasses = c(field_id = "character")
)$field_id

# read management files from inside mgmt directory
# TODO will break if not all mgmt types live at same path
# (e.g. user wants to pull in their own tillage but use monitored plant/harv)
read_parquet_years <- function(dir, parcel_ids, id_var = "parcel_id") {
  file.path(args$mgmt_file_dir, dir) |>
    list.files("*.parq(uet)?$", full.names = TRUE) |>
    arrow::open_dataset() |>
    # as.character is a hack bc planting dataset has id as string some years and int others.
    # TODO remove when fixed upstream.
    filter(as.character(.data[[id_var]]) %in% parcel_ids) |>
    collect()
}

# phenology doesn't have to be json -- we'll just write one CSV of all sites and years
pheno <- read_parquet_years("phenology/v1.0", ids, "site_id") |>
  # TODO some seasons wrap past year end (e.g. 2025-09-08 to 2026-03-29) --
  # current code drops year so leafonday > leafoffday, which write.config skips
  # as invalid.
  mutate(
    leafonday = lubridate::yday(leafonday),
    leafoffday = lubridate::yday(leafoffday)
  )
# If csv exists already, append instead of clobbering
# TODO keep old version of the dups instead of updating?
# Not sure which will be less surprising
pheno_out_path <- file.path(args$event_outdir, "phenology.csv")
if (file.exists(pheno_out_path)) {
  existing_pheno <- read.csv(
    pheno_out_path,
    colClasses = c(site_id = "character"))
  site_dups <- intersect(pheno$site_id, existing_pheno$site_id)
  if (length(site_dups) > 0) {
    warning(
      "Overwriting existing phenology records for",
      length(site_dups), "sites in", pheno_out_path
    )
  }
  pheno <- existing_pheno |>
    filter(!(site_id %in% site_dups)) |>
    bind_rows(pheno)
}
write.csv(pheno, file = pheno_out_path, row.names = FALSE)

plant <- read_parquet_years("planting/v1.0", ids, "site_id") |>
  # TODO fix upstream
  dplyr::rename(
    leaf_c_kg_m2 = C_LEAF,
    wood_c_kg_m2 = C_STEM,
    fine_root_c_kg_m2 = C_FINEROOT,
    coarse_root_c_kg_m2 = C_COARSEROOT,
  ) |>
  # Some planting events happen in the year previous to bulk of growth.
  # This is only a problem at the very start of the run, where the reported
  # planting date lands before start of simulation and causes a Sipnet error.
  # Temporary workaround: Adjust dates forward.
  # TODO: Should also (/instead?) adjust initial pool sizes in these cases.
  dplyr::mutate(date = pmax(date,  "2016-01-01"))

harv <- read_parquet_years("harvest/v1.0", ids, "site_id")

till <- read_parquet_years("tillage/v1.0", ids, "site_id") |>
  mutate(
    date = OGMn_date,
    # Placeholder -- better-informed conversion under development.
    # Note that NaNs get forced to 0. This was an arbitrary choice.
    tillage_eff_0to1 = pmax(0, pmin(1, ndti_pct_change / 100), na.rm = TRUE)
  )

irrig <- read_parquet_years("irrigation/v1.0", ids, "parcel_id") |>
  filter(
    # Ignore ensemble dimension. TODO support event ensembles across all event types
    ens_id == "irr_ens_001",
    # ignore all irrigation events before start of simulation
    date >= "2016-01-01"
  ) |>
  mutate(
    event_type = "irrigation",
    site_id = as.character(parcel_id),
    date = as.character(date)
  ) |>
  select(site_id, event_type, date, amount_mm, method)

# TODO add fertilization / NCC here when available

all_events <- dplyr::bind_rows(plant, harv, till, irrig) |>
  dplyr::arrange(site_id, date, event_type) |>
  dplyr::nest_by(site_id, .key="events") |>
  dplyr::mutate(pecan_events_version = "0.1.0")

evt_json_path <- file.path(args$event_outdir, "combined_events.json")
if (file.exists(evt_json_path)) {
  # TODO append to existing file like for phenology?
  # need more care to handle nesting right.
  warning("Overwriting existing events file", evt_json_path)
}
jsonlite::write_json(all_events, evt_json_path)

# Now divide the json into Sipnet events files
PEcAn.SIPNET::write.events.SIPNET(evt_json_path, args$event_outdir)


