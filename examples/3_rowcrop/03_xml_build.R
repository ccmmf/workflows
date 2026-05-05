#!/usr/bin/env Rscript

library(PEcAn.settings)

# Construct one multisite PEcAn XML file for statewide simulations

## Config section -- edit for your project
options <- list(
  optparse::make_option("--n_ens",
    default = 20,
    help = "number of ensemble simulations per site"
  ),
  optparse::make_option("--n_met",
    default = 10,
    help = "number of met files available (ensemble will sample from all)"
  ),
  optparse::make_option("--start_date",
    default = "2016-01-01",
    help = paste(
      "Date to begin simulations.",
      "Ensure your IC files are valid for this date"
    )
  ),
  optparse::make_option("--end_date",
    default = "2024-12-31",
    help = "Date to end simulations"
  ),
  optparse::make_option("--ic_dir",
    default = "IC_files",
    help = paste(
      "Directory containing initial conditions.",
      "Should contain subdirs named by site id"
    )
  ),
  optparse::make_option("--met_dir",
    default = "data/ERA5_CA_SIPNET",
    help = paste(
      "Directory containing climate data.",
      "Should contain subdirs named by site id"
    )
  ),
  optparse::make_option("--event_dir",
    default = "data/events",
    help = paste(
      "Directory containing Sipnet `events.in` files.",
      "Should contain subdirs named by site id"
    )
  ),
  optparse::make_option("--site_file",
    default = "site_info.csv",
    help = paste(
      "CSV file containing one row for each site to be simulated.",
      "Must contain at least columns `id`, `lat`, `lon`, and `site.pft`"
    )
  ),
  optparse::make_option("--template_file",
    default = "template.xml",
    help = paste(
      "XML file containing whole-run settings,",
      "Will be expanded to contain all sites at requested ensemble size"
    )
  ),
  optparse::make_option("--output_file",
    default = "settings.xml",
    help = "path to write output XML"
  ),
  optparse::make_option("--output_dir",
    default = "output",
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



site_info <- read.csv(args$site_file)
stopifnot(
  length(unique(site_info$id)) == nrow(site_info),
  all(site_info$lat > 0), # just to simplify grid naming below
  all(site_info$lon < 0)
)
site_info <- site_info |>
  dplyr::mutate(
    # match locations to half-degree ERA5 grid cell centers
    # CAUTION: Calculation only correct when all lats are N and all lons are W!
    ERA5_grid_cell = paste0(
      ((lat + 0.25) %/% 0.5) * 0.5, "N_",
      ((abs(lon) + 0.25) %/% 0.5) * 0.5, "W"
    )
  )

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
# TODO it's awkward to set PFT paths in the template but then edit them here --
# consider handling PFT insertion as an arg here?
for(i in seq_along(settings$pfts)) {
  settings$pfts[[i]]$posterior.files <- abs_path(
    settings$pfts[[i]]$posterior.files
  )
}
settings$model$binary <- abs_path(settings$model$binary)

settings$ensemble$size <- args$n_ens
settings$run$inputs$poolinitcond$ensemble <- args$n_ens
# TODO do we need to set settings$run$inputs$events$ensemble too?

# Hack: setEnsemblePaths leaves all path components other than siteid
# identical across sites.
# To use site-specific grid id, I'll string-replace each siteid
id2grid <- function(s) {
  # replacing in place to preserve names (easier than thinking)
  for (p in seq_along(s$run$inputs$met$path)) {
    s$run$inputs$met$path[[p]] <- gsub(
      pattern = s$run$site$id,
      replacement = s$run$site$ERA5_grid_cell,
      x = s$run$inputs$met$path[[p]]
    )
  }
  s
}

add_soil_pft <- function(s) {
  s$run$site$site.pft <- list(veg = s$run$site$site.pft, soil = "soil")
  s
}

# The restart functions use this to find the crop type for each planting event
add_event_source <- function(s) {
  s$run$inputs$events$source <- file.path(args$event_dir, "combined_events.json")
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
    # TODO use caladapt when ready
    # path_template = "{path}/{id}/caladapt.{id}.{n}.{d1}.{d2}.nc"
    path_template = "{path}/{id}/ERA5.{n}.{d1}.{d2}.clim"
  ) |>
  papply(id2grid) |>
  setEnsemblePaths(
    n_reps = args$n_ens,
    input_type = "poolinitcond",
    path = args$ic_dir,
    path_template = "{path}/{id}/IC_site_{id}_{n}.nc"
  ) |>
  setEnsemblePaths(
    n_reps = args$n_ens,
    input_type = "events",
    path = args$event_dir,
    path_template = "{path}/events-{id}.in"
  ) |>
  papply(add_event_source) |>
  # For now, hard-coding one phenology path for all sites, placed inside event dir
  # TODO make settable?
  setEnsemblePaths(
    n_reps = args$n_ens,
    input_type = "leaf_phenology",
    path = args$event_dir,
    path_template = "{path}/phenology.csv"
  ) |>
  papply(add_soil_pft)

# Update output directories
# Note that we're assuming local and remote paths are the same.
settings$outdir <- args$output_dir
settings$modeloutdir <- file.path(args$output_dir, "out")
settings$rundir <- file.path(args$output_dir, "run")
settings$host$outdir <- file.path(args$output_dir, "out")
settings$host$rundir <- file.path(args$output_dir, "run")

write.settings(
  settings,
  outputfile = basename(args$output_file),
  outputdir = dirname(args$output_file)
)
