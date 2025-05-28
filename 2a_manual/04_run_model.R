#!/usr/bin/env Rscript


library("PEcAn.all")


# --------------------------------------------------
# Run-time parameters
# TODO PEcAn's standard workflow.R reads these from the command line
# using PEcAn.settings::get_args();
# can go back to that if it turns out we often want to change them often,
# but for now hard-coding seems simpler.
#
# `settings`: path to the XML settings file you want to use for this run.
#   Be aware all paths are interpreted relative to the working directory of the
#   process that invokes run_model.R, not relative to the settings file path.
#
# `continue`: logical value intended to allow picking up in the middle of a
#   previously started-and-interrupted workflow.
#   Does not work reliably. Use at your own risk.
args <- list(
  settings = "settings.xml",
  continue = FALSE
)




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
  # PEcAn.workflow::runModule_start_model_runs(settings,
  #                                            stop.on.error = stop_on_error)
  n_jobs <- 8 # TODO SET SOMEWHERE EDITABLE
  run_path <- settings$host$rundir
  system2(
    "parallel",
    args = c(
      "-j", n_jobs,
      file.path(run_path, "{}", "job.sh"),
      "::::", file.path(run_path, "runs.txt")
    )
  )
  PEcAn.utils::status.end()
}


# Run sensitivity analysis and variance decomposition on model output
if ("sensitivity.analysis" %in% names(settings)
&& PEcAn.utils::status.check("SENSITIVITY") == 0) {
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
