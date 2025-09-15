library(targets)
library(tarchetypes)
library(PEcAn.all)


get_workflow_args <- function() {
  option_list <- list(
    optparse::make_option(
      c("-d", "--data_source_run_id"),
      default = NULL,
      type = "character",
      help = "RunID of the data source - must already exist",
    ),
    optparse::make_option(
      c("-a", "--analysis_run_id"),
      default = NULL,
      type = "character",
      help = "Run ID of this analysis workflow - optional",
    )
  )

  parser <- optparse::OptionParser(option_list = option_list)
  args <- optparse::parse_args(parser)

  return(args)
}

args = get_workflow_args()

#### run directory specification ####
# note: if this_run_directory exists already, and we specify the _targets script within it, targets will evaluate the pipeline already run
# if the pipeline has not changed, the pipeline will not run. This extends to the targeted functions, their arguments, and their arguments values. 
# thus, as long as the components of the pipeline run are kept in the functions, the data entities, and the arguments, we can have smart re-evaluation.
workflow_run_directory = file.path("./workflow_runs")
if (!dir.exists(workflow_run_directory)) {
    dir.create(workflow_run_directory, recursive = TRUE)
} 
workflow_run_directory = normalizePath(workflow_run_directory)

if (is.null(args$data_source_run_id)) {
    stop("Data source run id is required")
} else {
    print(paste("Data Run id specified:", args$data_source_run_id))
    data_source_run_id = args$data_source_run_id
}

analysis_run_id = paste0("analysis_run_", uuid::UUIDgenerate() )
if (is.null(args$analysis_run_id)) {
    print(paste("Analysis run id specified:", analysis_run_id))
} else {
    print(paste("Analysis run id specified:", args$analysis_run_id))
    analysis_run_id = args$analysis_run_id
}


this_data_source_directory = file.path(workflow_run_directory, data_source_run_id)
if (!dir.exists(this_data_source_directory)) {
  stop("Data source run directory does not exist")
} 

analysis_run_directory = file.path(workflow_run_directory, analysis_run_id)
if (!dir.exists(analysis_run_directory)) {
  dir.create(analysis_run_directory, recursive = TRUE)
}

# note: this allows the functions and code supporting this run to be switchable: I.e., we can do A/B testing on the code state.
function_path = normalizePath(file.path("../tools/workflow_functions.R"))

# variables specific to this pipeline iteration
pecan_xml_path = normalizePath(file.path("single_site_almond.xml"))

print(paste("Starting workflow run in directory:", analysis_run_directory))
setwd(analysis_run_directory)
tar_config_set(store = "./")
analysis_tar_script_path = file.path("./executed_pipeline.R")
tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)

  pecan_xml_path = "@PECANXML@"
  workflow_data_source = "@WORKFLOWDATASOURCE@"
  tar_source("@FUNCTIONPATH@")
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr"),
    imports = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow")
  )
  list(
    # Config XML and source data handling
    # obviously, if at any time we need to alter the content of the reference data, we're going to need to do more than link to it.
    # doesn't copy anything; also doesn't check content - if the content of the source is changed, this is unaware.
    tar_target(reference_IC_directory, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="IC_files", localized_name="IC_files")),
    tar_target(reference_data_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="data", localized_name="data")),
    tar_target(reference_pft_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="pfts", localized_name="pfts")),
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    # 
    # Prep run directory, read settings, get everything ready
    tar_target(pecan_settings, read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),
    #
    # check for continue; then write configs
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)), 
    tar_target(pecan_settings_configs, pecan_write_configs(pecan_settings=pecan_settings_prepared))
  )
}, ask = FALSE, script = analysis_tar_script_path)

script_content <- readLines(analysis_tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", function_path, script_content)
script_content <- gsub("@PECANXML@", pecan_xml_path, script_content)
script_content <- gsub("@WORKFLOWDATASOURCE@", this_data_source_directory, script_content)

writeLines(script_content, analysis_tar_script_path)

tar_make(script = analysis_tar_script_path)



