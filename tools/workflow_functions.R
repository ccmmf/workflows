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
    pecan_settings <- PEcAn.settings::read.settings(xml_file)
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
        stop(paste("Local link path", local_link_path, "already exists"))
    }
    file.symlink(from=external_link_path, to=local_link_path)
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
#SBATCH --nodes=1                     # Number of nodes
#SBATCH --ntasks-per-node=1           # Number of tasks per node
#SBATCH --cpus-per-task=1             # Number of CPU cores per task
#SBATCH --time=1:00:00                # Maximum runtime (D-HH:MM:SS)

#Load necessary modules (if needed)
"
    if (!is.null(apptainer)) {
        header_string = paste0(header_string, "module load apptainer\n")
    }
    return(header_string)
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
targets_based_local_exec <- function(function_artifact, args_artifact, task_id, dependencies = NULL) {
    # this function is silly. really just the analogous execution method as slurm.
    local_output_file = paste0("local_command_", task_id, ".sh")
    file_content = paste0('Rscript -e "library(targets)" -e "abstract_function=targets::tar_read(', function_artifact, ')" -e "abstract_args=targets::tar_read(', args_artifact, ')" -e "do.call(abstract_function, abstract_args)"')
    writeLines(file_content, local_output_file)
    system(paste0("bash ", local_output_file))
    return(TRUE)
}