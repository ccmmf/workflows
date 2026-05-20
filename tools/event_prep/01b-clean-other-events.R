#!/usr/bin/env Rscript

# Adapted from a more generic script maintained as part of PEcAn.
# Its path in the PEcAn repository is workflows/preprocess-event-parquet/01b-clean-other-events.R.
# Modifications added here: argument parsing, filtering/rescheduling of events outside the simulation date range.

## ---------------------- parse command-line options --------------------------
options <- list(
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
    help = "Directory containing Parquet files of hrvest events"
  ),
  optparse::make_option("--tillage_dir",
    default = "data_raw/management/tillage/v1.0",
    help = "Directory containing Parquet files of tillage events"
  ),
  # Fertilization and organic amendment files can be added here when ready
  # optparse::make_option("--fert_dir",...),
  # optparse::make_option("--ncc_dir",...),
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


harvest_files <- list.files(args$harvest_dir, "\\.parquet", full.names = TRUE, recursive = TRUE)
planting_files <- list.files(args$planting_dir, "\\.parquet$", full.names = TRUE, recursive = TRUE)
phenology_files <- list.files(args$pheno_dir, "\\.parquet$", full.names = TRUE, recursive = TRUE)
tillage_files <- list.files(args$tillage_dir, "\\.parquet$", full.names = TRUE, recursive = TRUE)
dir.create(args$outdir, showWarnings = FALSE, recursive = TRUE)

message("Writing harvest output")
harvest <- arrow::open_dataset(harvest_files, format = "parquet") |>
  dplyr::mutate(
    site_id = as.integer(site_id),
    date = as.Date(date)
  ) |>
  dplyr::arrange(.data$site_id) |>
  arrow::write_parquet(
    file.path(args$outdir, "harvest.parquet"),
    compression = "ZSTD"
  )

message("Writing planting output")
planting <- arrow::open_dataset(planting_files, format = "parquet") |>
  dplyr::mutate(
    site_id = as.integer(site_id),
    date = pmax(as.Date(date), as.Date(args$adjust_start)) # push earlier plantings forward to avoid beginning-of-run boundary error
  ) |>
  dplyr::rename(
    crop_code = "code",
    leaf_c_kg_m2 = "C_LEAF",
    wood_c_kg_m2 = "C_STEM",
    fine_root_c_kg_m2 = "C_FINEROOT",
    coarse_root_c_kg_m2 = "C_COARSEROOT",
    leaf_n_kg_m2 = "N_LEAF",
    wood_n_kg_m2 = "N_STEM",
    fine_root_n_kg_m2 = "N_FINEROOT",
    coarse_root_n_kg_m2 = "N_COARSEROOT"
  ) |>
  arrow::write_parquet(
    file.path(args$outdir, "planting.parquet"),
    compression = "ZSTD"
  )

# Equation is from PEcAn.data.land::ndti_to_sipnet_tillage,
# reimplemented here in simpler form so that Arrow's expression parser can
#  execute it directly as C++ without needing to pull the dataset back into R
pct_to_tillage <- function (delta_ndti, no_till_threshold = 0.3, slope = 2.5) {
  pmin(pmax(((delta_ndti/100) - no_till_threshold) * slope,
            0),
       1)
}

message("Writing tillage output")
tillage <- arrow::open_dataset(tillage_files, format = "parquet") |>
  dplyr::filter(
    is.finite(.data$ndti_pct_change),
    .data$ndti_pct_change >= 0
  ) |>
  dplyr::mutate(
    site_id = as.integer(site_id),
    tillage_eff_0to1 = pct_to_tillage(ndti_pct_change),
    date = as.Date(.data$OGMn_date)
  ) |>
  dplyr::select(
    "site_id",
    "date",
    "tillage_eff_0to1"
  ) |>
  arrow::write_parquet(
    file.path(args$outdir, "tillage.parquet"),
    compression = "ZSTD"
  )

message("Writing phenology output")
phenology <- arrow::open_dataset(phenology_files, format = "parquet")
leafon <- phenology |>
  dplyr::select("site_id", date = "leafonday") |>
  dplyr::mutate(
    site_id = as.integer(.data$site_id),
    date = pmax(as.Date(date), as.Date(args$adjust_start)) # push earlier leafons forward to avoid beginning-of-run boundary error
  )|>
  arrow::write_parquet(
    file.path(args$outdir, "leafon.parquet"),
    compression = "ZSTD"
  )
leafoff <- phenology |>
  dplyr::select("site_id", date = "leafoffday") |>
  dplyr::mutate(
    site_id = as.integer(.data$site_id),
    date = as.Date(.data$date)
  ) |>
  arrow::write_parquet(
    file.path(args$outdir, "leafoff.parquet"),
    compression = "ZSTD"
  )
