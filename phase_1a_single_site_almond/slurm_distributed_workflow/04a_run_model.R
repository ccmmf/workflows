#!/usr/bin/env Rscript


# Installs all needed PEcAn packages and their dependencies,
# pulling from a combination of CRAN and R-Universe.
# TODO: If on a clean system, need to install some system libraries first
#  (e.g. libudunits2?)
print("Hello world!")
# if (!requireNamespace("PEcAn.all", quietly = TRUE)) {
#  print("Oh yes, lets get alllll hacky")
#  options(repos = c(getOption("repos"), PEcAn = "pecanproject.r-universe.dev"))
#  print("Hack again?")
#  install.packages("PEcAn.all")
#}

print("loading pecan....")
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
# PEcAn.all::pecan_version()

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
  print("I think i'll see this.")
  settings <-
    PEcAn.workflow::runModule.run.write.configs(settings)
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
} else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
  settings <- PEcAn.settings::read.settings(
    file.path(settings$outdir, "pecan.CONFIGS.xml")
  )
}
print("done with configs.")
