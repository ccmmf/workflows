#!/usr/bin/env Rscript


library("PEcAn.all")


# Get command-line arguments
# I'm overriding the usual get_args() here to add an arg for irrigation events
# This isn't a great design but seems to work for today
raw_args <- commandArgs(trailingOnly = TRUE)
if (length(raw_args) == 2) {
  stopifnot(
    raw_args[[1]] == "--settings",
    grepl(".xml$", raw_args[[2]]))
  args <- list(
    settings = raw_args[[2]],
    continue = FALSE)
} else if (length(raw_args) == 4) {
  stopifnot(
    raw_args[[1]] == "--settings",
    grepl(".xml$", raw_args[[2]]),
    raw_args[[3]] == "--event_dir",
    dir.exists(raw_args[[4]]))
  args <- list(
    settings = raw_args[[2]],
    event_dir = raw_args[[4]],
    continue = FALSE)
} else {
  stop("Bad script arguments")
}


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

# Copy event files into rundirs
if (!is.null(args$event_dir)) {
  event_path <- function(id) {
    file.path(
      args$event_dir,
      paste0("irrigation_eventfile_", id, ".txt"))
  }
} else {
  event_path <- function(id) "data/sipnet.event"
}
site_ids <- sapply(settings, \(x) x$run$site$id)
purrr::walk(
  site_ids,
  \(id) {
    from_path <- event_path(id)
    to_paths <- list.files(path = settings$rundir, pattern = id, full.names = TRUE)
    file.copy(from = from_path, to = file.path(to_paths, "events.in"))
  }
)

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
                                             # stop.on.error = stop_on_error)
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

# Pecan workflow complete
if (PEcAn.utils::status.check("FINISHED") == 0) {
  PEcAn.utils::status.start("FINISHED")
  PEcAn.remote::kill.tunnel(settings)

  PEcAn.utils::status.end()
}

print("---------- PEcAn Workflow Complete ----------")
