#!/usr/bin/env Rscript

# Collects the restart.out files containing final model state from a previous
# batch of Sipnet runs, and copies them as sipnet.in to a new batch that will
# use them as initial conditions.

# Requirements for the previous and new batches to align:
# - Same site list and ensemble size
# - Same sample design
# - Prev run ends at start time of new run
# - Same build of Sipnet (restart files are not compatible between versions)
# - Sites that ended with an error in the previous run will error in the new
#   run too.
# - For the files to have any effect, settings$model$options needs to contain
#   `<RESTART_IN>restart.in</RESTART_IN>`

# Tentative design: Copies restarts first from the previous rundir into a
# `restarts_in` directory in the new dir, then each file is copied again from
# `<outdir>/restarts/restart-<siteid>-<ensid>.out` to
# `<outdir>/run/ENS-<ensid>-<siteid>/restart.in`.
# TODO: consider deleting `restarts/` when finished once we're confident the
# copying works reliably

options <- list(
  optparse::make_option("--prev_run_dir",
    default = "output/",
    help = paste(
      "Path to the output/ folder of a previously run PEcAn workflow,",
      "containing outputs that were run using Sipnet 2.x with its restart.out",
      "file enabled. For outputs that were run in multiple segments, only the",
      "last restart file will be copied."
    )
  ),
  optparse::make_option("--new_run_dir",
    default = "your_new_pecan_dir_here",
    help = paste(
      "Output path:",
      "A new PEcAn workflow directory into which restarts should be copied."
      "Will create or populate subdirs `restarts_in` and `/output/run/ENS-*`"
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
restart_dir <- file.path(args$new_run_dir, "restarts_in")
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
      "output", # TODO make configurable?
      "run",
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

