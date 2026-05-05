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
  ),
  optparse::make_option(c("-r", "--restart_code_location"),
    default = "~/pecan/workflows/sipnet-restart-workflow/utils.R",
    help = paste(
      "File containing R functions implementing crop changes via restart.",
      "Will be source()'d into the R session.",
      "This is a temporary option until restart functions are refactored into",
      "package code"
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
PEcAn.logger::logger.setLevel("WARN")

PEcAn.utils::status.start("DESIGN")
ens_design <- PEcAn.uncertainty::generate_joint_ensemble_design(
  settings[[1]],
  settings$ensemble$size
)$X
write.csv(ens_design, file.path(settings$outdir, "input_design.csv"))
settings$ensemble$id <- rlang::hash(ens_design)
PEcAn.utils::status.end()

# Write model specific configs
if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <- PEcAn.workflow::runModule.run.write.configs(
    settings,
    input_design = ens_design
  )
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
}

PEcAn.utils::status.start("CONFIG_SEGMENTS")
source(args$restart_code_location)
papply(settings, \(s) write_segmented_configs.SIPNET(s, ens_design))
PEcAn.utils::status.end()
