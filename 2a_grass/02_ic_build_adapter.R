#!/usr/bin/env Rscript

# Standalone command-line adapter for build_ic_files function from workflow_functions.R
# This script sources workflow_functions.R, parses command-line arguments using the
# exact same argument parsing as the original 02_ic_build.R, and builds an in-memory
# XML structure to pass into the workflow_functions.R version of build_ic_files.

# Source the workflow functions
source("../tools/workflow_functions.R")

# Argument parsing section (exact copy from 02_ic_build.R)
options <- list(
  optparse::make_option("--site_info_path",
    default = "site_info.csv",
    help = "CSV giving ids, locations, and PFTs for sites of interest"
  ),
  optparse::make_option("--field_shape_path",
    default = "data_raw/dwr_map/i15_Crop_Mapping_2018.gdb",
    help = "file containing site geometries, used for extraction from rasters"
  ),
  optparse::make_option("--ic_ensemble_size",
    default = 100,
    help = "number of files to generate for each site"
  ),
  optparse::make_option("--run_start_date",
    default = "2016-01-01",
    help = paste(
      "Date to begin simulations.",
      "For now, start date must be same for all sites,",
      "and some download/extraction functions rely on this.",
      "Workaround: Call this script separately for sites whose dates differ"
    )
  ),
  optparse::make_option("--run_LAI_date",
    default = "2016-07-01",
    help = "Date to look near (up to 30 days each direction) for initial LAI"
  ),
  optparse::make_option("--ic_outdir",
    default = "IC_files",
    help = "Directory to write completed initial conditions as nc files"
  ),
  optparse::make_option("--data_dir",
    default = "data/IC_prep",
    help = "Directory to store data retrieved/computed in the IC build process"
  ),
  optparse::make_option("--pft_dir",
    default = "pfts",
    help = paste(
      "path to parameter distributions used for PFT-specific conversions",
      "from LAI to estimated leaf carbon.",
      "Must be path to a dir whose child subdirectory names match the",
      "`site.pft` column of site_info and that contain a file",
      "`post.distns.Rdata`"
    )
  ),
  optparse::make_option("--params_read_from_pft",
    default = "SLA,leafC", # SLA units are m2/kg, leafC units are %
    help = "Parameters to read from the PFT file, comma separated"
  ),
  optparse::make_option("--landtrendr_raw_files",
    default = paste0(
      "data_raw/ca_biomassfiaald_2016_median.tif,",
      "data_raw/ca_biomassfiaald_2016_stdv.tif"
    ),
    help = paste(
      "Paths to two geotiffs, with a comma between them.",
      "These should contain means and standard deviations of aboveground",
      "biomass on the start date.",
      "We used Landtrendr-based values from the Kennedy group at Oregon State,",
      "which require manual download.",
      "Medians are available by anonymous FTP at islay.ceoas.oregonstate.edu",
      "and by web (but possibly this is a different version?) from",
      "https://emapr.ceoas.oregonstate.edu/pages/data/viz/index.html",
      "The uncertainty layer was formerly distributed by FTP but I cannot find",
      "it on the ceoas server at the moment.",
      "TODO find out whether this is available from a supported source.",
      "",
      "Demo used a subset (year 2016 clipped to the CA state boundaries)",
      "of the 30-m CONUS median and stdev maps that are stored on the Dietze",
      "lab server"
    )
  ),
  optparse::make_option("--additional_params",
    # Wood C fraction isn't in these PFTs, so just using my estimate.
    # TODO update from a citeable source,
    # and consider adding to PFT when calibrating
    default =
      "varname=wood_carbon_fraction,distn=norm,parama=0.48,paramb=0.005",
    help = paste(
      "Further params not available from site or PFT data,",
      "as a comma-separated named list with names `varname`, `distn`,",
      "`parama`, and `paramb`. Currently used only for `wood_carbon_fraction`"
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

## ---------------------------------------------------------
# Build in-memory XML structure to pass to build_ic_files
# This mimics the structure that would come from parsing workflow.create.clim.files
# section of the orchestration XML

orchestration_xml <- list(
  site.info.file = args$site_info_path,
  field.shape.path = args$field_shape_path,
  ic.ensemble.size = as.character(args$ic_ensemble_size),
  start.date = args$run_start_date,
  run_LAI.date = args$run_LAI_date,
  ic.outdir = args$ic_outdir,
  data.dir = args$data_dir,
  pft.dir = args$pft_dir,
  params.from.pft = args$params_read_from_pft,
  landtrendr.raw.files = args$landtrendr_raw_files,
  additional.params = args$additional_params
)

## ---------------------------------------------------------
# Call the build_ic_files function from workflow_functions.R
build_ic_files(orchestration_xml = orchestration_xml)

