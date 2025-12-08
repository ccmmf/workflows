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

workflow_name = "workflow.create.clim.files"

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
  library(XML)

  function_sourcefile = "@FUNCTIONPATH@"
  tar_source(function_sourcefile)

  orchestration_settings = parse_orchestration_xml("@ORCHESTRATIONXML@")
  pecan_xml_path = "@PECANXMLPATH@"
  workflow_name = "@WORKFLOWNAME@"
  workflow_settings = orchestration_settings$orchestration[[workflow_name]]
  base_workflow_directory = orchestration_settings$orchestration$workflow.base.run.directory
  if (is.null(workflow_settings)) {
    stop(sprintf("Workflow settings for '%s' not found in the configuration XML.", this_workflow_name))
  }

  site_era5_path <- normalizePath(workflow_settings$site.era5.path, mustWork = FALSE)
  site_sipnet_met_path <- normalizePath(workflow_settings$site.sipnet.met.path, mustWork = FALSE)
  site_info_filename = workflow_settings$site.info.file
  start_date <- workflow_settings$start.date
  end_date <- workflow_settings$end.date
  num_cores <- workflow_settings$n.workers
  parallel_strategy <- workflow_settings$parallel.strategy
  data_download_directory = file.path(base_workflow_directory, workflow_settings$data.download.reference)
  apptainer_sif = workflow_settings$apptainer$sif
  ensemble_literal <- sprintf(
    "c(%s)",
    paste(sprintf("%sL", seq_len(10)), collapse = ", ")
  )
  tar_option_set(
    packages = c()
  )

  list(
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),

    step__link_data_by_name(
      workflow_data_source_directory = data_download_directory, 
      target_artifact_names = c("reference_era5_path", "data_raw", "site_info_file", "data", "pfts"), 
      external_name_list = c("data_raw/ERA5_nc", "data_raw", site_info_filename, "data", "pfts"),
      localized_name_list = c("ERA5_nc", "data_raw", "site_info.csv", "data", "pfts")
    ),
    step__resolve_apptainer(apptainer_source_directory=data_download_directory, workflow_xml=workflow_settings),
    
    step__create_clim_files(
      pecan_settings=quote(pecan_settings), 
      container=quote(apptainer_reference), 
      workflow_settings=workflow_settings, 
      reference_path = quote(reference_era5_path),
      data_raw = quote(data_raw),
      site_info = quote(site_info_file),
      dependencies = c("pecan_settings", "apptainer_reference", "site_info_file", "reference_era5_path", "data_raw", "data")
    ),
    step__build_ic_files(
      workflow_settings = workflow_settings, 
      orchestration_settings = orchestration_settings, 
      container = quote(apptainer_reference), 
      dependencies = c("era5_clim_conversion", "apptainer_reference")
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

