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
  settings = settings[[1]],
  ensemble_size = settings$ensemble$size
)
write.csv(ens_design$X, file.path(settings$outdir, "input_design.csv"))

# Temporary hack:
# generate_joint_ensemble_design used to write samples.Rdata as a side effect,
# but recently changed to include the samples in its return value instead.
# Passing these directly to runModule.run.write.configs and
# write_segmented_configs is still to be implemented on the PEcAn side;
# meanwhile we write them back out to disk (which is handy for post-run
# provenance too).
sample_env <- list2env(ens_design$samples)
save(
  list = ls(sample_env),
  envir = sample_env,
  file = file.path(settings$outdir, "samples.Rdata")
)

settings$ensemble$id <- rlang::hash(ens_design)
PEcAn.utils::status.end()

# Write model specific configs
if (PEcAn.utils::status.check("CONFIG") == 0) {
  PEcAn.utils::status.start("CONFIG")
  settings <- PEcAn.workflow::runModule.run.write.configs(
    settings,
    input_design = ens_design$X
  )
  PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
  PEcAn.utils::status.end()
}

PEcAn.utils::status.start("CONFIG_SEGMENTS")
run_script_paths <- papply(
  settings,
  \(s) PEcAn.SIPNET::write_segmented_configs.SIPNET(s, ens_design$X)
)
PEcAn.utils::status.end()
