#!/usr/bin/env Rscript


# Installs all needed PEcAn packages and their dependencies,
# pulling from a combination of CRAN and R-Universe.
# TODO: If on a clean system, need to install some system libraries first
#  (e.g. libudunits2?)

library("PEcAn.utils")
library("PEcAn.remote")
library("PEcAn.settings")
library("PEcAn.workflow")
library("PEcAn.logger")
library("PEcAn.uncertainty")

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

# Open and read in settings file for PEcAn run.
settings <- PEcAn.settings::read.settings(args$settings)



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
# PEcAn.all::pecan_version()

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
  PEcAn.logger::logger.setUseConsole(TRUE)
  PEcAn.logger::logger.setLevel("ALL")
  PEcAn.workflow::runModule_start_model_runs(settings,
                                             stop.on.error = stop_on_error)
  PEcAn.utils::status.end()
}

# Get results of model runs
if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  PEcAn.uncertainty::runModule.get.results(settings)
  PEcAn.utils::status.end()
}

# Run ensemble analysis on model output.
if ("ensemble" %in% names(settings)
    && PEcAn.utils::status.check("ENSEMBLE") == 0) {
  PEcAn.utils::status.start("ENSEMBLE")
  PEcAn.uncertainty::runModule.run.ensemble.analysis(settings, TRUE)
  PEcAn.utils::status.end()
}

# Run sensitivity analysis and variance decomposition on model output
if ("sensitivity.analysis" %in% names(settings)
    && PEcAn.utils::status.check("SENSITIVITY") == 0) {
  PEcAn.utils::status.start("SENSITIVITY")
  PEcAn.uncertainty::runModule.run.sensitivity.analysis(settings)
  PEcAn.utils::status.end()
}


# Pecan workflow complete
if (PEcAn.utils::status.check("FINISHED") == 0) {
  PEcAn.utils::status.start("FINISHED")
  PEcAn.remote::kill.tunnel(settings)

  # Send email if configured
  if (!is.null(settings$email)
      && !is.null(settings$email$to)
      && (settings$email$to != "")) {
    sendmail(
      settings$email$from,
      settings$email$to,
      paste0("Workflow has finished executing at ", base::date()),
      paste0("You can find the results on ", settings$email$url)
    )
  }
  PEcAn.utils::status.end()
}

print("---------- PEcAn Workflow Complete ----------")
