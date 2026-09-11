#!/usr/bin/env Rscript

# Retrieves the samples.Rdata from a previous run,
# performs some basic compatibility checks (mostly for matching ensemble size),
# copies it to a new run directory to be found by a future PEcAn workflow.

options <- list(
  optparse::make_option("--prev_run_dir",
    default = "../prev_output/",
    # Q: Why a directory and not the full path to the file?
    # A: So we don't need separate manifest keys for this and copy_restarts.R
    # This might be the wrong tradeoff, though?
    help = "Path to a PEcAn output directory with a `samples.Rdata` file in it"
  ),
  optparse::make_option("--new_run_dir",
    default = "output",
    help = paste(
      "Output path:",
      "A new run directory into which restarts should be copied."
    )
  ),
  optparse::make_option("--settings",
    default = "settings.xml",
    help = "The PEcAn settings file that will be used for the new run"
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()


settings <- PEcAn.settings::read.settings(args$settings)
setting_pfts <- settings$pfts |>
  purrr::map_chr("name")
setting_n_ens <- settings$ensemble$size

prev_samp_file <- file.path(args$prev_run_dir, "samples.Rdata")
samps <- PEcAn.utils::load_local(prev_samp_file)
sample_pfts <- samps$ensemble.samples[[1]] |>
  names() |>
  sort()
sample_n_ens <- samps$ensemble.samples[[1]] |>
  purrr::map_int(nrow) |>
  unique()

stopifnot(
  all(setting_pfts %in% sample_pfts),
  length(sample_n_ens) == 1,
  sample_n_ens == setting_n_ens
)


if (!dir.exists(args$new_run_dir)) {
  dir.create(args$new_run_dir, recursive = TRUE)
}

samp_ok <- file.copy(
  prev_samp_file,
  file.path(args$new_run_dir, "samples.Rdata"),
  overwrite = TRUE
)
if (!samp_ok) {
  PEcAn.logger::logger.error(
    "Could not copy sample file from previous run",
    file.path(args$prev_run_dir, "samples.Rdata")
  )
}
