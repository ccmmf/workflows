##################
# workflow functions for targets-based PEcAn workflows
# Note that these functions will be executed in different environments depending on the context, so it is not safe to assume that dependencies are always present in the namespace from which the function is called.
# other functions will be abstracted by the targets framework, and loaded into a novel namespace on a different node.
# function authors are encouraged to think carefully about the dependencies of their functions.
# if dependencies are not present, it would be ideal for functions to error informatively rather than fail on imports.

#' Download CCMMF Data
#'
#' Downloads data from the CCMMF S3-compatible storage using AWS CLI.
#'
#' @param prefix_url Character string specifying the S3 URL prefix for the data.
#' @param local_path Character string specifying the local directory path where the file will be downloaded.
#' @param prefix_filename Character string specifying the filename to download.
#'
#' @return Character string containing the full path to the downloaded file.
#'
#' @examples
#' \dontrun{
#' file_path <- download_ccmmf_data("s3://bucket/path", "/local/path", "data.nc")
#' }
#'
#' @export
download_ccmmf_data <- function(prefix_url, local_path, prefix_filename) {
    system2("aws", args = c("s3", "cp", "--endpoint-url", "https://s3.garage.ccmmf.ncsa.cloud", paste0(prefix_url, "/", prefix_filename), local_path))
    return(file.path(local_path, prefix_filename))
}

#' Build ERA5 Site/Ensemble Combinations
#'
#' Reads the site metadata file and constructs a data frame of site / ensemble
#' combinations with associated start and end dates. Intended to be used with a
#' downstream targets dynamic branching step.
#'
#' @param site_info_file Character. Path to the CSV containing site metadata.
#'   Must include an `id` column.
#' @param start_date Character (YYYY-MM-DD). Start date for each combination.
#' @param end_date Character (YYYY-MM-DD). End date for each combination.
#' @param ensemble_members Integer vector identifying ensemble member indices.
#'
#' @return Data frame with columns `site_id`, `start_date`, `end_date`, and
#'   `ens_id`. Any additional columns from `site_info_file` are preserved and
#'   repeated across ensemble members.
#' @export
build_era5_site_combinations <- function(
    site_info_file = "site_info.csv",
    start_date = "2016-01-01",
    end_date = "2023-12-31",
    ensemble_members = 1:10,
    dependencies = NULL
) {

    if (!file.exists(site_info_file)) {
        stop(sprintf("Site info file not found: %s", site_info_file), call. = FALSE)
    }

    site_info <- utils::read.csv(site_info_file, stringsAsFactors = FALSE)
    if (!"id" %in% names(site_info)) {
        stop("`site_info_file` must contain an `id` column.", call. = FALSE)
    }

    site_info$site_id <- site_info$id
    site_info$start_date <- start_date
    site_info$end_date <- end_date

    if (!is.numeric(ensemble_members)) {
        stop("`ensemble_members` must be numeric.", call. = FALSE)
    }

    if (length(ensemble_members) == 0) {
        return(site_info[0, , drop = FALSE])
    }

    replicated_info <- site_info[rep(seq_len(nrow(site_info)), each = length(ensemble_members)), , drop = FALSE]
    replicated_info$ens_id <- rep(ensemble_members, times = nrow(site_info))

    rownames(replicated_info) <- NULL
    return(replicated_info)
}


build_era5_site_combinations_args <- function(
    site_info_file = "site_info.csv",
    start_date = "2016-01-01",
    end_date = "2023-12-31",
    ensemble_members = 1:10,
    reference_path = "",
    sipnet_met_path = "",
    dependencies = NULL
) {
    if (!file.exists(site_info_file)) {
        stop(sprintf("Site info file not found: %s", site_info_file), call. = FALSE)
    }

    site_info <- utils::read.csv(site_info_file, stringsAsFactors = FALSE)
    if (!"id" %in% names(site_info)) {
        stop("`site_info_file` must contain an `id` column.", call. = FALSE)
    }

    site_info$site_id <- site_info$id
    site_info$start_date <- start_date
    site_info$end_date <- end_date
    site_info$reference_path <- reference_path
    site_info$sipnet_met_path <- sipnet_met_path

    if (!is.numeric(ensemble_members)) {
        stop("`ensemble_members` must be numeric.", call. = FALSE)
    }

    if (length(ensemble_members) == 0) {
        return(site_info[0, , drop = FALSE])
    }

    replicated_info <- site_info[rep(seq_len(nrow(site_info)), each = length(ensemble_members)), , drop = FALSE]
    replicated_info$ens_id <- rep(ensemble_members, times = nrow(site_info))

    rownames(replicated_info) <- NULL
    return(replicated_info)
}

#' Convert a Single ERA5 Combination to SIPNET Clim Drivers
#'
#' Runs `PEcAn.SIPNET::met2model.SIPNET()` for a single site / ensemble
#' combination. Designed for use within a dynamic branching target fed by
#' `build_era5_site_combinations()`.
#'
#' @param site_id Character. Site identifier matching directory naming.
#' @param ens_id Integer. Ensemble member index.
#' @param start_date Character (YYYY-MM-DD). Start date for generated `clim`
#'   file.
#' @param end_date Character (YYYY-MM-DD). End date for generated `clim`
#'   file.
#' @param site_era5_path Character. Base directory containing ERA5 NetCDF
#'   inputs organised as `ERA5_<siteid>_<ensid>/ERA5.<ensid>.<year>.nc`.
#' @param site_sipnet_met_path Character. Directory where SIPNET `clim` files
#'   should be written.
#'
#' @return Character string giving the output directory used for the `clim`
#'   files.
#' @export
convert_era5_nc_to_clim <- function(
    site_combinations,
    site_era5_path = NULL,
    site_sipnet_met_path = NULL,
    n_workers = 2,
    dependencies = NULL
) {

    if (is.null(site_combinations$site_id) 
    || is.null(site_combinations$ens_id) 
    || is.null(site_combinations$start_date) 
    || is.null(site_combinations$end_date)) {
        stop("`site_id`, `ens_id`, `start_date`, and `end_date` must all be supplied.", call. = FALSE)
    }

    if (!dir.exists(site_era5_path)) {
        stop(sprintf("Input ERA5 directory not found: %s", site_era5_path), call. = FALSE)
    }

    if (!dir.exists(site_sipnet_met_path)) {
        dir.create(site_sipnet_met_path, recursive = TRUE)
    }

    output_directory <- file.path(site_sipnet_met_path)
    if (!dir.exists(output_directory)) {
        dir.create(output_directory, recursive = TRUE)
    }

    parallel_strategy = "multisession"
    future::plan(parallel_strategy, workers = n_workers)
    furrr::future_pwalk(
        site_combinations,
        function(site_id, start_date, end_date, ens_id, ...) {
            PEcAn.SIPNET::met2model.SIPNET(
                in.path = file.path(
                    site_era5_path,
                    paste("ERA5", site_id, ens_id, sep = "_")
                ),
                start_date = start_date,
                end_date = end_date,
                in.prefix = paste0("ERA5.", ens_id),
                outfolder = file.path(site_sipnet_met_path, site_id)
            )
        }
    )
    output_directory
}


#' Prepare PEcAn Run Directory
#'
#' Prepare PEcAn Run Directory
#'
#' Creates the output directory for a PEcAn workflow run if it doesn't exist.
#' Stops execution if the directory already exists to prevent overwriting.
#'
#' @param pecan_settings List containing PEcAn settings including the output directory path.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return The original pecan_settings list.
#'
#' @examples
#' \dontrun{
#' settings <- prepare_pecan_run_directory(pecan_settings)
#' }
#'
#' @export
prepare_pecan_run_directory <- function(pecan_settings, dependencies = NULL) {
    print(getwd())
    pecan_run_directory = pecan_settings$outdir
    if (!dir.exists(file.path(pecan_run_directory))) {
        print(paste("Creating run directory", pecan_run_directory))
        dir.create(file.path(pecan_run_directory), recursive = TRUE)
    } else {
        stop(paste("Run directory", pecan_run_directory, "already exists"))
    }
    return(pecan_settings)
}

#' Check PEcAn Continue Directive
#'
#' Checks if a PEcAn workflow should continue from a previous run by examining
#' the STATUS file in the output directory.
#'
#' @param pecan_settings List containing PEcAn settings including the output directory path.
#' @param continue Logical indicating whether to continue from a previous run.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return Logical value indicating whether to continue the workflow.
#'
#' @examples
#' \dontrun{
#' should_continue <- check_pecan_continue_directive(pecan_settings, continue=TRUE)
#' }
#'
#' @export
check_pecan_continue_directive <- function(pecan_settings, continue=FALSE, dependencies = NULL) {
    status_file <- file.path(pecan_settings$outdir, "STATUS")
    if (continue && file.exists(status_file)) {
        file.remove(status_file)
    }
    return(continue)
}

#' Monitor PEcAn Cluster Job
#'
#' Monitors the status of cluster jobs submitted via PEcAn's remote execution system.
#' Continuously checks job status until all jobs are completed.
#'
#' @param pecan_settings List containing PEcAn settings including host configuration.
#' @param job_id_list Named list of job IDs to monitor.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return Logical TRUE when all jobs are completed.
#'
#' @details
#' This function is adapted from PEcAn.remote::start_qsub and PEcAn.workflow::start_model_runs.
#' It polls job status every 10 seconds and removes completed jobs from the monitoring list.
#'
#' @examples
#' \dontrun{
#' job_ids <- list("job1" = "12345", "job2" = "12346")
#' pecan_monitor_cluster_job(pecan_settings, job_ids)
#' }
#'
#' @export
pecan_monitor_cluster_job <- function(pecan_settings, job_id_list, dependencies = NULL){
    # adapted heavily from 
    ## pecan.remote:start_qsub
    ## pecan.workflow:start_model_runs
    # list of job IDs (may be list of 1) 
    while (length(job_id_list) > 0) {
        Sys.sleep(10)
        for (run in names(job_id_list)) {
            job_finished = FALSE
            job_finished = PEcAn.remote::qsub_run_finished(
                run = job_id_list[run],
                host = pecan_settings$host$name,
                qstat = pecan_settings$host$qstat
            )
            if(job_finished){
                job_id_list[run] = NULL
            }
        }
    }
    return(TRUE)
}

monitor_cluster_job <- function(distribution_adapter, job_id_list, dependencies = NULL){
    # adapted heavily from 
    ## pecan.remote:start_qsub
    ## pecan.workflow:start_model_runs
    # list of job IDs (may be list of 1) 
    while (length(job_id_list) > 0) {
        Sys.sleep(10)
        for (run in names(job_id_list)) {
            job_finished = FALSE
            job_finished = PEcAn.remote::qsub_run_finished(
                run = job_id_list[run],
                host = distribution_adapter$name,
                qstat = distribution_adapter$qstat
            )
            if(job_finished){
                job_id_list[run] = NULL
            }
        }
    }
    return(TRUE)
}

#' Start PEcAn Ecosystem Model Runs
#'
#' Initiates ecosystem model runs using PEcAn's workflow system.
#' Handles both single runs and ensemble runs with appropriate error handling.
#'
#' @param pecan_settings List containing PEcAn settings and configuration.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return The original pecan_settings list.
#'
#' @details
#' This function uses PEcAn.utils, PEcAn.logger, and PEcAn.workflow packages.
#' It determines whether to stop on error based on ensemble size and settings.
#' For single runs, it stops on error; for ensemble runs, it continues on error.
#'
#' @examples
#' \dontrun{
#' settings <- pecan_start_ecosystem_model_runs(pecan_settings)
#' }
#'
#' @export
pecan_start_ecosystem_model_runs <- function(pecan_settings, dependencies = NULL) {
    # pecan.utils
    # pecan.logger
    # pecan.workflow
    # Start ecosystem model runs
    if (PEcAn.utils::status.check("MODEL") == 0) {
        PEcAn.utils::status.start("MODEL")
        stop_on_error <- as.logical(pecan_settings[[c("run", "stop_on_error")]])
        if (length(stop_on_error) == 0) {
            # If we're doing an ensemble run, don't stop. If only a single run, we
            # should be stopping.
            if (is.null(pecan_settings[["ensemble"]]) ||
                as.numeric(pecan_settings[[c("ensemble", "size")]]) == 1) {
                stop_on_error <- TRUE
            } else {
                stop_on_error <- FALSE
            }
        }
        PEcAn.logger::logger.setUseConsole(TRUE)
        PEcAn.logger::logger.setLevel("ALL")
        PEcAn.workflow::runModule_start_model_runs(pecan_settings, stop.on.error = stop_on_error)
        PEcAn.utils::status.end()
    }
    return(pecan_settings)
}

#' Get PEcAn Model Results
#'
#' Retrieves and processes the results from completed PEcAn model runs.
#'
#' @param pecan_settings List containing PEcAn settings and configuration.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return The original pecan_settings list.
#'
#' @details
#' This function uses PEcAn.uncertainty::runModule.get.results to process
#' model output and prepare it for further analysis.
#'
#' @examples
#' \dontrun{
#' settings <- pecan_get_model_results(pecan_settings)
#' }
#'
#' @export
pecan_get_model_results <- function(pecan_settings, dependencies = NULL) {
    # Get results of model runs
    if (PEcAn.utils::status.check("OUTPUT") == 0) {
        PEcAn.utils::status.start("OUTPUT")
        PEcAn.uncertainty::runModule.get.results(pecan_settings)
        PEcAn.utils::status.end()
    }
    return(pecan_settings)
}

#' Run PEcAn Ensemble Analysis
#'
#' Performs ensemble analysis on PEcAn model output if ensemble settings are configured.
#'
#' @param pecan_settings List containing PEcAn settings and configuration.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return The original pecan_settings list.
#'
#' @details
#' This function runs ensemble analysis using PEcAn.uncertainty::runModule.run.ensemble.analysis
#' only if ensemble configuration is present in the settings.
#'
#' @examples
#' \dontrun{
#' settings <- pecan_run_ensemble_analysis(pecan_settings)
#' }
#'
#' @export
pecan_run_ensemble_analysis <- function(pecan_settings, dependencies = NULL) {
    # Run ensemble analysis on model output.
    if ("ensemble" %in% names(pecan_settings) && PEcAn.utils::status.check("ENSEMBLE") == 0) {
        PEcAn.utils::status.start("ENSEMBLE")
        PEcAn.uncertainty::runModule.run.ensemble.analysis(pecan_settings, TRUE)
        PEcAn.utils::status.end()
    }
    return(pecan_settings)
}

#' Run PEcAn Sensitivity Analysis
#'
#' Performs sensitivity analysis and variance decomposition on PEcAn model output
#' if sensitivity analysis settings are configured.
#'
#' @param pecan_settings List containing PEcAn settings and configuration.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return The original pecan_settings list.
#'
#' @details
#' This function runs sensitivity analysis using PEcAn.uncertainty::runModule.run.sensitivity.analysis
#' only if sensitivity analysis configuration is present in the settings.
#'
#' @examples
#' \dontrun{
#' settings <- pecan_run_sensitivity_analysis(pecan_settings)
#' }
#'
#' @export
pecan_run_sensitivity_analysis <- function(pecan_settings, dependencies = NULL) {
    # Run sensitivity analysis and variance decomposition on model output
    if ("sensitivity.analysis" %in% names(pecan_settings) && PEcAn.utils::status.check("SENSITIVITY") == 0) {
        PEcAn.utils::status.start("SENSITIVITY")
        PEcAn.uncertainty::runModule.run.sensitivity.analysis(pecan_settings)
        PEcAn.utils::status.end()
    }
    return(pecan_settings)
}

#' Complete PEcAn Workflow
#'
#' Finalizes a PEcAn workflow by cleaning up resources and sending notification emails.
#'
#' @param pecan_settings List containing PEcAn settings and configuration.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return The original pecan_settings list.
#'
#' @details
#' This function performs final cleanup tasks including:
#' - Killing SSH tunnels
#' - Sending completion email notifications (if configured)
#' - Updating workflow status
#'
#' @examples
#' \dontrun{
#' settings <- pecan_workflow_complete(pecan_settings)
#' }
#'
#' @export
pecan_workflow_complete <- function(pecan_settings, dependencies = NULL) {
    if (PEcAn.utils::status.check("FINISHED") == 0) {
        PEcAn.utils::status.start("FINISHED")
        PEcAn.remote::kill.tunnel(pecan_settings)

        # Send email if configured
        if (!is.null(pecan_settings$email)
            && !is.null(pecan_settings$email$to)
            && (pecan_settings$email$to != "")) {
            sendmail(
                pecan_settings$email$from,
                pecan_settings$email$to,
                paste0("Workflow has finished executing at ", base::date()),
                paste0("You can find the results on ", pecan_settings$email$url)
            )
        }
        PEcAn.utils::status.end()
    }

    print("---------- PEcAn Workflow Complete ----------")
    return(pecan_settings)
}

#' Write PEcAn Configuration Files
#'
#' Writes PEcAn configuration files for model runs, either by generating new configs
#' or loading existing ones if they already exist.
#'
#' @param pecan_settings List containing PEcAn settings and configuration.
#' @param xml_file Character string specifying the path to the XML settings file.
#'
#' @return Updated pecan_settings list with configuration information.
#'
#' @details
#' This function either generates new configuration files using PEcAn.workflow::runModule.run.write.configs
#' or loads existing configuration files if they are already present in the output directory.
#'
#' @examples
#' \dontrun{
#' settings <- pecan_write_configs(pecan_settings, "settings.xml")
#' }
#'
#' @export
pecan_write_configs <- function(pecan_settings, xml_file) {
    # print(xml_file)
    # pecan_settings <- PEcAn.settings::read.settings(xml_file)
    pecan_settings = xml_file
    PEcAn.logger::logger.setLevel("ALL")
    if (PEcAn.utils::status.check("CONFIG") == 0) {
        PEcAn.utils::status.start("CONFIG")
        print("Writing configs via PEcAn.workflow::runModule.run.write.configs")
        pecan_settings <- PEcAn.workflow::runModule.run.write.configs(pecan_settings)
        print(paste("Writing configs to", file.path(pecan_settings$outdir, "pecan.CONFIGS.xml")))
        PEcAn.settings::write.settings(pecan_settings, outputfile = "pecan.CONFIGS.xml")
        PEcAn.utils::status.end()
    } else if (file.exists(file.path(pecan_settings$outdir, "pecan.CONFIGS.xml"))) {
        pecan_settings <- PEcAn.settings::read.settings(file.path(pecan_settings$outdir, "pecan.CONFIGS.xml"))
    }
    return(pecan_settings)
}

#' Reference External Data Entity
#'
#' Creates a symbolic link to an external data entity within the targets store.
#'
#' @param external_workflow_directory Character string specifying the directory containing the external data.
#' @param external_name Character string specifying the name of the external data file.
#' @param localized_name Character string specifying the name for the local symbolic link.
#'
#' @return Character string containing the path to the created symbolic link, or NULL if external_name is NULL.
#'
#' @details
#' This function creates a symbolic link from an external data entity to the targets store.
#' It validates that the external file exists and that the local link doesn't already exist.
#'
#' @examples
#' \dontrun{
#' link_path <- reference_external_data_entity("/external/path", "data.nc", "local_data.nc")
#' }
#'
#' @export
reference_external_data_entity <- function(external_workflow_directory, external_name, localized_name){
    if (is.null(external_name)){
        return(NULL)
    }
    local_link_path = file.path(paste0(tar_path_store(), localized_name))
    external_link_path = file.path(paste0(external_workflow_directory, "/",external_name))
    if (!file.exists(external_link_path)){
        stop(paste("External link path", external_link_path, "does not exist"))
        return(NULL)
    }
    if (file.exists(local_link_path)){
        warning(paste("Local link path", local_link_path, "already exists -- skipping."))
    }else{
        file.symlink(from=external_link_path, to=local_link_path)
    }
    return(local_link_path)
}

#' Localize Data Resources
#'
#' Copies data resources from a central directory to a local run directory.
#' Currently non-functional and returns FALSE.
#'
#' @param resource_list Character vector of resource names to copy.
#' @param this_run_directory Character string specifying the destination directory.
#' @param data_resource_directory Character string specifying the source directory.
#'
#' @return Logical FALSE (function is not yet implemented).
#'
#' @details
#' This function is currently not functional and will return FALSE with a warning message.
#' The commented code shows the intended functionality for copying data resources.
#'
#' @examples
#' \dontrun{
#' # This function is not yet implemented
#' result <- localize_data_resources(c("data1.nc", "data2.nc"), "/run/dir", "/data/dir")
#' }
#'
#' @export
localize_data_resources <- function(resource_list, this_run_directory, data_resource_directory) {
    cat("function not functional yet. don't do that.\n")
    return(FALSE)
    for (resource in resource_list) {
        resource = trimws(resource)
        this_run_directory = trimws(this_run_directory)
        print(paste(resource))
        source_path = normalizePath(file.path(paste0(data_resource_directory, "/",resource)))
        destination_path = normalizePath(file.path(paste0(this_run_directory, "/",resource)))
        # destination_path = file.path(paste0(this_run_directory, "/"))
        print(paste("Copying data resource from", source_path, "to", destination_path))
        # print(paste("Copying data resource from", source_path, "to", destination_path))
        # file.copy(source_path, destination_path, recursive=TRUE)
    }
    return(resource_list)
}

#' Generate Standard SLURM Batch Header
#'
#' Generates a standard SLURM batch script header with optional Apptainer module loading.
#'
#' @param apptainer Character string specifying the Apptainer container path (optional).
#'
#' @return Character string containing the SLURM batch script header.
#'
#' @details
#' This function generates a standard SLURM batch script header with default resource allocations:
#' - 1 node, 1 task per node, 1 CPU per task
#' - 1 hour runtime
#' - Standard output and error logging
#' If apptainer is provided, it adds a module load command for Apptainer.
#'
#' @examples
#' \dontrun{
#' header <- sbatch_header_standard()
#' header_with_container <- sbatch_header_standard("/path/to/container.sif")
#' }
#'
#' @export
sbatch_header_standard <- function(apptainer=NULL) {
    header_string <- "#!/bin/bash
#SBATCH --job-name=my_job_name        # Job name
#SBATCH --output=pecan_workflow_out_%j.log        # Standard output file
#SBATCH --error=pecan_workflow_err_%j.log             # Standard error file
#SBATCH --nodes=1                    # Number of nodes
#SBATCH --ntasks-per-node=1           # Number of tasks per node
#SBATCH --mem=32000
#SBATCH --cpus-per-task=1             # Number of CPU cores per task
#SBATCH --time=1:00:00                # Maximum runtime (D-HH:MM:SS)

#Load necessary modules (if needed)
"
    if (!is.null(apptainer)) {
        header_string = paste0(header_string, "module load apptainer\n")
    }
    return(header_string)
}

pull_apptainer_container <- function(apptainer_url_base=NULL, apptainer_image_name=NULL, apptainer_disk_sif=NULL, apptainer_tag="latest") {
    # TODO: handle nulls and non-passes. validate url/names,
    apptainer_output_sif = paste0(apptainer_image_name,"_",apptainer_tag,".sif")
    out = system2("apptainer", c(paste0("pull ", apptainer_output_sif ," ", apptainer_url_base,apptainer_image_name,":",apptainer_tag)), stdout = TRUE, stderr = TRUE)
    return(apptainer_output_sif)
}


#' Targets Function Abstraction
#'
#' Retrieves a function by name and returns it as a targets object for remote execution.
#'
#' @param function_name Character string specifying the name of the function to retrieve.
#'
#' @return The function object retrieved by name.
#'
#' @details
#' This function retrieves an arbitrary function by its name and returns it as a target product.
#' The targets framework saves the function as an unnamed function object in the workflow store,
#' making it available to targets::tar_read() calls. Once tar_read is called into a namespace,
#' the function is available under the name it is saved into. It is incumbent on the function
#' and data author to ensure that the data passed into the function in the remote matches the signature.
#'
#' @examples
#' \dontrun{
#' func <- targets_function_abstraction("my_function")
#' }
#'
#' @export
targets_function_abstraction <- function(function_name) {
    # We need to retrieve an arbitrary function by its name, and return it as a target product
    # targets will then save the function as an un-named function object in the workflow store, making it available to a targets::tar_read() call
    # once tar_read is called into a namespace, that function is available under the name it is saved into
    # it will be incumbent on the function and data author to ensure that the data passed into the function in the remote matches the signature.
    return(get(function_name, mode="function"))   
}

#' Targets Argument Abstraction
#'
#' Returns an argument object as a targets object for remote execution.
#'
#' @param argument_object R object containing arguments to be passed to a function.
#'
#' @return The original argument_object.
#'
#' @details
#' If targets returns an R object, it can be read into a namespace via targets::tar_read().
#' The object - as it is constructed, including its values, is then available under the variable
#' it is saved into. This allows a user on a headnode to construct an arguments object variable
#' with custom names, orders, etc., register it with targets, and on a remote, access the object
#' as it was constructed, and pass it into a function call.
#'
#' @examples
#' \dontrun{
#' args <- list(param1 = "value1", param2 = 42)
#' arg_obj <- targets_argument_abstraction(args)
#' }
#'
#' @export
targets_argument_abstraction <- function(argument_object) {
    # if we have targets return an R object, it can be read into a namespace via targets::tar_read()
    # the object - as it is constructed, including its values, is then available under the variable it is saved into
    # this allows a user on a headnode to construct a arguments object variable with custom names, orders, etc, register it with targets
    # and on a remote, access the object as it was constructed, and pass it into a function call.
    return(argument_object)
}

#' Targets Abstract SLURM Batch Execution
#'
#' Executes a targets function remotely via SLURM batch job with optional containerization.
#'
#' @param pecan_settings List containing PEcAn settings including host configuration.
#' @param function_artifact Character string specifying the name of the targets function object.
#' @param args_artifact Character string specifying the name of the targets arguments object.
#' @param task_id Character string specifying the task identifier.
#' @param apptainer Character string specifying the Apptainer container path (optional).
#' @param dependencies Optional parameter for dependency tracking (unused).
#' @param conda_env Character string specifying the conda environment name (optional).
#'
#' @return Named list containing job IDs for the submitted SLURM jobs.
#'
#' @details
#' This function creates a SLURM batch script that executes a targets function remotely.
#' It supports both Apptainer containers and conda environments. The function_artifact and
#' args_artifact should be the string names of targets objects, not the objects themselves.
#' The function generates a batch script, submits it via sbatch, and returns the job IDs.
#'
#' @examples
#' \dontrun{
#' job_ids <- targets_abstract_sbatch_exec(pecan_settings, "my_func", "my_args", "task1")
#' }
#'
#' @export
targets_abstract_sbatch_exec <- function(pecan_settings, function_artifact, args_artifact, task_id, apptainer=NULL, dependencies = NULL, conda_env=NULL) {
    if (!is.character(function_artifact) || !is.character(args_artifact)) {
        print("Remember - function_artifact and/or args_artifact should be the string name of a targets object of a function entity, not the function entity itself")
        return(FALSE)
    }
    slurm_output_file = paste0("slurm_command_", task_id, ".sh")
    file_content = sbatch_header_standard(apptainer=apptainer)
    if (!is.null(conda_env)) {
        file_content = paste0(file_content, ' conda run -n ', conda_env, ' ')
    }
    if (!is.null(apptainer)) {
        file_content = paste0(file_content, ' apptainer run ', apptainer)
    }

    file_content = paste0(file_content, ' Rscript -e "library(targets)" -e "abstract_function=targets::tar_read(', function_artifact, ')" -e "abstract_args=targets::tar_read(', args_artifact, ')" -e "do.call(abstract_function, abstract_args)"')
    writeLines(file_content, slurm_output_file)
    out = system2("sbatch", slurm_output_file, stdout = TRUE, stderr = TRUE)
    print(paste0("Output from sbatch command is: ", out))
    print(paste0("System will use this pattern: ", pecan_settings$host$qsub.jobid ))
    jobids = list()
    # submitted_jobid = sub(pecan_settings$host$qsub.jobid, '\\1', out)
    jobids[task_id] <- PEcAn.remote::qsub_get_jobid(
        out = out[length(out)],
        qsub.jobid = pecan_settings$host$qsub.jobid,
        stop.on.error = stop.on.error)
    # print(paste0("System thinks the jobid is: ", submitted_jobid))
    return(jobids)
}

targets_sbatch_exec <- function(qsub_pattern, function_artifact, args_artifact, task_id, apptainer=NULL, dependencies = NULL, conda_env=NULL) {
    if (!is.character(function_artifact) || !is.character(args_artifact)) {
        print("Remember - function_artifact and/or args_artifact should be the string name of a targets object of a function entity, not the function entity itself")
        return(FALSE)
    }
    slurm_output_file = paste0("slurm_command_", task_id, ".sh")
    file_content = sbatch_header_standard(apptainer=apptainer)
    if (!is.null(conda_env)) {
        file_content = paste0(file_content, ' conda run -n ', conda_env, ' ')
    }
    if (!is.null(apptainer)) {
        file_content = paste0(file_content, ' apptainer run ', apptainer)
    }

    file_content = paste0(file_content, ' Rscript -e "library(targets)" -e "abstract_function=targets::tar_read(', function_artifact, ')" -e "abstract_args=targets::tar_read(', args_artifact, ')" -e "do.call(abstract_function, abstract_args)"')
    writeLines(file_content, slurm_output_file)
    out = system2("sbatch", slurm_output_file, stdout = TRUE, stderr = TRUE)
    print(paste0(out))
    jobids = list()
    # submitted_jobid = sub(pecan_settings$host$qsub.jobid, '\\1', out)
    jobids[task_id] <- PEcAn.remote::qsub_get_jobid(
        out = out[length(out)],
        qsub.jobid = qsub_pattern,
        stop.on.error = stop.on.error)
    # print(paste0("System thinks the jobid is: ", submitted_jobid))
    return(jobids)
}

#' Targets Source-based SLURM Batch Execution
#'
#' Executes a function loaded via source() remotely via SLURM batch job with optional containerization.
#'
#' @param pecan_settings List containing PEcAn settings including host configuration.
#' @param function_artifact Character string specifying the name of the function within the node's calling namespace.
#' @param args_artifact Character string specifying the name of the targets arguments object.
#' @param task_id Character string specifying the task identifier.
#' @param apptainer Character string specifying the Apptainer container path (optional).
#' @param dependencies Optional parameter for dependency tracking (unused).
#' @param conda_env Character string specifying the conda environment name (optional).
#' @param functional_source Optional character string path to a file to be loaded via source() (optional).
#'
#' @return Named list containing job IDs for the submitted SLURM jobs.
#'
#' @details
#' This function creates a SLURM batch script that executes a function remotely.
#' It supports both Apptainer containers and conda environments. The function_artifact must be a string
#' variable and the function specified must exist in the calling namespace on the compute node. The
#' args_artifact should be the string name of a previously-returned targets object, (not the variable object itself).
#' The function generates a batch script, submits it via sbatch, and returns the job IDs.
#'
#' @examples
#' \dontrun{
#' job_ids <- targets_abstract_sbatch_exec(pecan_settings, "my_func", "my_args", "task1")
#' }
#'
#' @export
targets_abstract_args_sbatch_exec <- function(pecan_settings, function_artifact, args_artifact, task_id, apptainer=NULL, dependencies = NULL, conda_env=NULL, functional_source=NULL) {
    # the biggest difference between this method of execution (sourcing the function file) is that this is done at runtime within the node
    # this means that targets sees the path to the file, but not the file contents
    # we can therefore reference code outside the memory space of this R process (or any R process)
    # but: targets doesn't see this code. if this code changes, if this code is user's and is wobbly, targets won't know about it.
    # returning the function which is called via the targets framework incorporates it into target's smart re-eval
    # thats the benefit. This is a little more simple, but works fine.
    if (!is.character(function_artifact) || !is.character(args_artifact)) {
        print("Remember - function_artifact and/or args_artifact should be the string name of a targets object of a function entity, not the function entity itself")
        return(FALSE)
    }
    # Construct slurm batch file
    slurm_output_file = paste0("slurm_command_", task_id, ".sh")
    file_content = sbatch_header_standard(apptainer=apptainer)
    if (!is.null(conda_env)) {
        file_content = paste0(file_content, ' conda run -n ', conda_env, ' ')
    }
    if (!is.null(apptainer)) {
        file_content = paste0(file_content, ' apptainer run ', apptainer)
    }

    file_content = paste0(file_content, ' Rscript -e "library(targets)" ')
    if(!is.null(functional_source)){
        file_content = paste0(file_content, '-e "source(\'', functional_source, '\')" ')
    }
    file_content = paste0(file_content, '-e "abstract_args=targets::tar_read(', args_artifact, ')" ')
    file_content = paste0(file_content, '-e "do.call(', function_artifact,', abstract_args)"')
    writeLines(file_content, slurm_output_file)

    # Submit slurm batch file; leverages PEcAn.remote for monitoring
    out = system2("sbatch", slurm_output_file, stdout = TRUE, stderr = TRUE)
    print(paste0(out))
    # print(paste0("Output from sbatch command is: ", out))
    # print(paste0("System will use this pattern: ", pecan_settings$host$qsub.jobid ))
    jobids = list()
    # submitted_jobid = sub(pecan_settings$host$qsub.jobid, '\\1', out)
    jobids[task_id] <- PEcAn.remote::qsub_get_jobid(
        out = out[length(out)],
        qsub.jobid = pecan_settings$host$qsub.jobid,
        stop.on.error = stop.on.error)
    # print(paste0("System thinks the jobid is: ", submitted_jobid))
    return(jobids)
}

#' Targets Based Local Execution
#'
#' Executes a targets function locally using a shell script.
#'
#' @param function_artifact Character string specifying the name of the targets function object.
#' @param args_artifact Character string specifying the name of the targets arguments object.
#' @param task_id Character string specifying the task identifier.
#' @param dependencies Optional parameter for dependency tracking (unused).
#'
#' @return Logical TRUE when execution completes.
#'
#' @details
#' This function is the local execution equivalent of targets_abstract_sbatch_exec.
#' It creates a shell script that executes a targets function locally and runs it via bash.
#' The function_artifact and args_artifact should be the string names of targets objects.
#'
#' @examples
#' \dontrun{
#' result <- targets_based_local_exec("my_func", "my_args", "task1")
#' }
#'
#' @export
targets_based_containerized_local_exec <- function(pecan_settings, function_artifact, args_artifact, task_id, apptainer=NULL, dependencies = NULL, conda_env=NULL) {
    # this function is NOT silly. It allows us to execute code on the local node, but within an apptainer!
    if (!is.character(function_artifact) || !is.character(args_artifact)) {
        print("Remember - function_artifact and/or args_artifact should be the string name of a targets object of a function entity, not the function entity itself")
        return(FALSE)
    }
    local_output_file = paste0("local_command_", task_id, ".sh")
    file_content=""
    if (!is.null(apptainer)) {
        file_content = paste0(file_content, ' apptainer run ', apptainer)
    }
    file_content = paste0(file_content, ' Rscript -e "library(targets)" -e "abstract_function=targets::tar_read(', function_artifact, ')" -e "abstract_args=targets::tar_read(', args_artifact, ')" -e "do.call(abstract_function, abstract_args)"')
    writeLines(file_content, local_output_file)
    system(paste0("bash ", local_output_file))
    return(TRUE)
}

targets_sourcing_test <- function(string_to_print="DefaultString") {
    print(paste0(string_to_print))
    return(string_to_print)
}

targets_sourcing_test_encapsulate <- function(func_name=NULL, string_to_print=NULL, task_id, targets_code_file_obj_name=NULL, apptainer=NULL, dependencies = NULL) {

    local_output_file = paste0("local_command_", task_id, ".sh")
    file_content=""
    if (!is.null(apptainer)) {
        file_content = paste0(file_content, ' apptainer run ', apptainer)
    }

    file_content = paste0(file_content, ' Rscript -e "library(targets)" ')
    
    file_content = paste0(file_content, '-e "source(\'', targets_code_file_obj_name, '\')" ')
    
    # file_content = paste0(file_content, '-e "abstract_args=targets::tar_read(', args_artifact, ')" ')
    # file_content = paste0(file_content, '-e "function_result=do.call(', function_artifact,', abstract_args)" ')
    file_content = paste0(file_content, '-e "', func_name, '(string_to_print=\'', string_to_print,'\')" ')
    get_response=FALSE
    if(get_response){
        file_content = paste0(file_content, '-e "print(function_result)" ')
        writeLines(file_content, local_output_file)
        outcome=system(paste0("bash ", local_output_file), intern = TRUE)
    }else{
        writeLines(file_content, local_output_file)
        outcome=system(paste0("bash ", local_output_file))
    }

    return(outcome)
}


targets_based_sourced_containerized_local_exec <- function(function_artifact, args_artifact, task_id, apptainer=NULL, dependencies = NULL, conda_env=NULL, functional_source=NULL) {
    # this function is NOT silly. It allows us to execute code on the local node, but within an apptainer!
    if (!is.character(function_artifact) || !is.character(args_artifact)) {
        print("Remember - function_artifact and/or args_artifact should be the string name of a targets object of a function entity, not the function entity itself")
        return(FALSE)
    }
    local_output_file = paste0("local_command_", task_id, ".sh")
    file_content=""
    if (!is.null(apptainer)) {
        file_content = paste0(file_content, ' apptainer run ', apptainer)
    }

    file_content = paste0(file_content, ' Rscript -e "library(targets)" ')
    if(!is.null(functional_source)){
        file_content = paste0(file_content, '-e "source(\'', functional_source, '\')" ')
    }
    file_content = paste0(file_content, '-e "abstract_args=targets::tar_read(', args_artifact, ')" ')
    file_content = paste0(file_content, '-e "function_result=do.call(', function_artifact,', abstract_args)" ')
    get_response=TRUE
    if(get_response){
        file_content = paste0(file_content, '-e "print(function_result)" ')
        writeLines(file_content, local_output_file)
        outcome=system(paste0("bash ", local_output_file), intern = TRUE)
    }else{
        writeLines(file_content, local_output_file)
        outcome=system(paste0("bash ", local_output_file))
    }

    return(outcome)
}


step__run_model_2a <- function(pecan_settings = NULL, container = NULL, dependencies = NULL, use_abstraction=TRUE){
      list(
            tar_target_raw(
                "pecan_run_model_function",
                quote(targets_function_abstraction(function_name = "run_model_2a")), 
                deps = dependencies
            ),
            tar_target_raw(
                "pecan_run_model_arguments",
                substitute(
                    targets_argument_abstraction(
                        argument_object = list(
                            settings = pecan_settings_raw
                        )
                    ),
                    env = list(pecan_settings_raw = pecan_settings)
                ),
                deps = c(dependencies, "pecan_run_model_function")
            ),
            # run the abstracted function on the abstracted arguments via slurm
            tar_target_raw(
                "pecan_run_model_2a_job_submission", 
                substitute(
                    targets_abstract_sbatch_exec(
                        pecan_settings=pecan_settings_raw,
                        function_artifact="pecan_run_model_function", 
                        args_artifact="pecan_run_model_arguments", 
                        task_id=uuid::UUIDgenerate(), 
                        apptainer=apptainer_reference_raw, 
                        dependencies=c()
                    ),
                    env = list(pecan_settings_raw = pecan_settings, apptainer_reference_raw = NULL)
                ),
                deps = c(dependencies, "pecan_run_model_arguments")
            ),
            tar_target_raw(
                "run_model_2a_job_outcome",
                quote(pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_run_model_2a_job_submission))
            )
        )
}

run_model_2a <- function(settings = NULL){
    library(PEcAn.settings)
    library(PEcAn.workflow)
    library(PEcAn.logger)
    # Write model specific configs
    stop_on_error = TRUE
    PEcAn.workflow::runModule_start_model_runs(settings,
                                                stop.on.error = stop_on_error)


    # Get results of model runs
    # this function is arguably too chatty, so we'll suppress
    # INFO-level log output for this step.
    loglevel <- PEcAn.logger::logger.setLevel("WARN")
    
    runModule.get.results(settings)

    PEcAn.logger::logger.setLevel(loglevel)


    # Run sensitivity analysis and variance decomposition on model output
    runModule.run.sensitivity.analysis(settings)

    print("---------- PEcAn Workflow Complete ----------")

}

step__build_pecan_xml <- function(workflow_settings = NULL, template_file = NULL, dependencies = NULL){
      list(
            tar_target_raw(
                "pecan_build_xml_function",
                quote(targets_function_abstraction(function_name = "build_pecan_xml"))
            ),
            tar_target_raw(
                "pecan_build_xml_arguments",
                quote(targets_argument_abstraction(
                    argument_object = list(
                        orchestration_xml = workflow_settings, 
                        template_file = pecan_template_file,  
                        dependencies = c("site_info_file", "IC_files", "pecan_template_file")
                    )
                ))
            ),
            tar_target_raw("pecan_xml_file", quote(pecan_xml_path), format = "file"),
            tar_target_raw("pecan_settings", quote(PEcAn.settings::read.settings(pecan_xml_file))),
            # run the abstracted function on the abstracted arguments via slurm
            tar_target_raw(
                "pecan_xml_build_job_submission", 
                quote(targets_abstract_sbatch_exec(
                    pecan_settings=pecan_settings,
                    function_artifact="pecan_build_xml_function", 
                    args_artifact="pecan_build_xml_arguments", 
                    task_id=uuid::UUIDgenerate(), 
                    apptainer=apptainer_reference, 
                    dependencies=c(pecan_build_xml_arguments)
                ))
            ),
            tar_target_raw(
                "build_xml_job_outcome",
                quote(pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_xml_build_job_submission))
            ),
            tar_target_raw("pecan_built_xml_file", quote("./pecan_built_config.xml"), format = "file", deps=c("build_xml_job_outcome")),
            tar_target_raw("pecan_built_xml", quote(PEcAn.settings::read.settings(pecan_built_xml_file)), deps=c("pecan_built_xml_file"))
        )
}

build_pecan_xml <- function(orchestration_xml = NULL, template_file = NULL, dependencies = NULL) {
    library(PEcAn.settings)

    site_info <- read.csv(orchestration_xml$site.info.file)
    stopifnot(
    length(unique(site_info$id)) == nrow(site_info),
    all(site_info$lat > 0), # just to simplify grid naming below
    all(site_info$lon < 0)
    )
    site_info <- site_info |>
    dplyr::mutate(
        # match locations to half-degree ERA5 grid cell centers
        # CAUTION: Calculation only correct when all lats are N and all lons are W!
        ERA5_grid_cell = paste0(
        ((lat + 0.25) %/% 0.5) * 0.5, "N_",
        ((abs(lon) + 0.25) %/% 0.5) * 0.5, "W"
        )
    )

    settings <- read.settings(template_file) |>
    setDates(orchestration_xml$start.date, orchestration_xml$end.date)

    settings$ensemble$size <- orchestration_xml$n.ens
    settings$run$inputs$poolinitcond$ensemble <- orchestration_xml$n.ens

    # Hack: setEnsemblePaths leaves all path components other than siteid
    # identical across sites.
    # To use site-specific grid id, I'll string-replace each siteid
    id2grid <- function(s) {
    # replacing in place to preserve names (easier than thinking)
    for (p in seq_along(s$run$inputs$met$path)) {
        s$run$inputs$met$path[[p]] <- gsub(
        pattern = s$run$site$id,
        replacement = s$run$site$ERA5_grid_cell,
        x = s$run$inputs$met$path[[p]]
        )
    }
    s
    }

    settings <- settings |>
    createMultiSiteSettings(site_info) |>
    setEnsemblePaths(
        n_reps = orchestration_xml$n.met,
        input_type = "met",
        path = orchestration_xml$met.dir,
        d1 = orchestration_xml$start.date,
        d2 = orchestration_xml$end.date,
        # TODO use caladapt when ready
        # path_template = "{path}/{id}/caladapt.{id}.{n}.{d1}.{d2}.nc"
        path_template = "{path}/{id}/ERA5.{n}.{d1}.{d2}.clim"
    ) |>
    papply(id2grid) |>
    setEnsemblePaths(
        n_reps = orchestration_xml$n.ens,
        input_type = "poolinitcond",
        path = orchestration_xml$ic.dir,
        path_template = "{path}/{id}/IC_site_{id}_{n}.nc"
    )

    # Hack: Work around a regression in PEcAn.uncertainty 1.8.2 by specifying
    # PFT outdirs explicitly (even though they go unused in this workflow)
    settings$pfts <- settings$pfts |>
    lapply(\(x) {
        x$outdir <- file.path(settings$outdir, "pfts", x$name)
        x
    })

    write.settings(
    settings,
    outputfile = basename(orchestration_xml$output.xml),
    outputdir = dirname(orchestration_xml$output.xml)
    )

    return(settings)
}

step__build_ic_files <- function(workflow_settings = NULL, orchestration_settings = NULL, container = NULL, dependencies = NULL){
    list(
            tar_target_raw(
                "pecan_build_ic_files_function",
                quote(targets_function_abstraction(function_name = "build_ic_files")),
                deps = c(dependencies)
            ),
            tar_target_raw(
                "pecan_build_ic_files_arguments",
                substitute(targets_argument_abstraction(
                    argument_object = list(
                        orchestration_xml = workflow_settings_raw
                    )
                ),
                env = list(workflow_settings_raw = workflow_settings)
                ),
                deps = c(dependencies)
            ),

            # run the abstracted function on the abstracted arguments via slurm
            tar_target_raw(
                "pecan_build_ic_files_job_submission", 
                substitute(targets_sbatch_exec(
                    qsub_pattern=qsub_pattern_raw,
                    function_artifact="pecan_build_ic_files_function", 
                    args_artifact="pecan_build_ic_files_arguments", 
                    task_id=uuid::UUIDgenerate(), 
                    apptainer=container_raw
                ),
                env = list(container_raw = container, qsub_pattern_raw=orchestration_settings$orchestration$distributed.compute.adapter$qsub.jobid)
                ),
                deps = c("pecan_build_ic_files_arguments", dependencies)
            ),
            tar_target_raw(
                "build_ic_files_job_outcome",
                substitute(monitor_cluster_job(distribution_adapter=adapter_raw, job_id_list=pecan_build_ic_files_job_submission),
                env = list(
                    adapter_raw=orchestration_settings$orchestration$distributed.compute.adapter
                    )
                ),
                deps = c("pecan_build_ic_files_job_submission", dependencies)
            )
        )
}

build_ic_files <- function(orchestration_xml = NULL){
    # adapted from CB's 02_ic_build.R 
    set.seed(6824625)
    library(tidyverse)

    # Do parallel processing in separate R processes instead of via forking
    # (without this the {furrr} calls inside soilgrids_soilC_extract
    # 	were crashing for me. TODO check if this is machine-specific)
    op <- options(parallelly.fork.enable = FALSE)
    on.exit(options(op))

    # if (!dir.exists(args$data_dir)) dir.create(args$data_dir, recursive = TRUE)
    if (!dir.exists(orchestration_xml$data.dir)) dir.create(orchestration_xml$data.dir, recursive = TRUE)

    # split up comma-separated options
    params_read_from_pft <- strsplit(orchestration_xml$params.from.pft, ",")[[1]]
    landtrendr_raw_files <- strsplit(orchestration_xml$landtrendr.raw.files, ",")[[1]]
    additional_params <- orchestration_xml$additional.params |>
    str_match_all("([^=]+)=([^,]+),?") |>
    _[[1]] |>
    (\(x) setNames(as.list(x[, 3]), x[, 2]))() |>
    as.data.frame() |>
    mutate(across(starts_with("param"), as.numeric))

    site_info <- read.csv(
    orchestration_xml$site.info.file,
    colClasses = c(field_id = "character")
    )
    site_info$start_date <- orchestration_xml$start.date
    site_info$LAI_date <- orchestration_xml$run_LAI.date


    PEcAn.logger::logger.info("Getting estimated soil carbon from SoilGrids 250m")
    # NB this takes several minutes to run
    # csv filename is hardcoded by fn
    soilc_csv_path <- file.path(orchestration_xml$data.dir, "soilgrids_soilC_data.csv")
    if (file.exists(soilc_csv_path)) {
        PEcAn.logger::logger.info("using existing soil C file", soilc_csv_path)
        soil_carbon_est <- read.csv(soilc_csv_path, check.names = FALSE)
        sites_needing_soilc <- site_info |>
            filter(!id %in% soil_carbon_est$Site_ID)
    } else {
        soil_carbon_est <- NULL
        sites_needing_soilc <- site_info
    }
    nsoilc <- nrow(sites_needing_soilc)
    if (nsoilc > 0) {
    PEcAn.logger::logger.info("Retrieving soil C for", nsoilc, "sites")
    new_soil_carbon <- PEcAn.data.land::soilgrids_soilC_extract(
        sites_needing_soilc |> select(site_id = id, site_name = name, lat, lon),
        outdir = orchestration_xml$data.dir
    )
    soil_carbon_est <- bind_rows(soil_carbon_est, new_soil_carbon) |>
        arrange(Site_ID)
    write.csv(soil_carbon_est, soilc_csv_path, row.names = FALSE)
    }



    PEcAn.logger::logger.info("Soil moisture")
    sm_outdir <- file.path(orchestration_xml$data.dir, "soil_moisture") |>
    normalizePath(mustWork = FALSE)
    sm_csv_path <- file.path(orchestration_xml$data.dir, "sm.csv") # name is hardcorded by fn
    if (file.exists(sm_csv_path)) {
    PEcAn.logger::logger.info("using existing soil moisture file", sm_csv_path)
    soil_moisture_est <- read.csv(sm_csv_path)
    sites_needing_soilmoist <- site_info |>
        filter(!id %in% soil_moisture_est$site.id)
    } else {
    soil_moisture_est <- NULL
    sites_needing_soilmoist <- site_info
    }
    nmoist <- nrow(sites_needing_soilmoist)
    if (nmoist > 0) {
    PEcAn.logger::logger.info("Retrieving soil moisture for", nmoist, "sites")
    if (!dir.exists(sm_outdir)) dir.create(sm_outdir)
    new_soil_moisture <- PEcAn.data.land::extract_SM_CDS(
        site_info = sites_needing_soilmoist |>
        dplyr::select(site_id = id, lat, lon),
        time.points = as.Date(site_info$start_date[[1]]),
        in.path = sm_outdir,
        out.path = dirname(sm_csv_path),
        allow.download = TRUE
    )
    soil_moisture_est <- bind_rows(soil_moisture_est, new_soil_moisture) |>
        arrange(site.id)
    write.csv(soil_moisture_est, sm_csv_path, row.names = FALSE)
    }

    PEcAn.logger::logger.info("LAI")
    # Note that this currently creates *two* CSVs:
    # - "LAI.csv", with values from each available day inside the search window
    #   (filename is hardcoded inside MODIS_LAI_PREP())
    # - this path, aggregated to one row per site
    # TODO consider cleaning this up -- eg reprocess from LAI.csv on the fly?
    lai_csv_path <- file.path(orchestration_xml$data.dir, "LAI_bysite.csv")
    if (file.exists(lai_csv_path)) {
    PEcAn.logger::logger.info("using existing LAI file", lai_csv_path)
    lai_est <- read.csv(lai_csv_path, check.names = FALSE) # TODO edit MODIS_LAI_prep to use valid colnames?
    sites_needing_lai <- site_info |>
        filter(!id %in% lai_est$site_id)
    } else {
    lai_est <- NULL
    sites_needing_lai <- site_info
    }
    nlai <- nrow(sites_needing_lai)
    if (nlai > 0) {
    PEcAn.logger::logger.info("Retrieving LAI for", nlai, "sites")
    lai_res <- PEcAn.data.remote::MODIS_LAI_prep(
        site_info = sites_needing_lai |> dplyr::select(site_id = id, lat, lon),
        time_points = as.Date(site_info$LAI_date[[1]]),
        outdir = orchestration_xml$data.dir,
        export_csv = TRUE,
        skip_download = FALSE
    )
    lai_est <- bind_rows(lai_est, lai_res$LAI_Output) |>
        arrange(site_id)
    write.csv(lai_est, lai_csv_path, row.names = FALSE)
    }


    PEcAn.logger::logger.info("Aboveground biomass from LandTrendr")

    landtrendr_agb_outdir <- orchestration_xml$data.dir

    landtrendr_csv_path <- file.path(
    landtrendr_agb_outdir,
    "aboveground_biomass_landtrendr.csv"
    )
    if (file.exists(landtrendr_csv_path)) {
    PEcAn.logger::logger.info(
        "using existing LandTrendr AGB file",
        landtrendr_csv_path
    )
    agb_est <- read.csv(landtrendr_csv_path)
    sites_needing_agb <- site_info |>
        filter(!id %in% agb_est$site_id)
    } else {
    agb_est <- NULL
    sites_needing_agb <- site_info
    }
    nagb <- nrow(sites_needing_agb)
    if (nagb > 0) {
    PEcAn.logger::logger.info("Retrieving aboveground biomass for", nagb, "sites")
    lt_med_path <- grep("_median.tif$", landtrendr_raw_files, value = TRUE)
    lt_sd_path <- grep("_stdv.tif$", landtrendr_raw_files, value = TRUE)
    stopifnot(
        all(file.exists(landtrendr_raw_files)),
        length(lt_med_path) == 1,
        length(lt_sd_path) == 1
    )
    lt_med <- terra::rast(lt_med_path)
    lt_sd <- terra::rast(lt_sd_path)
    field_shp <- terra::vect(orchestration_xml$field.shape.path)

    site_bnds <- field_shp[field_shp$UniqueID %in% sites_needing_agb$field_id, ] |>
        terra::project(lt_med)

    # Check for unmatched sites
    # TODO is stopping here too strict? Could reduce to warning if needed
    stopifnot(all(sites_needing_agb$field_id %in% site_bnds$UniqueID))

    new_agb <- lt_med |>
        terra::extract(x = _, y = site_bnds, fun = mean, bind = TRUE) |>
        terra::extract(x = lt_sd, y = _, fun = mean, bind = TRUE) |>
        as.data.frame() |>
        left_join(sites_needing_agb, by = c("UniqueID" = "field_id")) |>
        dplyr::select(
        site_id = id,
        AGB_median_Mg_ha = ends_with("median"),
        AGB_sd = ends_with("stdv")
        ) |>
        mutate(across(where(is.numeric), \(x) signif(x, 5)))
    agb_est <- bind_rows(agb_est, new_agb) |>
        arrange(site_id)
    write.csv(agb_est, landtrendr_csv_path, row.names = FALSE)
    }

    # ---------------------------------------------------------
    # Great, we have estimates for some variables.
    # Now let's make IC files!

    PEcAn.logger::logger.info("Building IC files")


    initial_condition_estimated <- dplyr::bind_rows(
    soil_organic_carbon_content = soil_carbon_est |>
        dplyr::select(
        site_id = Site_ID,
        mean = `Total_soilC_0-30cm`,
        sd = `Std_soilC_0-30cm`
        ) |>
        dplyr::mutate(
        lower_bound = 0,
        upper_bound = Inf
        ),
    SoilMoistFrac = soil_moisture_est |>
        dplyr::select(
        site_id = site.id,
        mean = sm.mean,
        sd = sm.uncertainty
        ) |>
        # Note that we pass this as a percent -- yes, Sipnet wants a fraction,
        # but write.configs.SIPNET hardcodes a division by 100.
        # TODO consider modifying write.configs.SIPNET
        #   to not convert when 0 > SoilMoistFrac > 1
        dplyr::mutate(
        lower_bound = 0,
        upper_bound = 100
        ),
    LAI = lai_est |>
        dplyr::select(
        site_id = site_id,
        mean = ends_with("LAI"),
        sd = ends_with("SD")
        ) |>
        dplyr::mutate(
        lower_bound = 0,
        upper_bound = Inf
        ),
    AbvGrndBiomass = agb_est |> # NB this assumes AGB ~= AGB woody
        dplyr::select(
        site_id = site_id,
        mean = AGB_median_Mg_ha,
        sd = AGB_sd
        ) |>
        dplyr::mutate(across(
        c("mean", "sd"),
        ~ PEcAn.utils::ud_convert(.x, "Mg ha-1", "kg m-2")
        )) |>
        dplyr::mutate(
        lower_bound = 0,
        upper_bound = Inf
        ),
    .id = "variable"
    )
    write.csv(
    initial_condition_estimated,
    file.path(orchestration_xml$data.dir, "IC_means.csv"),
    row.names = FALSE
    )



    # read params from PFTs

    sample_distn <- function(varname, distn, parama, paramb, ..., n) {
        if (distn == "exp") {
            samp <- rexp(n, parama)
        } else {
            rfn <- get(paste0("r", distn))
            samp <- rfn(n, parama, paramb)
        }

        data.frame(samp) |>
            setNames(varname)
    }

    sample_pft <- function(path,
                        vars = params_read_from_pft,
                        n_samples = orchestration_xml$ic.ensemble.size) {
        e <- new.env()
        load(file.path(path, "post.distns.Rdata"), envir = e)
        e$post.distns |>
            tibble::rownames_to_column("varname") |>
            dplyr::select(-"n") |> # this is num obs used in posterior; conflicts with n = ens size when sampling
            dplyr::filter(varname %in% vars) |>
            dplyr::bind_rows(additional_params) |>
            purrr::pmap(sample_distn, n = n_samples) |>
            purrr::list_cbind() |>
            tibble::rowid_to_column("replicate")
    }

    pft_var_samples <- site_info |>
    mutate(pft_path = file.path(orchestration_xml$pft.dir, site.pft)) |>
    nest_by(id) |>
    mutate(samp = purrr::map(data$pft_path, sample_pft)) |>
    unnest(samp) |>
    dplyr::select(-"data") |>
    dplyr::rename(site_id = id)


    ic_sample_draws <- function(df, n = 100, ...) {
        stopifnot(nrow(df) == 1)
        data.frame(
            replicate = seq_len(n),
            sample = truncnorm::rtruncnorm(
            n = n,
            a = df$lower_bound,
            b = df$upper_bound,
            mean = df$mean,
            sd = df$sd
            )
        )
    }

    ic_samples <- initial_condition_estimated |>
    dplyr::filter(site_id %in% site_info$id) |>
    dplyr::group_by(site_id, variable) |>
    dplyr::group_modify(ic_sample_draws, n = as.numeric(orchestration_xml$ic.ensemble.size)) |>
    tidyr::pivot_wider(names_from = variable, values_from = sample) |>
    dplyr::left_join(pft_var_samples, by = c("site_id", "replicate")) |>
    dplyr::mutate(
        AbvGrndWood = AbvGrndBiomass * wood_carbon_fraction,
        leaf_carbon_content = tidyr::replace_na(LAI, 0) / SLA * (leafC / 100),
        wood_carbon_content = pmax(AbvGrndWood - leaf_carbon_content, 0)
    )

    ic_names <- colnames(ic_samples)
    std_names <- c("site_id", "replicate", PEcAn.utils::standard_vars$Variable.Name)
    nonstd_names <- ic_names[!ic_names %in% std_names]
    if (length(nonstd_names) > 0) {
    PEcAn.logger::logger.debug(
        "Not writing these nonstandard variables to the IC files:", nonstd_names
    )
    ic_samples <- ic_samples |> dplyr::select(-any_of(nonstd_names))
    }

    file.path(orchestration_xml$ic.outdir, site_info$id) |>
    unique() |>
    purrr::walk(dir.create, recursive = TRUE)

    ic_samples |>
    dplyr::group_by(site_id, replicate) |>
    dplyr::group_walk(
        ~ PEcAn.SIPNET::veg2model.SIPNET(
        outfolder = file.path(orchestration_xml$ic.outdir, .y$site_id),
        poolinfo = list(
            dims = list(time = 1),
            vals = .x
        ),
        siteid = .y$site_id,
        ens = .y$replicate
        )
    )

    PEcAn.logger::logger.info("IC files written to", orchestration_xml$ic.outdir)
    PEcAn.logger::logger.info("Done")
}

check_directory_exists <- function(directory_path, stop_on_nonexistent=FALSE) {
    if (!dir.exists(directory_path)) {
        if (stop_on_nonexistent) {
            print(paste0("Directory: ", directory_path, " doesn't exist."))
            stop("This path is required to proceed. Exiting.")
        }
        return(FALSE)
    }
    return(TRUE)
}


workflow_run_directory_setup <- function(orchestration_settings = NULL, workflow_name = NULL) {
    workflow_run_directory = orchestration_settings$orchestration$workflow.base.run.directory
    workflow_settings = orchestration_settings$orchestration[[workflow_name]]
    run_identifier = workflow_settings$run.identifier

    if(is.null(workflow_run_directory)){
        stop("Cannot continue without a workflow run directory - check XML configuration.")
    }
    if (!dir.exists(workflow_run_directory)) {
        dir.create(workflow_run_directory, recursive = TRUE)
    }
    analysis_run_id = paste0("analysis_run_", uuid::UUIDgenerate() )
    if (is.null(run_identifier)) {
        print(paste("Analysis run id specified:", analysis_run_id))
    } else {
        print(paste("Analysis run id specified:", run_identifier))
        analysis_run_id = run_identifier
    }
    analysis_run_directory = file.path(workflow_run_directory, analysis_run_id)
    if (!check_directory_exists(analysis_run_directory, stop_on_nonexistent=FALSE)) {
        dir.create(analysis_run_directory, recursive = TRUE)
    }
    return(list(run_dir=analysis_run_directory, run_id=analysis_run_id))
}


parse_orchestration_xml <- function(orchestration_xml_path=NULL) {
    if(is.null(orchestration_xml_path)){
        stop("must provide orchestration XML path for parsing.")
    }
    orchestration_xml = XML::xmlParse(orchestration_xml_path)
    orchestration_xml <- XML::xmlToList(orchestration_xml)
    return(orchestration_xml)
}

check_orchestration_keys = function(orchestration_xml = NULL, key_list = NULL, required=TRUE){
  missing_values=FALSE
  for(key in key_list){
    if(key %in% names(orchestration_xml)){
        # warning(paste0("Found key: ", key))
    }else{
        missing_values=TRUE
    }
  }
  if (missing_values && required) {
    stop("One or more needed keys are not present in orchestration configuration. Please see prior warnings.")
  } else if (missing_values) {
    return(FALSE)
  }
  return(TRUE)
}

#' @title Example target factory.
#' @description Define 3 targets:
#' 1. Track the user-supplied data file.
#' 2. Read the data using `read_data()` (defined elsewhere).
#' 3. Fit a model to the data using `fit_model()` (defined elsewhere).
#' @return A list of target objects.
#' @export
#' @param file Character, data file path.
# apptainer_factory <- function(orchestration_settings, workflow_name) {
apptainer_can_download <- function(apptainer_xml = NULL) {
    if(check_orchestration_keys(orchestration_xml = apptainer_xml, key_list = c("sif", "remote.url", "container.name", "tag"), required=FALSE)){
        # print("Missing required parameters in configuration to download apptainer. Required keys under apptainer: url, name, tag, sif")
        return(TRUE)
    }else{
        return(FALSE)
    }
}

apptainer_can_link <- function(source_directory = NULL, apptainer_xml = NULL) {
    if(check_orchestration_keys(orchestration_xml = apptainer_xml, key_list = c("sif"), required=FALSE)){
        if(!is.null(source_directory) && file.exists(file.path(paste0(source_directory, "/",apptainer_xml$sif)))){
            return(TRUE)
        }
    }
    return(FALSE)
}

step__resolve_apptainer <- function(apptainer_source_directory=NULL, workflow_xml=NULL) {
  # Strictly speaking, this argument munging is not necessary. The below unevaluated [quote()'ed] expression
  # is returned to the calling targets pipeline as it is - unevaluated
  # this means that the variables passed are not actually used - they aren't evaluated until runtime
  # so the variables aren't even bound until this step is evaluated within the calling namespace.
  apptainer_settings = workflow_xml$apptainer
  link = apptainer_can_link(source_directory=apptainer_source_directory, apptainer_xml=apptainer_settings)
  download = apptainer_can_download(apptainer_xml=apptainer_settings)
  system("module load apptainer")
  if(link){
    print("Attempting to link apptainer SIF.")
    list(
        tar_target_raw(
            "apptainer_reference", 
            reference_external_data_entity(
                external_workflow_directory=substitute(apptainer_source_value, env = list(apptainer_source_value = apptainer_source_directory)),
                external_name=apptainer_sif, 
                localized_name=apptainer_sif
            )
        )
    )
  }else if(download){
    print("Attempting to download apptainer.")
    list(
        tar_target_raw(
            "apptainer_reference", 
            pull_apptainer_container(
                apptainer_url_base=substitute(raw_apptainer_url, env = list(raw_apptainer_url = workflow_xml$apptainer$remote.url)),
                apptainer_image_name=substitute(raw_apptainer_name, env = list(raw_apptainer_name = workflow_xml$apptainer$container.name)),
                apptainer_tag=substitute(raw_apptainer_tag, env = list(raw_apptainer_tag = workflow_xml$apptainer$tag)),
                apptainer_disk_sif=substitute(raw_apptainer_sif, env = list(raw_apptainer_sif = workflow_xml$apptainer$sif))
            )
        )
    )
  }else{
    print(workflow_xml)
    stop("Failed to resolve apptainer - could not link or download container. Please check configuration XML.")
  }
}

step__link_data_by_name <- function(workflow_data_source_directory = NULL, target_artifact_names = c(), localized_name_list = c(), external_name_list = c()){
    target_list = list()
    if((length(localized_name_list) != length(target_artifact_names)) || (length(localized_name_list) != length(external_name_list))){
        stop("Cannot link internal names to external link targets with unequal length lists")
    }
    for(i in seq_along(localized_name_list)){
        target_list = append(target_list, 
            tar_target_raw(substitute(target_name, env = list(target_name = target_artifact_names[i])), 
                reference_external_data_entity(
                    external_workflow_directory=substitute(raw_data_source, env = list(raw_data_source = workflow_data_source_directory)),
                    external_name=substitute(external_name, env = list(external_name = external_name_list[i])),
                    localized_name=substitute(localized_name, env = list(localized_name = localized_name_list[i]))
                )
            )
        )
    }
    # print(target_list)
    target_list
}

step__run_distributed_write_configs <- function(pecan_settings=NULL, container=NULL, use_abstraction=TRUE, dependencies = NULL) {
    # note on substitution: when substitutions are needed inside of functions that must also be quoted, 
    # the solution is to expand the captured expression which has substitutions and to do all subs at once
    if(use_abstraction){
        list(
            tar_target_raw(
                "pecan_write_configs_function",
                quote(targets_function_abstraction(function_name = "pecan_write_configs")),
                deps = dependencies
            ),
            # create the abstraction of the pecan write configs arguments
            tar_target_raw(
                "pecan_write_configs_arguments",
                substitute(
                    targets_argument_abstraction(argument_object = list(pecan_settings=raw_pecan_settings, xml_file=raw_pecan_xml)), 
                    env = list(raw_pecan_settings = pecan_settings, raw_pecan_xml = pecan_settings)
                ),
                deps = dependencies
            ),
            tar_target_raw(
                "pecan_settings_job_submission", 
                substitute(targets_abstract_sbatch_exec(
                    pecan_settings=raw_pecan_settings,
                    function_artifact="pecan_write_configs_function", 
                    args_artifact="pecan_write_configs_arguments", 
                    task_id=uuid::UUIDgenerate(), 
                    apptainer=raw_apptainer, 
                    dependencies=c(pecan_continue)
                ), env=list(raw_pecan_settings = pecan_settings, raw_apptainer = container)),
                deps = dependencies
            ),
            tar_target_raw(
                "settings_job_outcome",
                quote(pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_settings_job_submission))
            )
        )
    }else{
        list(
            tar_target_raw(
                "pecan_write_configs_arguments",
                quote(targets_argument_abstraction(argument_object = list(pecan_settings=pecan_settings_prepared, xml_file=pecan_xml_file)))
            ),
            tar_target_raw(
            "pecan_settings_job_submission", 
            quote(
                targets_abstract_args_sbatch_exec(
                    pecan_settings=pecan_settings,
                    function_artifact="pecan_write_configs", 
                    args_artifact="pecan_write_configs_arguments", 
                    task_id=uuid::UUIDgenerate(), 
                    functional_source=function_sourcefile,
                    apptainer=apptainer_reference, 
                    dependencies=c(pecan_continue)
                )
            )
            ),
            tar_target_raw(
                "settings_job_outcome",
                quote(pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_settings_job_submission))
            )
        )
    }
}

step__create_clim_files <- function(pecan_settings=NULL, container=NULL, workflow_settings=NULL, dependencies = NULL, reference_path=NULL, data_raw=NULL, site_info=NULL) {
    site_sipnet_met_path <- normalizePath(workflow_settings$site.sipnet.met.path, mustWork = FALSE)
    list(
        tar_target_raw(
            "era5_site_combinations",
            substitute(
                build_era5_site_combinations_args(
                    site_info_file = site_info_file_raw,
                    start_date = start_date_raw,
                    end_date = end_date_raw,
                    reference_path = reference_era5_path_raw,
                    sipnet_met_path = site_sipnet_met_path_raw,
                    dependencies = c()
                ),
                env = list(
                    site_sipnet_met_path_raw = site_sipnet_met_path,
                    reference_era5_path_raw = reference_path,
                    site_info_file_raw = site_info,
                    start_date_raw = workflow_settings$start.date,
                    end_date_raw = workflow_settings$end.date
                )
            ),
            deps = substitute(raw_dependencies, env = list(raw_dependencies = dependencies))
        ),
        tar_target_raw(
            "era5_clim_create_args",
            substitute(
                targets_argument_abstraction(
                    argument_object = list(
                        site_combinations = era5_site_combinations,
                        site_era5_path = reference_era5_path_raw,
                        site_sipnet_met_path = site_sipnet_met_path_raw,
                        n_workers = 1,
                        dependencies=c()
                    )
                ),
                env = list(
                    site_sipnet_met_path_raw = site_sipnet_met_path,
                    reference_era5_path_raw = reference_path
                )
            ),
            deps = c("era5_site_combinations", dependencies)
        ),
        tar_target_raw(
            "era5_clim_output",
            substitute(
                targets_abstract_args_sbatch_exec(
                    pecan_settings=pecan_settings_raw,
                    function_artifact="convert_era5_nc_to_clim", 
                    args_artifact="era5_clim_create_args", 
                    task_id=uuid::UUIDgenerate(), 
                    apptainer= apptainer_reference_raw, 
                    dependencies = era5_clim_create_args,
                    functional_source = function_sourcefile
                ),
                env = list(
                    pecan_settings_raw = pecan_settings, 
                    apptainer_reference_raw = container
                )
            ),
            deps = c("era5_clim_create_args", dependencies)
        ),
        tar_target_raw(
            "era5_clim_conversion",
            substitute(
                pecan_monitor_cluster_job(
                    pecan_settings=pecan_settings_raw,
                    job_id_list=era5_clim_output
                ),
                env = list(
                    pecan_settings_raw = pecan_settings
                )
            ),
            deps = c("era5_clim_output", dependencies)
        )
    )
}

step__run_pecan_workflow <- function() {
    list(
        tar_target_raw(
            "ecosystem_settings",
            quote(pecan_start_ecosystem_model_runs(pecan_settings=pecan_settings, dependencies=c(settings_job_outcome)))
        ), 
        tar_target_raw(
            "model_results_settings",
            quote(pecan_get_model_results(pecan_settings=ecosystem_settings))
        ),
        tar_target_raw(
            "ensembled_results_settings", ## the sequential settings here serve to ensure these are run in sequence, rather than in parallel
            quote(pecan_run_ensemble_analysis(pecan_settings=model_results_settings))
        ),
        tar_target_raw(
            "sensitivity_settings",
            quote(pecan_run_sensitivity_analysis(pecan_settings=ensembled_results_settings))
        ),
        tar_target_raw(
            "complete_settings",
            quote(pecan_workflow_complete(pecan_settings=sensitivity_settings))
        )
    )
}
