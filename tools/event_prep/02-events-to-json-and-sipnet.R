#!/usr/bin/env Rscript



# Adapted from a more generic script maintained as part of PEcAn.
# Its path in the PEcAn repository is workflows/preprocess-event-parquet/02_events-to-json.R.
# Modifications added here: argument parsing, site specification via CSV, writing Sipnet event files in same step as validation

## ---------------------- parse command-line options --------------------------
options <- list(
  optparse::make_option("--site_info_path",
    default = "site_info.csv",
    help = "CSV giving ids, locations, and PFTs for sites of interest"
  ),
  optparse::make_option("--parquet_dir",
    default = "data/management/",
    help = paste(
      "Directory containing Parquet files of each event type,",
      "either as single files or Hive-partitioned subdirectories",
      "named `<event_type>.parquet`"
    )
  ),
  optparse::make_option("--event_dir",
    default = "data/events/",
    help = "Directory to write combined events as one JSON file per ensemble member"
  ),
  optparse::make_option("--start_date",
    default = "2016-01-01",
    help = "Remove events before this date"
  ),
  optparse::make_option("--end_date",
    default = "2023-12-31",
    help = "Remove events after this date"
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


dir.create(args$event_dir, showWarnings = FALSE, recursive = TRUE)
site_ids <- read.csv(args$site_info_path)$id

ens_ids <- PEcAn.data.land::get_event_ensemble_ids(parquet_dir = args$parquet_dir)

events_ensemble_manifest <- dplyr::as_tibble(ens_ids) |>
  dplyr::mutate(
    ensemble_id = sprintf("ens_%03d", dplyr::row_number()),
    json_path = file.path(
      .env$args$event_dir,
      sprintf("events_%s.json", .data$ensemble_id)
    )
  ) |>
  dplyr::relocate("ensemble_id", "json_path")

events_files <- PEcAn.data.land::event_parquet_to_json(
  parquet_dir = args$parquet_dir,
  events_ensemble_manifest = events_ensemble_manifest,
  site_ids = site_ids,
  start_date = args$start_date,
  end_date = args$end_date
)


message("Validating event files and converting to Sipnet .in format")
pb <- utils::txtProgressBar(0, nrow(events_files))
for (i in seq_len(nrow(events_files))) {
  path <- events_files[["json_path"]][[i]]
  # TODO I'd prefer to organize event files by site then rep,
  # but rep then site is easier with current write.events.SIPNET behavior
  # of writing to outdir/events-<siteid>.in.
  # For today let's go with what's easy
  ensdir <- file.path(args$event_dir, events_files[["ensemble_id"]][[i]])
  PEcAn.SIPNET::write.events.SIPNET(path, ensdir)

  # Write CSVs of crop changes, used to pick restart times later.
  # Sites with no changes drop out of the events_to_crop_cycle_starts result;
  # we add them back to write a zero-row CSV for these sites.
  PEcAn.data.land::events_to_crop_cycle_starts(path) |>
    dplyr::full_join(
      data.frame(site_id = as.character(site_ids)),
      by = "site_id"
    ) |>
    dplyr::group_by(site_id) |>
    dplyr::group_walk(~write.csv(
      .x |> tidyr::drop_na(),
      file = file.path(
        ensdir,
        paste0("cycles-", .y$site_id, ".csv")
      ),
      row.names = FALSE
    ))

  utils::setTxtProgressBar(pb, i)
}
close(pb)

