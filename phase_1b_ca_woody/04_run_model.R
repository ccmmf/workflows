#!/usr/bin/env Rscript


library("PEcAn.all")


# --------------------------------------------------
# get command-line arguments
# TODO Much of what `get_args` does is not relevant for CCMMF;
# the main useful effect is it takes the settings XML from the command-line
# argument `--settings=/path/to/single_site_almond.xml`.
#
# Simpler approaches that may work as well:
# - If you only plan to run this with one settings file, hard-code it here
#     as args <- list(settings = "/path/to/single_site_almond.xml", continue = FALSE)
# - To accept the settings file as an argument but with less typing,
#   edit this to args$settings <- commandArgs(trailingOnly = TRUE)[[1]]
args <- get_args()




# make sure always to call status.end
options(warn = 1)
options(error = quote({
  try(PEcAn.utils::status.end("ERROR"))
  try(PEcAn.remote::kill.tunnel(settings))
  if (!interactive()) {
    q(status = 1)
  }
}))

# ----------------------------------------------------------------------
# PEcAn Workflow
# ----------------------------------------------------------------------

# Report package versions for provenance
PEcAn.all::pecan_version()

# Open and read in settings file for PEcAn run.
settings <- PEcAn.settings::read.settings(args$settings)

if (!dir.exists(settings$outdir)) {
  dir.create(settings$outdir, recursive = TRUE)
}


# start from scratch if no continue is passed in
status_file <- file.path(settings$outdir, "STATUS")
if (args$continue && file.exists(status_file)) {
  file.remove(status_file)
}


# Write model specific configs
if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <-
    PEcAn.workflow::runModule.run.write.configs(settings)
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
  settings <- PEcAn.settings::read.settings(
    file.path(settings$outdir, "pecan.CONFIGS.xml")
  )
}


# Start ecosystem model runs
if (PEcAn.utils::status.check("MODEL") == 0) {
  PEcAn.utils::status.start("MODEL")
  stop_on_error <- as.logical(settings[[c("run", "stop_on_error")]])
  if (length(stop_on_error) == 0) {
    # If we're doing an ensemble run, don't stop. If only a single run, we
    # should be stopping.
    if (is.null(settings[["ensemble"]]) ||
          as.numeric(settings[[c("ensemble", "size")]]) == 1) {
      stop_on_error <- TRUE
    } else {
      stop_on_error <- FALSE
    }
  }
  PEcAn.workflow::runModule_start_model_runs(settings,
                                             stop.on.error = stop_on_error)
  PEcAn.utils::status.end()
}

# Pecan workflow complete
if (PEcAn.utils::status.check("FINISHED") == 0) {
  PEcAn.utils::status.start("FINISHED")
  PEcAn.remote::kill.tunnel(settings)

  PEcAn.utils::status.end()
}

print("---------- PEcAn Workflow Complete ----------")
