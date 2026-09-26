#!/usr/bin/env Rscript

# Adapted from a more generic script maintained as part of PEcAn.
# Its path in the PEcAn repository is workflows/preprocess-event-parquet/01b-clean-other-events.R.
# Modifications added here: argument parsing, filtering/rescheduling of events
# outside the simulation date range, filtering to target sites.

## ---------------------- parse command-line options --------------------------
options <- list(
  optparse::make_option("--site_info_path",
    default = "site_info.csv",
    help = "CSV giving ids to be extracted. Only column 'field_id' is used"
  ),
  optparse::make_option("--pheno_dir",
    default = "data_raw/management/phenology/v1.0",
    help = "Directory containing Parquet files of phenology (leafon/leafoff) events"
  ),
  optparse::make_option("--planting_dir",
    default = "data_raw/management/planting/v1.0",
    help = "Directory containing Parquet files of planting events"
  ),
  optparse::make_option("--harvest_dir",
    default = "data_raw/management/harvest/v1.0",
    help = "Directory containing Parquet files of harvest events"
  ),
  optparse::make_option("--tillage_dir",
    default = "data_raw/management/tillage/v1.0",
    help = "Directory containing Parquet files of tillage events"
  ),
  optparse::make_option("--outdir",
    default = "data/management/",
    help = paste(
      "Directory to write cleaned events.",
      "Format will be a single Parquet file per event type."
    )
  ),
  optparse::make_option("--adjust_start",
    default = "2016-01-01",
    help = paste(
      "Used by planting and leafon only:",
      "Events before this date (e.g. winter planting of a spring crop)",
      "are adjusted forward to happen on the first simulation day.",
      "this ensures they are seen by Sipnet rather than filtered out"
    )
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

# Convert "parcel_id" columns to "site_id"
#
# Most management sources preserve DWR field identity via "parcel_id",
# but some label it "site_id". PEcan's event JSON standard expects "site_id",
# so converting it here.
# Why the terminology change? Because this is the moment we conceptually switch
# from data monitored on a whole field (parcel_id) to events used to model a
# point location (site_id).
harmonize_siteid <- function(dat) {
  if ("site_id" %in% colnames(dat)) {
    return(dat)
  } else if (!"parcel_id" %in% colnames(dat)) {
    stop("no parcel id found in data")
  }

  dplyr::rename(dat, site_id = parcel_id)
}


siteids <- read.csv(args$site_info_path) |>
  _$id |>
  unique()

dir.create(args$outdir, showWarnings = FALSE, recursive = TRUE)

message("Writing harvest output")
harvest <- arrow::open_dataset(args$harvest_dir, format = "parquet") |>
  harmonize_siteid() |>
  dplyr::filter(
    as.character(site_id) %in% siteids,
    !is.na(date)
  ) |>
  dplyr::mutate(
    site_id = as.integer(site_id),
    date = as.Date(date)
  ) |>
  dplyr::arrange(.data$site_id) |>
  dplyr::select(
    "event_type",
    "site_id",
    "date",
    "frac_above_removed_0to1",
    "frac_below_removed_0to1",
    "frac_above_to_litter_0to1",
    "frac_below_to_litter_0to1"
  ) |>
  arrow::write_parquet(
    file.path(args$outdir, "harvest.parquet"),
    compression = "ZSTD"
  )

message("Writing planting output")
planting <- arrow::open_dataset(args$planting_dir, format = "parquet") |>
  harmonize_siteid() |>
  dplyr::filter(
    as.character(site_id) %in% siteids,
    !is.na(date)
  ) |>
  dplyr::mutate(
    site_id = as.integer(site_id),
    date = pmax(as.Date(date), as.Date(args$adjust_start)) # push earlier plantings forward to avoid beginning-of-run boundary error
  ) |>
  # Keep accepting v1 naming scheme
  dplyr::rename_with(
    \(x) dplyr::case_when(
      x == "code" ~ "crop_code",
      x == "C_LEAF" ~ "leaf_c_kg_m2",
      x == "C_STEM" ~ "wood_c_kg_m2",
      x == "C_FINEROOT" ~ "fine_root_c_kg_m2",
      x == "C_COARSEROOT" ~ "coarse_root_c_kg_m2",
      x == "N_LEAF" ~ "leaf_n_kg_m2",
      x == "N_STEM" ~ "wood_n_kg_m2",
      x == "N_FINEROOT" ~ "fine_root_n_kg_m2",
      x == "N_COARSEROOT" ~ "coarse_root_n_kg_m2",
      TRUE ~ x
    )
  ) |>
  dplyr::select(
    "event_type",
    "site_id",
    "date",
    "crop_code",
    "leaf_c_kg_m2",
    "wood_c_kg_m2",
    "fine_root_c_kg_m2",
    "coarse_root_c_kg_m2",
    "leaf_n_kg_m2",
    "wood_n_kg_m2",
    "fine_root_n_kg_m2",
    "coarse_root_n_kg_m2"
  ) |>
  # TODO maybe these should be louder warnings/errors?
  dplyr::filter(dplyr::across(everything(), ~!is.na(.))) |>
  arrow::write_parquet(
    file.path(args$outdir, "planting.parquet"),
    compression = "ZSTD"
  )

message("Writing tillage output")
tillage <- arrow::open_dataset(args$tillage_dir, format = "parquet") |>
  harmonize_siteid() |>
  dplyr::filter(as.character(.data$site_id) %in% siteids) |>
  dplyr::mutate(site_id = as.integer(site_id)) |>
  dplyr::rename_with(
    # Handle naming inconsistencies between input versions
    \(x) dplyr::case_when(
      x == "pct_ndti_change" ~ "ndti_pct_change",
      x == "OGMn_date" ~ "date",
      TRUE ~ x
    )
  ) |>
  dplyr::filter(
    is.finite(ndti_pct_change),
    ndti_pct_change >= 0,
    !is.na(date)
  )
if (!"tillage_eff_0to1" %in% colnames(tillage)) {
  tillage <- tillage |>
    dplyr::collect() |> # arrow can't inline ndti_to_sipnet_tillage()
    dplyr::mutate(
      tillage_eff_0to1 = PEcAn.data.land::ndti_to_sipnet_tillage(
        .data$ndti_pct_change / 100
      )
    )
}
tillage <- tillage |>
  dplyr::select(
    "event_type",
    "site_id",
    "date",
    "tillage_eff_0to1"
  ) |>
  arrow::write_parquet(
    file.path(args$outdir, "tillage.parquet"),
    compression = "ZSTD"
  )

message("Writing phenology output")
phenology <- arrow::open_dataset(args$pheno_dir, format = "parquet") |>
  harmonize_siteid() |>
  dplyr::filter(as.character(site_id) %in% siteids) |> dplyr::collect()

if (all(c("leafonday", "leafoffday") %in% colnames(phenology))) {
  # wide form; use the appropriate column
  leafon <- phenology |>
    dplyr::filter(!is.na(leafonday)) |>
    dplyr::select("site_id", "date" = leafonday)
  leafoff <- phenology |>
    dplyr::filter(!is.na(leafoffday)) |>
    dplyr::select("site_id", "date" = leafoffday)
} else if (all(c("date", "event_type") %in% colnames(phenology))) {
  # long form w/event type column distinguishing leafon from leafoff
  leafon <- phenology |>
    dplyr::filter(event_type == "leafon", !is.na(date)) |>
    dplyr::select("site_id", "date")
  leafoff <- phenology |>
    dplyr::filter(event_type == "leafoff", !is.na(date)) |>
    dplyr::select("site_id", "date")
} else {
  PEcAn.logger::logger.severe("Unrecognized phenology format")
}

leafon <- leafon |>
  dplyr::mutate(
    event_type = "leafon",
    site_id = as.integer(.data$site_id),
    date = pmax(as.Date(date), as.Date(args$adjust_start)) # push earlier leafons forward to avoid beginning-of-run boundary error
  )|>
  arrow::write_parquet(
    file.path(args$outdir, "leafon.parquet"),
    compression = "ZSTD"
  )
leafoff <- phenology |>
  dplyr::mutate(
    event_type = "leafoff",
    site_id = as.integer(.data$site_id),
    date = as.Date(.data$date)
  ) |>
  arrow::write_parquet(
    file.path(args$outdir, "leafoff.parquet"),
    compression = "ZSTD"
  )
