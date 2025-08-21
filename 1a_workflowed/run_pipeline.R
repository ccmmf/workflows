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

#### run-time parameters to the workflow have to be defined here
# variables required in all pipelines
# note: this allows the functions and code supporting this run to be switchable: I.e., we can do A/B testing on the code state.
function_path = normalizePath(file.path("./R/functions.R"))

# variables specific to this pipeline iteration
pecan_xml_path = normalizePath(file.path("../1a_single_site/single_site_almond.xml"))
ccmmf_env_tarball_url = "s3://carb/environments/PEcAn_head.tar.gz"
ccmmf_data_tarball_url = "s3://carb/data/workflows/phase_1a"
ccmmf_data_filename = "00_cccmmf_phase_1a_input_artifacts.tgz"
# strictly speaking not needed. this is the default. but, for clarity.

print(paste("Starting workflow run in directory:", this_run_directory))
# tar_config_set(store = this_run_directory)
# tar_script_path = file.path(this_run_directory, "executed_pipeline.R")
setwd(this_run_directory)
tar_config_set(store = "./")
tar_script_path = file.path("./executed_pipeline.R")


# testing required: 
# the era5 data can be loaded. If i add an ERA5 file to the external folder, will the pipeline re-run?
# if i alter the content of an era5 data file, will the pipeline re-run?
# if i add an NC file, will the pipeline re-run? (this should be the same answer as above)
# if i alter the content of an NC file, which is in binary, will the pipeline re-run?

#### Pipeline definition ####
# ok, here it is. This is a script that creates the targets pipeline exactly as below.
# this pipeline 

tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)

  pecan_xml_path = "@PECANXML@"
  ccmmf_data_tarball_url = "@CCMMFDATAURL@"
  ccmmf_data_filename = "@CCMMFDATAFILENAME@"
  tar_source("@FUNCTIONPATH@")
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr"),
    imports = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow")
  )
  list(
    tar_target(ccmmf_data_tarball, download_ccmmf_data(prefix_url=ccmmf_data_tarball_url, local_path=tar_path_store(), prefix_filename=ccmmf_data_filename)),
    tar_target(workflow_data_paths, untar(ccmmf_data_tarball, exdir = tar_path_store())),
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)), # note - this needs to be parameterized
    # tar_target(pecan_status, status.check("CONFIG"), packages=c("PEcAn.utils")),
    tar_target(pecan_settings_configs, pecan_write_configs(pecan_settings=pecan_settings_prepared))
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
writeLines(script_content, tar_script_path)

tar_make(script = tar_script_path)



