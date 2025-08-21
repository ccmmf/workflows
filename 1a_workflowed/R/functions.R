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

load_data_csv <- function(file) {
  read_csv(file, col_types = cols())
}

download_ccmmf_data <- function(prefix_url, local_path, prefix_filename) {
    system2("aws", args = c("s3", "cp", "--endpoint-url", "https://s3.garage.ccmmf.ncsa.cloud", paste0(prefix_url, "/", prefix_filename), local_path))
    return(file.path(local_path, prefix_filename))
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

check_data_path_in_run_directory <- function(workflow_run, data_resource_file_path) {
    if (is.null(workflow_run$run_directory)) {
        stop("Workflow run object does not have a run directory")
    }
    if (workflow_run$run_directory %in% data_resource_file_path) {
        return(TRUE)
    }
    return(FALSE)
}

prepare_pecan_run_directory <- function(pecan_settings) {
    pecan_run_directory = pecan_settings$outdir
    if (!dir.exists(file.path(pecan_run_directory))) {
        dir.create(file.path(pecan_run_directory), recursive = TRUE)
    } else {
        stop(paste("Run directory", file.path(pecan_run_directory), "already exists"))
    }
    return(pecan_settings)
}

check_pecan_continue_directive <- function(pecan_settings, continue=FALSE) {
    status_file <- file.path(pecan_settings$outdir, "STATUS")
    if (continue && file.exists(status_file)) {
        file.remove(status_file)
    }
    return(continue)
}

pecan_write_configs <- function(pecan_settings) {
    # if (PEcAn.utils::status.check("CONFIG") == 0) {
    #     PEcAn.utils::status.start("CONFIG")
    #     settings <- PEcAn.workflow::runModule.run.write.configs(settings)
    #     PEcAn.settings::write.settings(settings, outputfile = "pecan.CONFIGS.xml")
    #     PEcAn.utils::status.end()
    # } else if (file.exists(file.path(settings$outdir, "pecan.CONFIGS.xml"))) {
    #     settings <- PEcAn.settings::read.settings(file.path(settings$outdir, "pecan.CONFIGS.xml"))
    # }
    if (status.check("CONFIG") == 0) {
        status.start("CONFIG")
        pecan_settings <- runModule.run.write.configs(pecan_settings)
        write.settings(pecan_settings, outputfile = "pecan.CONFIGS.xml")
        status.end()
    } else if (file.exists(file.path(pecan_settings$outdir, "pecan.CONFIGS.xml"))) {
        pecan_settings <- read.settings(file.path(pecan_settings$outdir, "pecan.CONFIGS.xml"))
    }
    return(pecan_settings)
}


get_ERA5_met <- function(pecan_settings, raw_era5_path, site_era5_path, site_sipnet_met_path) {
    library("PEcAn.settings")
    library("PEcAn.data.atmosphere")
    site_info <- list(
        site_id = pecan_settings$run$site$name, # "losthills",
        lat = pecan_settings$run$site$lat, # 35.5103,
        lon = pecan_settings$run$site$lon, # -119.6675,
        start_date = pecan_settings$run$site$met.start, # "1999-01-01",
        end_date = pecan_settings$run$site$met.end # "2012-12-31"
    )
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