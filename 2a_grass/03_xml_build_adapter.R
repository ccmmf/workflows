#!/usr/bin/env Rscript

# Standalone command-line adapter for build_pecan_xml function from workflow_functions.R
# This script sources workflow_functions.R, parses command-line arguments using the
# exact same argument parsing as the original 03_xml_build.R, and builds an in-memory
# XML structure to pass into the workflow_functions.R version.

# Source the workflow functions
source("../tools/workflow_functions.R")

# Argument parsing section (exact copy from 03_xml_build.R)
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

## ---------------------------------------------------------
# Build in-memory XML structure to pass to build_pecan_xml
# This mimics the structure that would come from parsing workflow.build.xml
# section of the orchestration XML

orchestration_xml <- list(
  site.info.file = args$site_file,
  n.ens = as.character(args$n_ens),
  n.met = as.character(args$n_met),
  start.date = args$start_date,
  end.date = args$end_date,
  ic.dir = args$ic_dir,
  met.dir = args$met_dir,
  output.xml = args$output_file
)

## ---------------------------------------------------------
# Call the build_pecan_xml function from workflow_functions.R
build_pecan_xml(
  orchestration_xml = orchestration_xml,
  template_file = args$template_file
)

