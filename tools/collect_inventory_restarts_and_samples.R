#!/usr/bin/env Rscript

# Grabs the restart files and samples.Rdata from a PEcAn run,
# drops them all in one directory for easy archiving.

options <- list(
  optparse::make_option("--rundir",
    default = "output/",
    help = "Path to a PEcAn output directory"
  ),
  optparse::make_option("--out",
    default = "restart-file-archive",
    help = paste(
      "path in which to save restarts.*.out and samples.Rdata"
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



if (!dir.exists(args$out)) {
  dir.create(args$out, recursive = TRUE)
}

samp_ok <- file.copy(
  file.path(args$rundir, "samples.Rdata"),
  file.path(args$out, "samples.Rdata"),
  overwrite = TRUE
)
if (!samp_ok) {
  PEcAn.logger::logger.error(
    "Could not copy sample file from previous run",
    file.path(args$rundir, "samples.Rdata")
  )
}


restarts <- PEcAn.SIPNET::collect_restarts(
  file.path(args$rundir, "out"),
  args$out,
  overwrite = TRUE
)

# TODO do we want any kind of check whether all restarts were found?
# collect_restarts() checks for success copying the files it finds,
# but won't warn about e.g. runs that errored without saving a restart.
