#!/usr/bin/env Rscript

# Installing needed packages from R-Universe
options(repos = c(getOption("repos"), PEcAn = "pecanproject.r-universe.dev"))


# Installs all needed PEcAn packages and their dependencies
# TODO: If on a clean system, need to install some system libraries first
#  (e.g. libudunits2?)
# install.packages("PEcAn.all")


library("PEcAn.all")


# # ----------------------------------------------------------------------
# # Artifacts needed before running this workflow
# # Set paths here [TODO move these to XML when possible]
# # ----------------------------------------------------------------------

# # 1. Posterior file for PFT-specific model parameters
# # (running calibration to set these is a complex offline process)
# pft_input <- "path/to/pft"

# # 2. Site-specific climate driver files for SIPNET
# # (TODO finish removing database dependencies from the functions that
# # generate these on the fly)
# # This should be a single flat folder full of *.clim files;
# # the ensemble will use all of them
# met_files <- "path/to/met"

# # 3. Site-specific initial condition files
# # TODO generate more -- first few parameters implemented in ic_build.R
# ic_files <- "path/to/IC"


# --------------------------------------------------
# get command-line arguments
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
# settings$outdir <- outdir
if (!dir.exists(settings$outdir)) {
  dir.create(settings$outdir, recursive = TRUE)
}


# Standard PEcAn workflow calls update.settings() here
# Skipping because it requires a DB connection -- consider changing that,
# but we can fix XML files by hand until then
PEcAn.settings::write.settings(settings, outputfile = "pecan.CHECKED.xml")

# start from scratch if no continue is passed in
status_file <- file.path(settings$outdir, "STATUS")
if (args$continue && file.exists(status_file)) {
  file.remove(status_file)
}

# Do conversions
# settings <- PEcAn.workflow::do_conversions(settings)

# # Query the trait database for data and priors
# if (PEcAn.utils::status.check("TRAIT") == 0) {
#   PEcAn.utils::status.start("TRAIT")
#   settings <- PEcAn.workflow::runModule.get.trait.data(settings)
#   PEcAn.settings::write.settings(settings,
#     outputfile = "pecan.TRAIT.xml"
#   )
#   PEcAn.utils::status.end()
# } else if (file.exists(file.path(settings$outdir, "pecan.TRAIT.xml"))) {
#   settings <- PEcAn.settings::read.settings(file.path(settings$outdir, "pecan.TRAIT.xml"))
# }

#NO. this is secretly a calibration
# # Run the PEcAn meta.analysis
# if (!is.null(settings$meta.analysis)) {
#   if (PEcAn.utils::status.check("META") == 0) {
#     PEcAn.utils::status.start("META")
#     PEcAn.MA::runModule.run.meta.analysis(settings)
#     PEcAn.utils::status.end()
#   }
# }


# Write model specific configs
if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <-
    PEcAn.workflow::runModule.run.write.configs(settings)
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
  settings <- PEcAn.settings::read.settings(file.path(settings$outdir, "pecan.CONFIGS.xml"))
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
  PEcAn.workflow::runModule_start_model_runs(settings, stop.on.error = stop_on_error)
  PEcAn.utils::status.end()
}

# Get results of model runs
if (PEcAn.utils::status.check("OUTPUT") == 0) {
  PEcAn.utils::status.start("OUTPUT")
  runModule.get.results(settings)
  PEcAn.utils::status.end()
}

# Run ensemble analysis on model output.
if ("ensemble" %in% names(settings)
    && PEcAn.utils::status.check("ENSEMBLE") == 0) {
  PEcAn.utils::status.start("ENSEMBLE")
  runModule.run.ensemble.analysis(settings, TRUE)
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
