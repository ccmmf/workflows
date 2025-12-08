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
    # Config XML and source data handling
    # obviously, if at any time we need to alter the content of the reference data, we're going to need to do more than link to it.
    # doesn't copy anything; also doesn't check content - if the content of the source is changed, this is unaware.
    tar_target(reference_IC_directory, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="IC_files", localized_name="IC_files")),
    tar_target(reference_data_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="data", localized_name="data")),
    tar_target(reference_pft_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="pfts", localized_name="pfts")),

    # In this case, we're not pulling the apptainer - we are referencing it from a prior run
    # this means you can use the data-prep runs to iterate the apptainer version (when needed)
    # and use analysis runs to leverage the apptainer (but not update it)
    tar_target(
      apptainer_reference, 
      reference_external_data_entity(
        external_workflow_directory=apptainer_source_directory, 
        external_name=apptainer_sif, 
        localized_name=apptainer_sif
      )
    ),
    # Prep run directory & check for continue
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),

    # check for continue; then write configs
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)), 
    #### This throws an error about not finding uniform:
    # tar_target(pecan_settings_configs, pecan_write_configs(pecan_settings=pecan_settings_prepared, xml_file=pecan_xml_file))

    tar_target(
      pecan_write_configs_arguments,
      targets_argument_abstraction(argument_object = list(pecan_settings=pecan_settings_prepared, xml_file=pecan_xml_file))
    ),

    tar_target(
      pecan_settings_job_submission, 
      targets_abstract_args_sbatch_exec(
        pecan_settings=pecan_settings,
        function_artifact="pecan_write_configs", 
        args_artifact="pecan_write_configs_arguments", 
        task_id=uuid::UUIDgenerate(), 
        functional_source=functions_source,
        apptainer=apptainer_reference, 
        dependencies=c(pecan_continue)
      )
    ),
    # block and wait until dist. job is done
    tar_target(
      settings_job_outcome,
      pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_settings_job_submission)
    ), ## blocks until component jobs are done
    tar_target(
      ecosystem_settings,
      pecan_start_ecosystem_model_runs(pecan_settings=pecan_settings, dependencies=c(settings_job_outcome))
    ), 
    tar_target(
      model_results_settings,
      pecan_get_model_results(pecan_settings=ecosystem_settings)
    ),
    tar_target(
      ensembled_results_settings, ## the sequential settings here serve to ensure these are run in sequence, rather than in parallel
      pecan_run_ensemble_analysis(pecan_settings=model_results_settings)
    ),
    tar_target(
      sensitivity_settings,
      pecan_run_sensitivity_analysis(pecan_settings=ensembled_results_settings)
    ),
    tar_target(
      complete_settings,
      pecan_workflow_complete(pecan_settings=sensitivity_settings)
    )
  )
}, ask = FALSE, script = tar_script_path)

script_content <- readLines(tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", workflow_function_path, script_content, fixed = TRUE)
script_content <- gsub("@ORCHESTRATIONXML@", settings_path, script_content, fixed = TRUE)
script_content <- gsub("@WORKFLOWNAME@", workflow_name, script_content, fixed=TRUE)
script_content <- gsub("@PECANXMLPATH@", pecan_config_path, script_content, fixed=TRUE)

writeLines(script_content, tar_script_path)

tar_make(script = tar_script_path)