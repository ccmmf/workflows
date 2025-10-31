#!/usr/bin/env Rscript

# --------------------------------------------------
# Run-time parameters

options <- list(
  optparse::make_option(c("-s", "--settings"),
    default = "settings.xml",
    help = paste(
      "path to the XML settings file you want to use for this run.",
      "Be aware all paths inside the file are interpreted relative to the",
      "working directory of the process that invokes run_model.R,",
      "not relative to the settings file path"
    )
  ),
  optparse::make_option(c("-c", "--continue"),
    default = FALSE,
    help = paste(
      "Attempt to pick up in the middle of a previously interrupted workflow?",
      "Does not work reliably. Use at your own risk"
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

library("PEcAn.all")


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
  settings <- PEcAn.workflow::runModule.run.write.configs(settings)
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


# Get results of model runs
# this function is arguably too chatty, so we'll suppress
# INFO-level log output for this step.
loglevel <- PEcAn.logger::logger.setLevel("WARN")
if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  runModule.get.results(settings)
  PEcAn.utils::status.end()
}
PEcAn.logger::logger.setLevel(loglevel)


# Run ensemble analysis on model output.
# if ("ensemble" %in% names(settings)
# && PEcAn.utils::status.check("ENSEMBLE") == 0) {
#   PEcAn.utils::status.start("ENSEMBLE")
#   runModule.run.ensemble.analysis(settings, TRUE)
#   PEcAn.utils::status.end()
# }


# Run sensitivity analysis and variance decomposition on model output
if ("sensitivity.analysis" %in% names(settings) &&
      PEcAn.utils::status.check("SENSITIVITY") == 0) {
  PEcAn.utils::status.start("SENSITIVITY")
  runModule.run.sensitivity.analysis(settings)
  PEcAn.utils::status.end()
}

# Pecan workflow complete
if (PEcAn.utils::status.check("FINISHED") == 0) {
  PEcAn.utils::status.start("FINISHED")
  PEcAn.remote::kill.tunnel(settings)

  PEcAn.utils::status.end()
}

print("---------- PEcAn Workflow Complete ----------")
