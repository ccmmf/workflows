get_data <- function(file) {
  read_csv(file, col_types = cols()) %>%
    filter(!is.na(Ozone))
}

fit_model <- function(data) {
  lm(Ozone ~ Temp, data) %>%
    coefficients()
}

plot_model <- function(model, data) {
  ggplot(data) +
    geom_point(aes(x = Temp, y = Ozone)) +
    geom_abline(intercept = model[1], slope = model[2])
}

exec_step_double <- function(file) {
    read_csv(file, col_types = cols()) %>%
    filter(!is.na(Ozone))
}

check_run_object <- function(workflow_run, required_fields) {
    for (field in required_fields) {
        if (!is.null(workflow_run$field)) {
            print(paste("Workflow run object is missing required field:", field))
            print(workflow_run)
            stop(paste("Error in workflow run configuration."))
        }
    }
}

print_object <- function(object) {
    print(object)
}

prepare_run_directory <- function(workflow_run, run_directory, step_name="prepare_run_directory") {
    if (!is.null(workflow_run$run_directory)) {
        stop(paste("Workflow run object already has a run directory: ", workflow_run$run_directory))
    }
    if (!dir.exists(run_directory)) {
        dir.create(run_directory, recursive = TRUE)
    } else {
        stop(paste("Run directory", run_directory, "already exists"))
    }
    workflow_run[["run_directory"]] = run_directory
    return(workflow_run)
}

#' Localize Data Resources for Workflow Step
#'
#' Copies data resource files to a workflow-specific directory structure and updates
#' the workflow run object with the localized file paths. This function ensures that
#' data resources are organized within the workflow's run directory and accessible
#' to subsequent workflow steps.
#'
#' @param workflow_run A list object containing workflow run information, including
#'   a required 'run_directory' field that specifies the base directory for the workflow.
#' @param data_resource_file_path Character string specifying the path to the data
#'   resource file that should be localized. Must not be NULL.
#' @param step_name Character string specifying the name of the workflow step for
#'   which the data resource is being localized. Must not be NULL and must not
#'   already exist in the workflow's data resources.
#'
#' @return A list object (the updated workflow_run) with the data resource
#'   information added to the 'data_resources' field. The localized file path
#'   is stored as `workflow_run$data_resources$step_name$file_path`.
#'
#' @details
#' The function performs the following operations:
#' \itemize{
#'   \item Validates that the workflow run object contains a 'run_directory' field
#'   \item Creates a target directory structure: `{run_directory}/data/{step_name}/`
#'   \item Copies the data resource file to the target directory
#'   \item Updates the workflow run object with the localized file path
#'   \item Prevents duplicate data resource entries for the same step
#' }
#'
#' @examples
#' \dontrun{
#' # Example usage
#' workflow_run <- list(run_directory = "/path/to/workflow/run")
#' updated_run <- localize_data_resources(
#'   workflow_run = workflow_run,
#'   data_resource_file_path = "/path/to/input/data.csv",
#'   step_name = "data_preparation"
#' )
#' }
#'
#' @seealso \code{\link{prepare_run_directory}}, \code{\link{check_run_object}}
#'
localize_data_resources <- function(workflow_run, data_resource_file_paths, step_name) {
    check_run_object(workflow_run=workflow_run, required_fields=c("run_directory"))
    run_directory = workflow_run$"run_directory"
    if (is.null(data_resource_file_paths)) {
        print(data_resource_file_paths)
        stop("Data resource file paths are required")
    }
    if (is.null(step_name)) {
        stop("Step name is required")
    }
    if (!is.null(workflow_run$data_resources) && !is.null(workflow_run$data_resources$step_name)) {
        print(paste("Data resource for step", step_name, "already exists"))
        print(workflow_run)
        stop(paste("Error in workflow run configuration."))
    }
    target_step_directory = file.path(run_directory, step_name)
    target_data_resource_directory = file.path(target_step_directory, "data")
    if (is.null(workflow_run$data_resources)) {
        workflow_run$data_resources = list ()
    } 

    if (!dir.exists(target_step_directory)) {
        dir.create(target_step_directory, recursive = TRUE)
        dir.create(target_data_resource_directory, recursive = TRUE)
    }
    workflow_run$data_resources[[step_name]] = c()
    for (i in 1:length(data_resource_file_paths)){
        data_resource_file_path = data_resource_file_paths[i]
        target_data_resource_file_path = file.path(target_data_resource_directory, basename(data_resource_file_path))
        file.copy(data_resource_file_path, target_data_resource_directory)
        workflow_run$data_resources[[step_name]] = c(workflow_run$data_resources[[step_name]], target_data_resource_file_path)
    }    
    return(workflow_run)
}

check_data_path_in_run_directory <- function(workflow_run, data_resource_file_path) {
    if (is.null(workflow_run$run_directory)) {
        stop("Workflow run object does not have a run directory")
    }
    if (workflow_run$run_directory %in% data_resource_file_path) {
        return(TRUE)
    }
    return(FALSE)
}

register_data_resource <- function(workflow_run, data_resource_file_path, step_name) {
    if (!check_data_path_in_run_directory(workflow_run, data_resource_file_path)) {
        stop(paste("Data resource file path", data_resource_file_path, "is not in the run directory", workflow_run$run_directory, ". Please localize the data resource file path using the localize_data_resources function."))
    }
    if (is.null(workflow_run$data_resources)) {
        workflow_run$data_resources = list ()
    }
    if (is.null(workflow_run$data_resources$step_name)) {
        workflow_run$data_resources$step_name = list(data_resource_file_path)
    } else {
        stop(paste("Cannot add data resource under step_name:", step_name, "because that name is already in use by another data resource."))
    }
    return(workflow_run)
}

exec_system_command <- function(command, step_name=NULL) {
    system(command)
    # oh, yeah, that's safe.
}

exec_step_01_ph <- function() {
    site_info <- list(
    site_id = "losthills",
    lat = 35.5103,
    lon = -119.6675,
    start_date = "1999-01-01",
    end_date = "2012-12-31"
    )
    # variables used
    # raw_era5_path
    # site_info$lon,
    # site_info$lat,
    # site_sipnet_met_path
    # site_info$start_date,
    # site_info$end_date,
    # site_info$site_id
    # site_era5_path
    # data_prefix = "ERA5_"

    PEcAn.data.atmosphere::extract.nc.ERA5(
        slat = site_info$lat,
        slon = site_info$lon,
        in.path = raw_era5_path,
        start_date = site_info$start_date,
        end_date = site_info$end_date,
        outfolder = site_era5_path,
        in.prefix = "ERA5_",
        newsite = site_info$site_id
    )
    purrr::walk(
        1:10, # ensemble members
        ~PEcAn.SIPNET::met2model.SIPNET(
            in.path = file.path(site_era5_path,
                                paste("ERA5", site_info$site_id, ., sep = "_")),
            start_date = site_info$start_date,
            end_date = site_info$end_date,
            in.prefix = paste0("ERA5.", .),
            outfolder = site_sipnet_met_path
        )
    )

}