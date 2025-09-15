
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

reference_external_data_entity <- function(external_workflow_directory, external_name, localized_name){
    local_link_path = file.path(paste0(tar_path_store(), "/",localized_name))
    external_link_path = file.path(paste0(external_workflow_directory, "/",external_name))
    if (!dir.exists(external_link_path)){
        stop(paste("External link path", external_link_path, "does not exist"))
        return(NULL)
    }
    if (dir.exists(local_link_path)){
        stop(paste("Local link path", local_link_path, "already exists"))
    }
    file.symlink(from=external_link_path, to=local_link_path)
    # first, synthesize the local directory string
    # execute the link
    # return the local directory string
    return(local_link_path)
}

localize_data_resources <- function(resource_list, this_run_directory, data_resource_directory) {
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


exec_system_command <- function(command) {
    system2(command)
    return(TRUE)
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