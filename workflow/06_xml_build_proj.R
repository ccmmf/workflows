#!/usr/bin/env Rscript

library(PEcAn.settings)

# Construct one multisite PEcAn XML file for statewide simulations

## Config section -- edit for your project
options <- list(
  optparse::make_option("--n_ens",
    default = 20,
    help = "number of ensemble simulations per site"
  ),
  optparse::make_option("--start_date",
    default = "2016-01-01",
    help = paste(
      "Date to begin simulations.",
      "Ensure your IC files are valid for this date"
    )
  ),
  optparse::make_option("--end_date",
    default = "2023-12-31",
    help = "Date to end simulations"
  ),
  optparse::make_option("--ic_dir",
    default = "data/IC_files",
    help = paste(
      "Directory containing initial conditions.",
      "Should contain subdirs named by site id"
    )
  ),
  optparse::make_option("--n_ic",
    default = 100,
    help = "number of initial condition files available (ensemble will sample from all)"
  ),
  optparse::make_option("--met_dir",
    default = "data/ERA5_CA_SIPNET",
    help = paste(
      "Directory containing climate data.",
      "Should contain subdirs named by grid cell (eg '32.5N_114.5W')"
    )
  ),
  optparse::make_option("--n_met",
    default = 10,
    help = "number of met files available (ensemble will sample from all)"
  ),
  optparse::make_option("--models",
    default = paste0(
      "CESM2,CNRM-ESM2-1,EC-Earth3,EC-Earth3-Veg,",
      "FGOALS-g3,MIROC6,MPI-ESM1-2-HR,TaiESM1"
    ),
    help = paste(
      "Comma-separated list of GCMs to convert.",
      "See `caladaptaer::cae_models(\"WRF\")` for valid names."
    )
  ),
  optparse::make_option("--scenario",
    default = "ssp370",
    help = paste(
      "Climate scenario. See `caladaptaer::cae_scenarios(\"WRF\")`",
      "for valid values."
    )
  ),
  optparse::make_option("--event_dir",
    default = "data/events",
    help = paste(
      "Directory containing Sipnet `events.in` files.",
      "Should contain subdirs named by site id"
    )
  ),
    optparse::make_option("--n_event",
    default = 20,
    help = "number of event files available (ensemble will sample from all)"
  ),
  optparse::make_option("--pft_dir",
    default = "data_raw/pfts",
    help = paste(
      "Directory containing PFT definitions.",
      "Should contain subdirs whose names match the values in the 'site.pft'",
      "column of the site file.",
      "The <pfts> block of the output will contain one entry for each subdir."
    )
  ),
  optparse::make_option("--site_file",
    default = "site_info.csv",
    help = paste(
      "CSV file containing one row for each site to be simulated.",
      "Must contain at least columns `id`, `lat`, `lon`, and `site.pft`.",
      "Values in `site.pft` must be PFT names that appear in pft_dir"
    )
  ),
  optparse::make_option("--template_file",
    default = "template.xml",
    help = paste(
      "XML file containing whole-run settings,",
      "Will be expanded to contain all sites at requested ensemble size"
    )
  ),
  optparse::make_option("--sipnet_parameter_file",
    default = "sipnet.default.param",
    help = paste(
      "Sipnet parameter file to be used as defaults for any model parameter",
      "not set by parameter sampling or initial conditions.",
      "Should be in the same format as",
      "`system.file(\"template.param_v2\", package = \"PEcAn.SIPNET\')`."
    )
  ),
  optparse::make_option("--output_file",
    default = "settings.xml",
    help = "path to write output XML"
  ),
  optparse::make_option("--output_dir",
    default = "ensemble_output",
    help = paste(
      "Path the settings should declare as output directory.",
      "This will be inserted replacing [out] in all of the following places:",
      "`outdir` = [out] ; `modeloutdir` = [out]/out; `rundir` = [out]/run;",
      "`host$outdir`: [out]/out; `host$rundir`: [out]/run."
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


## End config section
## Whew, that was a lot of lines to define a few defaults!


# papply emits a lot of uninformative debug messages; let's ignore those
PEcAn.logger::logger.setLevel("INFO")

models <- strsplit(args$models, ",")[[1]] |>
  trimws()
stopifnot(length(models) == args$n_met)

site_info <- read.csv(args$site_file)
stopifnot(
  length(unique(site_info$id)) == nrow(site_info))

settings <- read.settings(args$template_file) |>
  setDates(args$start_date, args$end_date)

# Attempt to convert to absolute paths, because the restart code changes
# working directory and gets confused by relative paths
# Q: "But why the getwd()? Won't normalizePath expand it for you?"
# A: Only for existing paths; dirs not yet created need the getwd. Humph.
abs_path <- function(path) {
  if (substr(path, 1, 1) != "/") path <- file.path(getwd(), path)
  normalizePath(path, mustWork = FALSE)
}
args$ic_dir <- abs_path(args$ic_dir)
args$met_dir <- abs_path(args$met_dir)
args$event_dir <- abs_path(args$event_dir)
args$output_dir <- abs_path(args$output_dir)
# PFT posterior.files is deliberately left relative (as workflow/03_xml_build.R
# and the other examples do): it's only resolved later, inside
# workflow/04_set_up_runs.R during run-ensembles, which magic-ensemble invokes
# with CWD=run_dir. Eagerly absolutizing it here (a prepare step, CWD=REPO_ROOT)
# baked a wrong path into settings.xml.
settings$model$binary <- abs_path(settings$model$binary)

settings$ensemble$size <- args$n_ens
settings$run$inputs$poolinitcond$ensemble <- args$n_ens
# TODO do we need to set settings$run$inputs$events$ensemble too?


add_soil_pft <- function(s) {
  s$run$site$site.pft <- list(veg = s$run$site$site.pft, soil = "soil")
  s
}

settings <- settings |>
  createMultiSiteSettings(site_info) |>
  setEnsemblePaths(
    n_reps = args$n_met,
    input_type = "met",
    path = args$met_dir,
    d1 = args$start_date,
    d2 = args$end_date,
    model = models,
    scenario = args$scenario,
    path_template = "{path}/{WRF_grid_cell}/{model}.{scenario}.{d1}.{d2}.clim"
  ) |>
  # setEnsemblePaths(
  #   n_reps = args$n_ic,
  #   input_type = "poolinitcond",
  #   path = args$ic_dir,
  #   path_template = "{path}/{id}/IC_site_{id}_{n}.nc"
  # ) |>
  papply(\(s) {s$run$inputs$poolinitcond <- NULL; s}) |>
  setEnsemblePaths(
    n_reps = sprintf("%03d", seq_len(args$n_event)), # yes, n_reps secretly accepts a vector!
    input_type = "events",
    path = args$event_dir,
    path_template = "{path}/ens_{n}/events-{id}.in"
  ) |>
  setEnsemblePaths(
    n_reps = sprintf("%03d", seq_len(args$n_event)),
    input_type = "crop_changes",
    path = args$event_dir,
    path_template = "{path}/ens_{n}/cycles-{id}.csv"
  ) |>
  papply(add_soil_pft)

# Update output directories
# Note that we're assuming local and remote paths are the same.
settings$outdir <- args$output_dir
settings$modeloutdir <- file.path(args$output_dir, "out")
settings$rundir <- file.path(args$output_dir, "run")
settings$host$outdir <- file.path(args$output_dir, "out")
settings$host$rundir <- file.path(args$output_dir, "run")

# Hack: drop IC from inputs section
# (possible we could instead do one of
# - maintain a projections template with no IC provided
# - leave all IC machinery in place but quietly overwritten by restart.out
# - ???
settings$ensemble$samplingspace$poolinitcond <- NULL

# Populate PFT section
# Makes several key assumptions:
# 1. All subdirs of pft_dir are named with their pft's name
#  (i.e. pft_dir/baz/post.distns.Rdata is for a pft named "baz").
# 2. User wants all PFTs in pft_dir to be inserted into settings.xml
# 3. pft dir already exists on disk (unlike input paths that are constructed
#   without checking)
# 4. Posterior priority: trait.mcmc > post.distns > error
find_posterior <- function(dir) {
  if (file.exists(file.path(dir, "trait.mcmc.Rdata"))) {
    return(file.path(dir, "trait.mcmc.Rdata"))
  } else if (file.exists(file.path(dir, "post.distns.Rdata"))) {
    return(file.path(dir, "post.distns.Rdata"))
  } else {
    PEcAn.logger::logger.severe(
      "Don't know what posterior to use for pft", sQuote(dir)
    )
  }
}
build_pft_entry <- function(name) {
  list(
    name = name,
    posterior.files = find_posterior(file.path(args$pft_dir, name))
  )
}
pft_names <- list.dirs(args$pft_dir, full.names = FALSE, recursive = FALSE)
pft_list <- lapply(pft_names, build_pft_entry) |>
  # Yes, PEcAn expects a pft list with each entry named `<pft>`.
  # No, I don't like it, but am not going to try to change that today.
  setNames(nm = rep("pft", length(pft_names)))
settings$pfts <- pft_list

# not yet sure this is sufficient for segmented runs...
settings$model$options$RESTART_IN <- "restart.in"

settings$model$default.param <- args$sipnet_parameter_file

write.settings(
  settings,
  outputfile = basename(args$output_file),
  outputdir = dirname(args$output_file)
)
