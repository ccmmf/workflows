library(targets)
library(tarchetypes)
library(PEcAn.settings)

get_workflow_args <- function() {
  option_list <- list(
    optparse::make_option(
      c("-s", "--settings"),
      default = NULL,
      type = "character",
      help = "Workflow & Pecan configuration XML",
    )
  )

  parser <- optparse::OptionParser(option_list = option_list)
  args <- optparse::parse_args(parser)

  return(args)
}

args <- get_workflow_args()

if (is.null(args$settings)) {
  stop("An Orchestration settings XML must be provided via --settings.")
}


workflow_name = "workflow.reference.02"

#### Primary workflow settings parsing ####

settings_path = normalizePath(file.path(args$settings))
settings = XML::xmlToList(XML::xmlParse(args$settings))

workflow_function_source = file.path(settings$orchestration$functions.source)
workflow_function_path = normalizePath(workflow_function_source)
source(workflow_function_source)

# hopefully can find a more elegant way to do this
pecan_config_path = normalizePath(file.path(settings$orchestration[[workflow_name]]$pecan.xml.path))

ret_obj <- workflow_run_directory_setup(orchestration_settings=settings, workflow_name=workflow_name)

analysis_run_directory = ret_obj$run_dir
run_id = ret_obj$run_id

message(sprintf("Starting workflow run '%s' in directory: %s", run_id, analysis_run_directory))

setwd(analysis_run_directory)
tar_config_set(store = "./")
tar_script_path <- file.path("./executed_pipeline.R")

#### Pipeline definition ####
tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)

  function_sourcefile = "@FUNCTIONPATH@"
  workflow_name = "@WORKFLOWNAME@"
  pecan_xml_path = "@PECANXMLPATH@"
  tar_source(function_sourcefile)
  orchestration_settings = parse_orchestration_xml("@ORCHESTRATIONXML@")
  
  workflow_settings = orchestration_settings$orchestration[[workflow_name]]
  base_workflow_directory = orchestration_settings$orchestration$workflow.base.run.directory
  if (is.null(workflow_settings)) {
    stop(sprintf("Workflow settings for '%s' not found in the configuration XML.", this_workflow_name))
  }

  apptainer_url = workflow_settings$apptainer$remote.url
  apptainer_name = workflow_settings$apptainer$container.name
  apptainer_tag = workflow_settings$apptainer$tag
  apptainer_sif = workflow_settings$apptainer$sif

  #### DATA REFERENCING ####
  #### Workflow run base directory + data source ID = source of data ####
  data_source_run_identifier = workflow_settings$data.source.01.reference
  workflow_data_source = file.path(base_workflow_directory, data_source_run_identifier)
  dir_check = check_directory_exists(workflow_data_source, stop_on_nonexistent=TRUE)

  # tar_option_set(
  #   packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr")
  # )
  tar_option_set(
    packages = c("PEcAn.settings", "readr", "dplyr")
  )
  list(
    step__resolve_data_routing(
      workflow_data_source_directory = workflow_data_source, 
      target_artifact_names = c("reference_IC_directory", "reference_data_entity", "reference_pft_entity"), 
      external_name_list = c("IC_files", "data", "pfts"),
      localized_name_list = c("IC_files", "data", "pfts"),
      action_list = c("reference", "reference", "reference")
    ),
    # how does the user either specify what vars are populated, or clarify what vars are populated by a func call
    step__resolve_apptainer(apptainer_source_directory=NULL, workflow_xml=workflow_settings),

    # Prep run directory & check for continue
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),
    # check for continue; then write configs
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)), 

    # TODO: find a method which allows passing of non-quoted vars
    step__run_distributed_write_configs(container=quote(apptainer_reference), pecan_settings=quote(pecan_settings_prepared), use_abstraction=TRUE)
  )
}, ask = FALSE, script = tar_script_path)

script_content <- readLines(tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", workflow_function_path, script_content, fixed = TRUE)
script_content <- gsub("@ORCHESTRATIONXML@", settings_path, script_content, fixed = TRUE)
script_content <- gsub("@WORKFLOWNAME@", workflow_name, script_content, fixed=TRUE)
script_content <- gsub("@PECANXMLPATH@", pecan_config_path, script_content, fixed=TRUE)

writeLines(script_content, tar_script_path)

tar_make(script = tar_script_path)



