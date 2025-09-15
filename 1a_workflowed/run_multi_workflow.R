library(targets)
library(tarchetypes)
library(PEcAn.all)

#### run directory specification ####
# note: if this_run_directory exists already, and we specify the _targets script within it, targets will evaluate the pipeline already run
# if the pipeline has not changed, the pipeline will not run. This extends to the targeted functions, their arguments, and their arguments values. 
# thus, as long as the components of the pipeline run are kept in the functions, the data entities, and the arguments, we can have smart re-evaluation.
workflow_run_directory = file.path("./workflow_runs")
if (!dir.exists(workflow_run_directory)) {
    dir.create(workflow_run_directory, recursive = TRUE)
} 
workflow_run_directory = normalizePath(workflow_run_directory)

# adding a cut-in
run_id_A = "workflow_run_A"
run_id_B = "workflow_run_B"

this_run_directory_A = file.path(workflow_run_directory, run_id_A)
if (!dir.exists(this_run_directory_A)) {
    dir.create(this_run_directory_A, recursive = TRUE)
} 
this_run_directory_B = file.path(workflow_run_directory, run_id_B)
if (!dir.exists(this_run_directory_B)) {
  dir.create(this_run_directory_B, recursive = TRUE)
}


# note: this allows the functions and code supporting this run to be switchable: I.e., we can do A/B testing on the code state.
function_path = normalizePath(file.path("../tools/workflow_functions.R"))

# variables specific to this pipeline iteration
ccmmf_data_tarball_url = "s3://carb/data/workflows/phase_1a"
ccmmf_data_filename = "00_cccmmf_phase_1a_input_artifacts.tgz"

print(paste("Starting workflow run in directory:", this_run_directory_A))
setwd(this_run_directory_A)
tar_config_set(store = "./")
tar_script_path = file.path("./executed_pipeline.R")
#### Pipeline definition ####
# ok, here it is. This is a script that creates the targets pipeline exactly as below.

tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)

  ccmmf_data_tarball_url = "@CCMMFDATAURL@"
  ccmmf_data_filename = "@CCMMFDATAFILENAME@"
  tar_source("@FUNCTIONPATH@")
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr"),
    imports = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow")
  )
  list(
    # source data handling
    tar_target(ccmmf_data_tarball, download_ccmmf_data(prefix_url=ccmmf_data_tarball_url, local_path=tar_path_store(), prefix_filename=ccmmf_data_filename)),
    tar_target(workflow_data_paths, untar(ccmmf_data_tarball, exdir = tar_path_store())),
    tar_target(obtained_resources_untar, untar(ccmmf_data_tarball, list = TRUE)) 
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
script_content <- gsub("@CCMMFDATAURL@", ccmmf_data_tarball_url, script_content)
script_content <- gsub("@CCMMFDATAFILENAME@", ccmmf_data_filename, script_content)
writeLines(script_content, tar_script_path)
tar_make(script = tar_script_path)

### Pipeline definition for part B ###
# Reset working directory
setwd(paste0(workflow_run_directory,"/../"))

# variables specific to this pipeline iteration
pecan_xml_path = normalizePath(file.path("single_site_almond.xml"))

# Create the targets script and launch.
print(paste("Starting workflow run in directory:", this_run_directory_B))
setwd(this_run_directory_B)
tar_config_set(store = "./")
tar_script_path_B = file.path("./executed_pipeline.R")
tar_script({
  library(targets)
  library(tarchetypes)

  pecan_xml_path = "@PECANXML@"
  workflow_A = "@WORKFLOWA@"
  tar_source("@FUNCTIONPATH@")
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr"),
    imports = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow")
  )
  list(
    # Config XML and source data handling
    # obviously, if at any time we need to alter the content of the reference data, we're going to need to do more than link to it.
    # doesn't copy anything; also doesn't check content - if the content of the source is changed, this is unaware.
    tar_target(reference_IC_directory, reference_external_data_entity(external_workflow_directory=workflow_A, external_name="IC_files", localized_name="IC_files")),
    tar_target(reference_data_entity, reference_external_data_entity(external_workflow_directory=workflow_A, external_name="data", localized_name="data")),
    tar_target(reference_pft_entity, reference_external_data_entity(external_workflow_directory=workflow_A, external_name="pfts", localized_name="pfts")),
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
}, ask = FALSE, script = tar_script_path_B)

script_content <- readLines(tar_script_path_B)
script_content <- gsub("@FUNCTIONPATH@", function_path, script_content)
script_content <- gsub("@PECANXML@", pecan_xml_path, script_content)
script_content <- gsub("@WORKFLOWA@", this_run_directory_A, script_content)

writeLines(script_content, tar_script_path_B)

tar_make(script = tar_script_path_B)



