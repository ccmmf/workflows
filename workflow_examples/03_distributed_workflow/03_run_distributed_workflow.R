library(targets)
library(tarchetypes)
library(XML)

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

##########################################################

workflow_name = "workflow.analysis.03"

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

  #### Data Referencing ####
  ## Workflow run base directory + data source ID = source of data ##
  data_source_run_identifier = workflow_settings$data.source.01.reference
  workflow_data_source = normalizePath(file.path(base_workflow_directory, data_source_run_identifier))
  dir_check = check_directory_exists(workflow_data_source, stop_on_nonexistent=TRUE)

  ## apptainer is referenced from a different workflow run id ##
  apptainer_source_run_identifier = workflow_settings$apptainer.source.reference
  apptainer_source_directory = normalizePath(file.path(base_workflow_directory, apptainer_source_run_identifier))
  dir_check = check_directory_exists(apptainer_source_directory, stop_on_nonexistent=TRUE)
  apptainer_sif = workflow_settings$apptainer$sif

  # tar pipeline options and config
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr")
  )
  list(
    # we can reference data products in an external directory
    # here, we can call this once per directory, and identify the components of that directory we want to reference
    step__link_data_by_name(
      workflow_data_source_directory = workflow_data_source, 
      target_artifact_names = c("reference_IC_directory", "reference_data_entity", "reference_pft_entity"), 
      external_name_list = c("IC_files", "data", "pfts"),
      localized_name_list = c("IC_files", "data", "pfts")
    ),
    # this is still a little chunky; workflow steps referencing these target names do so invisibily at the moment.

    # If we can't link to the apptainer via apptainer_source_directory, attempt to pull it from the remote.
    step__resolve_apptainer(apptainer_source_directory=apptainer_source_directory, workflow_xml=workflow_settings),

    # we can mix and match our own functions with classic tar_target imperatives
    # Prep run directory & check for continue
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),

    # check for continue; then write configs
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)), 
    
    ####  no more abstraction - or at least, not where the user has to do it. We do the abstraction in the background
    # instead of:
    # tar_target(
    #   pecan_write_configs_function,
    #   targets_function_abstraction(function_name = "pecan_write_configs"),
    # ),
    # tar_target(
    #   pecan_write_configs_arguments,
    #   targets_argument_abstraction(argument_object = list(pecan_settings=pecan_settings_prepared, xml_file=pecan_xml_file))
    # ),
    # tar_target(
    #   pecan_settings_job_submission, 
    #   targets_abstract_args_sbatch_exec(
    #     pecan_settings=pecan_settings,
    #     function_artifact="pecan_write_configs", 
    #     args_artifact="pecan_write_configs_arguments", 
    #     task_id=uuid::UUIDgenerate(), 
    #     functional_source=functions_source,
    #     apptainer=apptainer_reference, 
    #     dependencies=c(pecan_continue)
    #   )
    # ),

    # we write:
    step__run_distributed_write_configs(container=quote(apptainer_reference), pecan_settings=quote(pecan_settings), use_abstraction=TRUE, 
          dependencies=c("apptainer_reference", "pecan_settings")),

    # we can do this:
    step__run_pecan_workflow()

    # not this:
    # tar_target(
    #   ecosystem_settings,
    #   pecan_start_ecosystem_model_runs(pecan_settings=pecan_settings, dependencies=c(settings_job_outcome))
    # ), 
    # tar_target(
    #   model_results_settings,
    #   pecan_get_model_results(pecan_settings=ecosystem_settings)
    # ),
    # tar_target(
    #   ensembled_results_settings, ## the sequential settings here serve to ensure these are run in sequence, rather than in parallel
    #   pecan_run_ensemble_analysis(pecan_settings=model_results_settings)
    # ),
    # tar_target(
    #   sensitivity_settings,
    #   pecan_run_sensitivity_analysis(pecan_settings=ensembled_results_settings)
    # ),
    # tar_target(
    #   complete_settings,
    #   pecan_workflow_complete(pecan_settings=sensitivity_settings)
    # )
  )
}, ask = FALSE, script = tar_script_path)

script_content <- readLines(tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", workflow_function_path, script_content, fixed = TRUE)
script_content <- gsub("@ORCHESTRATIONXML@", settings_path, script_content, fixed = TRUE)
script_content <- gsub("@WORKFLOWNAME@", workflow_name, script_content, fixed=TRUE)
script_content <- gsub("@PECANXMLPATH@", pecan_config_path, script_content, fixed=TRUE)

writeLines(script_content, tar_script_path)

tar_make(script = tar_script_path)