library(targets)
library(tarchetypes)
library(PEcAn.all)

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

args = get_workflow_args()
settings <- PEcAn.settings::read.settings(args$settings)

#### run directory specification ####
# note: if this_run_directory exists already, and we specify the _targets script within it, targets will evaluate the pipeline already run
# if the pipeline has not changed, the pipeline will not run. This extends to the targeted functions, their arguments, and their arguments values. 
# thus, as long as the components of the pipeline run are kept in the functions, the data entities, and the arguments, we can have smart re-evaluation.

this_workflow_name = "workflow.reference.02"

#### Primary workflow settings parsing ####

## settings and params for this workflow
workflow_settings = settings$orchestration[[this_workflow_name]]
workflow_function_source = settings$orchestration$functions.source
source(workflow_function_source)

## overall run directory for common collection of workflow artifacts
workflow_run_directory = settings$orchestration$workflow.base.run.directory
dir_check = check_directory_exists(workflow_run_directory, stop_on_nonexistent=TRUE)
workflow_run_directory = normalizePath(workflow_run_directory)

run_identifier = workflow_settings$run.identifier
pecan_xml_path = workflow_settings$pecan.xml.path

data_source_run_identifier = workflow_settings$data.source.01.reference

# TODO: input parameter validation and defense
#### Handle input parameters parsed from settings file ####
#### workflow prep ####
function_path = normalizePath(file.path(workflow_function_source))
pecan_xml_path = normalizePath(file.path(pecan_xml_path))

#### DATA REFERENCING ####
#### Workflow run base directory + data source ID = source of data ####
this_data_source_directory = file.path(workflow_run_directory, data_source_run_identifier)
dir_check = check_directory_exists(this_data_source_directory, stop_on_nonexistent=TRUE)

#### THIS ANALYSIS RUN DIRECTORY SETUP ####
ret_obj <- workflow_run_directory_setup(run_identifier=run_identifier, workflow_run_directory=workflow_run_directory)
analysis_run_directory = ret_obj$run_dir
analysis_run_id = ret_obj$run_id

#### 
print(paste("Starting workflow run in directory:", analysis_run_directory))
setwd(analysis_run_directory)
tar_config_set(store = "./")
analysis_tar_script_path = file.path("./executed_pipeline.R")

#### Pipeline definition ####
tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)
  pecan_xml_path = "@PECANXML@"
  workflow_data_source = "@WORKFLOWDATASOURCE@"
  tar_source("@FUNCTIONPATH@")
  apptainer_url = "@APPTAINERURL"
  apptainer_name = "@APPTAINERNAME@"
  apptainer_tag = "@APPTAINERTAG@"
  apptainer_sif = "@APPTAINERSIF@"
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

    # pull down the apptainer from remote
    # we could do this in the prior step. 
    # doing it here in this example allows the next step to reference two different data sources    
    tar_target(apptainer_reference, pull_apptainer_container(apptainer_url_base=apptainer_url, apptainer_image_name=apptainer_name, apptainer_tag=apptainer_tag, apptainer_disk_sif=apptainer_sif)),

    # Prep run directory & check for continue
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),

    # check for continue; then write configs
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)), 

    # now we get into the abstract functions. 
    # create the abstraction of pecan write configs.
    tar_target(
        pecan_write_configs_function,
        targets_function_abstraction(function_name = "pecan_write_configs")
    ),
    # create the abstraction of the pecan write configs arguments
    tar_target(
      pecan_write_configs_arguments,
      targets_argument_abstraction(argument_object = list(pecan_settings=pecan_settings_prepared, xml_file=pecan_xml_file))
    ),

    # run the abstracted function on the abstracted arguments via slurm
    # tar_target(
    #   pecan_settings_job_submission, 
    #   targets_abstract_sbatch_exec(
    #     pecan_settings=pecan_settings,
    #     function_artifact="pecan_write_configs_function", 
    #     args_artifact="pecan_write_configs_arguments", 
    #     task_id=uuid::UUIDgenerate(), 
    #     apptainer=apptainer_reference, 
    #     dependencies=c(pecan_continue, apptainer_reference)
    #   )
    # ),
    tar_target(
      pecan_settings_job_submission,
      targets_based_containerized_local_exec(
        pecan_settings=pecan_settings,
        function_artifact="pecan_write_configs_function", 
        args_artifact="pecan_write_configs_arguments", 
        task_id=uuid::UUIDgenerate(), 
        apptainer=apptainer_reference, 
        dependencies=c(pecan_continue, apptainer_reference)
      )
    ),
    # block and wait until dist. job is done
    tar_target(
      settings_job_outcome,
      pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_settings_job_submission)
    )
  )
}, ask = FALSE, script = analysis_tar_script_path)

script_content <- readLines(analysis_tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", function_path, script_content)
script_content <- gsub("@PECANXML@", pecan_xml_path, script_content)
script_content <- gsub("@WORKFLOWDATASOURCE@", this_data_source_directory, script_content)
script_content <- gsub("@APPTAINERURL", workflow_settings$apptainer$remote.url, script_content)
script_content <- gsub("@APPTAINERNAME@", workflow_settings$apptainer$container.name, script_content)
script_content <- gsub("@APPTAINERTAG@", workflow_settings$apptainer$tag, script_content)
script_content <- gsub("@APPTAINERSIF@", workflow_settings$apptainer$sif, script_content)

writeLines(script_content, analysis_tar_script_path)

tar_make(script = analysis_tar_script_path)



