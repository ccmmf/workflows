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

settings$ensemble$size <- args$n_ens
settings$run$inputs$poolinitcond$ensemble <- args$n_ens

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
  )

# Hack: Work around a regression in PEcAn.uncertainty 1.8.2 by specifying
# PFT outdirs explicitly (even though they go unused in this workflow)
settings$pfts <- settings$pfts |>
  lapply(\(x) {
    x$outdir <- file.path(settings$outdir, "pfts", x$name)
    x
  })

write.settings(
  settings,
  outputfile = basename(args$output_file),
  outputdir = dirname(args$output_file)
)
