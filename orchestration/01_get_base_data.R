library(targets)
library(tarchetypes)
library(XML)

get_workflow_args <- function() {
  option_list <- list(
    optparse::make_option(
      c("-s", "--settings"),
      default = NULL,
      type = "character",
      help = "Workflow configuration XML"
    )
  )

  parser <- optparse::OptionParser(option_list = option_list)
  optparse::parse_args(parser)
}

args <- get_workflow_args()

if (is.null(args$settings)) {
  stop("An Orchestration settings XML must be provided via --settings.")
}

this_workflow_name <- "workflow.get.base.data"

settings_path = normalizePath(file.path(args$settings))
settings = XML::xmlToList(XML::xmlParse(args$settings))

workflow_function_source = file.path(settings$orchestration$functions.source)
workflow_function_path = normalizePath(workflow_function_source)
source(workflow_function_source)

ret_obj <- workflow_run_directory_setup(orchestration_settings=settings, workflow_name=this_workflow_name)



analysis_run_directory = ret_obj$run_dir
run_id = ret_obj$run_id

dir.create(paste0(analysis_run_directory,"/data_raw"), recursive = TRUE)

message(sprintf("Starting workflow run '%s' in directory: %s", run_id, analysis_run_directory))

setwd(analysis_run_directory)
tar_config_set(store = "./")
tar_script_path <- file.path("./executed_pipeline.R")

tar_script({
  library(targets)
  library(tarchetypes)
  library(XML)

  function_sourcefile = "@FUNCTIONPATH@"
  workflow_name = "@WORKFLOWNAME@"
  tar_source(function_sourcefile)
  orchestration_settings = parse_orchestration_xml("@ORCHESTRATIONXML@")
  
  check_orchestration_keys(orchestration_xml = orchestration_settings$orchestration, key_list = c(workflow_name, "workflow.base.run.directory"))

  workflow_settings = orchestration_settings$orchestration[[workflow_name]]
  base_workflow_directory = orchestration_settings$orchestration$workflow.base.run.directory
  
  check_orchestration_keys(orchestration_xml = workflow_settings, key_list = c("apptainer", "ccmmf.s3.artifact.01.url", "ccmmf.s3.artifact.01.filename", "ccmmf.s3.artifact.02.url", "ccmmf.s3.artifact.02.filename"))
  check_orchestration_keys(orchestration_xml = workflow_settings$apptainer, key_list = c("remote.url", "container.name", "tag", "sif"))
  

  apptainer_url = workflow_settings$apptainer$remote.url
  apptainer_name = workflow_settings$apptainer$container.name
  apptainer_tag = workflow_settings$apptainer$tag
  apptainer_sif = workflow_settings$apptainer$sif

  artifact1_url <- workflow_settings$ccmmf.s3.artifact.01.url
  artifact1_filename <- workflow_settings$ccmmf.s3.artifact.01.filename
  artifact2_url <- workflow_settings$ccmmf.s3.artifact.02.url
  artifact2_filename <- workflow_settings$ccmmf.s3.artifact.02.filename
  median_tif_url <- workflow_settings$ccmmf.s3.median_tif.url
  median_tif_filename <- workflow_settings$ccmmf.s3.median_tif.filename
  stdv_tif_filename <- workflow_settings$ccmmf.s3.stdv_tif.filename

  tar_option_set(packages = character(0))

  list(
    # tar_target(
    #   ccmmf_artifact_01_file, 
    #   download_ccmmf_data(prefix_url = artifact1_url, local_path = tar_path_store(), prefix_filename = artifact1_filename)
    # ),
    # tar_target(
    #   ccmmf_artifact_01_contents,
    #   untar(ccmmf_artifact_01_file, exdir = tar_path_store())
    # ),
    tar_target(
      ccmmf_artifact_02_file,
      download_ccmmf_data(prefix_url = artifact2_url,local_path = tar_path_store(),prefix_filename = artifact2_filename)
    ),
    tar_target(
      ccmmf_artifact_02_contents,
      untar(ccmmf_artifact_02_file, exdir = tar_path_store())
    ),
    tar_target(
      ccmmf_median_tif_file,
      download_ccmmf_data(prefix_url = median_tif_url, local_path = paste0(tar_path_store(),"data_raw/"), prefix_filename = median_tif_filename)
    ),
    tar_target(
      ccmmf_stdv_tif_file,
      download_ccmmf_data(prefix_url = median_tif_url, local_path = paste0(tar_path_store(),"data_raw/"), prefix_filename = stdv_tif_filename)
    ),
    tar_target(
      apptainer_reference, 
      pull_apptainer_container(apptainer_url_base=apptainer_url, apptainer_image_name=apptainer_name, apptainer_tag=apptainer_tag, apptainer_disk_sif=apptainer_sif)
    )
  )
}, ask = FALSE, script = tar_script_path)

script_content <- readLines(tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", workflow_function_path, script_content, fixed = TRUE)
script_content <- gsub("@ORCHESTRATIONXML@", settings_path, script_content, fixed = TRUE)
script_content <- gsub("@WORKFLOWNAME@", this_workflow_name, script_content, fixed=TRUE)

writeLines(script_content, tar_script_path)

tar_make(script = tar_script_path)

