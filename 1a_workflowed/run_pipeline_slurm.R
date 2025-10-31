library(targets)
library(tarchetypes)
library(PEcAn.all)

get_workflow_args <- function() {
  option_list <- list(
    optparse::make_option(
      c("-r", "--run_id"),
      default = NULL,
      type = "character",
      help = "Run ID - optional",
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
if (is.null(args$run_id)) {
    run_id = uuid::UUIDgenerate() # future: optional provision by user.
} else {
    print(paste("Run id specified:", args$run_id))
    run_id = args$run_id
}
this_run_directory = file.path(workflow_run_directory, run_id)
if (!dir.exists(this_run_directory)) {
    dir.create(this_run_directory, recursive = TRUE)
} 

# note: this allows the functions and code supporting this run to be switchable: I.e., we can do A/B testing on the code state.
function_path = normalizePath(file.path("../tools/workflow_functions.R"))

# variables specific to this pipeline iteration
pecan_xml_path = normalizePath(file.path("slurm_distributed_single_site_almond.xml"))
ccmmf_data_tarball_url = "s3://carb/data/workflows/phase_1a"
ccmmf_data_filename = "00_cccmmf_phase_1a_input_artifacts.tgz"
# obtained via: apptainer pull docker://hdpriest0uiuc/sipnet-carb:latest
apptainer_source_dir = normalizePath(file.path("/home/hdpriest/Projects/workflows_distributed/1a_workflowed"))
# apptainer_name = "none"
remote_conda_env = "none"
apptainer_name = "sipnet-carb_latest.sif"
# remote_conda_env = "pecan-all"

print(paste("Starting workflow run in directory:", this_run_directory))
setwd(this_run_directory)
tar_config_set(store = "./")
tar_script_path = file.path("./executed_pipeline.R")

#### Pipeline definition ####
# ok, here it is. This is a script that creates the targets pipeline exactly as below.

tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)

  pecan_xml_path = "@PECANXML@"
  ccmmf_data_tarball_url = "@CCMMFDATAURL@"
  ccmmf_data_filename = "@CCMMFDATAFILENAME@"
  apptainer_source_dir = "@APPTAINERSOURCEDIR@"
  remote_conda_env = "@REMOTECONDAENV@"
  apptainer_name = "@APPTAINERNAME@"

  if (apptainer_name == "none") {
    apptainer_name = NULL
  }
  if (remote_conda_env == "none") {
    remote_conda_env = NULL
  }

  tar_source("@FUNCTIONPATH@")
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr"),
    imports = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow")
  )
  list(
    # source data handling
    tar_target(
      apptainer_reference, 
      reference_external_data_entity(
        external_workflow_directory=apptainer_source_dir, 
        external_name=apptainer_name, 
        localized_name=apptainer_name
      )
    ),
    tar_target(
      ccmmf_data_tarball, 
      download_ccmmf_data(
        prefix_url=ccmmf_data_tarball_url, 
        local_path=tar_path_store(), 
        prefix_filename=ccmmf_data_filename
      )
    ),
    # untar the data
    tar_target(workflow_data_paths, untar(ccmmf_data_tarball, exdir = tar_path_store())),
    # XML sourcing
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),

    # Prep run directory & check for continue
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),
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
    tar_target(
      pecan_settings_job_submission, 
      targets_abstract_sbatch_exec(
        pecan_settings=pecan_settings,
        function_artifact="pecan_write_configs_function", 
        args_artifact="pecan_write_configs_arguments", 
        task_id=uuid::UUIDgenerate(), 
        apptainer=apptainer_reference, 
        conda_env=remote_conda_env,
        dependencies=c(pecan_continue)
      )
    ),
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

# because tar_make executes the script in a separate process based on the created workflow directory,
# in order to parametrize the workflow script, we have to first create placeholders, and then below, replace them with actual values.
# if we simply place the variables in the script definition above, they are evaluated as the time the script is executed by tar_make()
# that execution takes place in a different process + memory space, in which those variables are not accessible.
# so, we create the execution script, and then text-edit in the parameters.
# Read the generated script and replace placeholders with actual file paths
script_content <- readLines(tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", function_path, script_content)
script_content <- gsub("@PECANXML@", pecan_xml_path, script_content)
script_content <- gsub("@CCMMFDATAURL@", ccmmf_data_tarball_url, script_content)
script_content <- gsub("@CCMMFDATAFILENAME@", ccmmf_data_filename, script_content)
script_content <- gsub("@APPTAINERSOURCEDIR@", apptainer_source_dir, script_content)
script_content <- gsub("@APPTAINERNAME@", apptainer_name, script_content)
script_content <- gsub("@REMOTECONDAENV@", remote_conda_env, script_content)

writeLines(script_content, tar_script_path)

tar_make(script = tar_script_path)



