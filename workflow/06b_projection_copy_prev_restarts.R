#!/usr/bin/env Rscript

options <- list(
  optparse::make_option("--prev_run_dir",
    default = "output/",
    help = paste(
      "Path to a set of PEcAn outputs, possibly segmented, that were run",
      "using Sipnet 2.x with its restart.out file enabled"
    )
  ),
  optparse::make_option("--new_run_dir",
    default = "collected_restarts",
    help = paste(
      "Output path:",
      "A new run directory into which restarts should be copied."
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

if (!dir.exists(args$new_run_dir)) {
  dir.create(args$new_run_dir, recursive = TRUE)
}

# Dunno if we actually need to keep a separate copy of these,
# but will do it that way at least for initial debug
restart_dir <- file.path(args$new_run_dir, "restarts")
 if (!dir.exists(restart_dir)) {
  dir.create(restart_dir, recursive = TRUE)
}
restarts <- PEcAn.SIPNET::collect_restarts(
  args$prev_run_dir,
  restart_dir,
  overwrite = TRUE
)

restart_locs <- data.frame(path = basename(restarts)) |> 
  tidyr::separate_wider_regex(
    cols = "path",
    patterns = c("restart-", site = "\\d+", "-", ens = ".+", "\\.out"),
    cols_remove = FALSE
  ) |>
  dplyr::mutate(
    dest_path = file.path(
      args$new_run_dir,
      "run", # TODO bake this into new_run_dir?
      paste("ENS", ens, site, sep = "-"),
      "restart.in")
  )

dirs_ok <- restart_locs$dest_path |>
  dirname() |>
  purrr::map_lgl( \(p) dir.exists(p) || dir.create(p, recursive = TRUE))
if (!all(dirs_ok)) {
  PEcAn.logger::logger.warn(
    "Failed to create these dirs for restart file copying:",
    toString(dirname(restart_locs$dest_path[!dirs_ok]))
  )
}

copies_ok <- file.copy(
  file.path(dirname(restarts), restart_locs$path),
  restart_locs$dest_path,
  overwrite = TRUE
)
if (!all(copies_ok)) {
  PEcAn.logger::logger.warn(
    "Some restart files not copied:",
    toString(restart_locs$path[!copies_ok])
   )
}

samp_ok <- file.copy(
  file.path(args$prev_run_dir, "samples.Rdata"),
  file.path(args$new_run_dir, "samples.Rdata"),
  overwrite = TRUE
)
if (!samp_ok) {
  PEcAn.logger::logger.error(
    "Could not copy sample file from previous run",
    file.path(args$prev_run_dir, "samples.Rdata")
  )
}

# for debugging -- if downstream sampling works as I think,
# expect both copies to stay identical 
# file.copy(
#   file.path(args$prev_run_dir, "samples.Rdata"),
#   file.path(args$new_run_dir, "samples_orig.Rdata"),
# )
