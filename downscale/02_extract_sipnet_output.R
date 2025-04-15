# This file processess the output from SIPNET ensemble runs and generates
# three different data formats that comply with Ecological Forecasting Initiative 
# (EFI) standard:
# 1. A 4-D array (time, site, ensemble, variable)
# 2. A long format data frame (time, site, ensemble, variable)
# 3. A NetCDF file (time, site, ensemble, variable)
# This code can be moved to PEcAn.utils as one or more functions
# I did this so that I could determine which format is easiest to work with
# For now, I am planning to work with the CSV format
# TODO: write out EML metadata in order to be fully EFI compliant
library(PEcAn.logger)
library(lubridate)
library(dplyr)
library(ncdf4)
library(furrr)
library(stringr)

# Define base directory for ensemble outputs
modeloutdir <- "/projectnb/dietzelab/ccmmf/ccmmf_phase_1b_20250319064759_14859"

# Read settings file and extract run information
settings <- PEcAn.settings::read.settings(file.path(modeloutdir, "settings.xml"))
outdir <- file.path(modeloutdir, settings$modeloutdir)
ensemble_size <- settings$ensemble$size |>
    as.numeric()
start_date <- settings$run$settings.1$start.date
start_year <- lubridate::year(start_date)
end_date <- settings$run$settings.1$end.date
end_year <- lubridate::year(end_date)

# Site Information
# design points for 1b
# data/design_points.csv
design_pt_csv <- "https://raw.githubusercontent.com/ccmmf/workflows/46a61d58a7b0e43ba4f851b7ba0d427d112be362/data/design_points.csv"
design_points <- readr::read_csv(design_pt_csv, show_col_types = FALSE) |>
    rename(site_id = id) |> # fixed in more recent version of 01 script
    dplyr::distinct()

# Variables to extract
variables <- c("AGB", "TotSoilCarb")

#' **Available Variables**
#' This list is from the YYYY.nc.var files, and may change, 
#'   e.g. if we write out less information in order to save time and storage space
#' See SIPNET parameters.md for more details
#'
#' | Variable                      | Description                              |
#' |-------------------------------|------------------------------------------|
#' | GPP                           | Gross Primary Productivity               |
#' | NPP                           | Net Primary Productivity                 |
#' | TotalResp                     | Total Respiration                        |
#' | AutoResp                      | Autotrophic Respiration                  |
#' | HeteroResp                    | Heterotrophic Respiration                |
#' | SoilResp                      | Soil Respiration                         |
#' | NEE                           | Net Ecosystem Exchange                   |
#' | AbvGrndWood                   | Above ground woody biomass               |
#' | leaf_carbon_content           | Leaf Carbon Content                      |
#' | TotLivBiom                    | Total living biomass                     |
#' | TotSoilCarb                   | Total Soil Carbon                        |
#' | Qle                           | Latent heat                              |
#' | Transp                        | Total transpiration                      |
#' | SoilMoist                     | Average Layer Soil Moisture              |
#' | SoilMoistFrac                 | Average Layer Fraction of Saturation     |
#' | SWE                           | Snow Water Equivalent                    |
#' | litter_carbon_content         | Litter Carbon Content                    |
#' | litter_mass_content_of_water  | Average layer litter moisture            |
#' | LAI                           | Leaf Area Index                          |
#' | fine_root_carbon_content      | Fine Root Carbon Content                 |
#' | coarse_root_carbon_content    | Coarse Root Carbon Content               |
#' | GWBI                          | Gross Woody Biomass Increment            |
#' | AGB                           | Total aboveground biomass                |
#' | time_bounds                   | history time interval endpoints          |

site_ids <- design_points |>
    pull(site_id) |>
    unique()
ens_ids <- 1:ensemble_size

##-----TESTING SUBSET-----##
# comment out for full run # 
# site_ids   <- site_ids[1:5]
# ens_ids    <- ens_ids[1:5]
# start_year <- end_year - 1

ens_dirs <- expand.grid(ens = PEcAn.utils::left.pad.zeros(ens_ids), 
                        site_id = site_ids, 
                        stringsAsFactors = FALSE) |>
    mutate(dir = file.path(outdir, paste("ENS", ens, site_id, sep = "-")))
# Check that all ens dirs exist
existing_dirs <- file.exists(ens_dirs$dir)
if (!all(existing_dirs)) {
    missing_dirs <- ens_dirs[!existing_dirs]
    PEcAn.logger::logger.warn("Missing expected ensemble directories: ", paste(missing_dirs, collapse = ", "))
}

# extract output via PEcAn.utils::read.output
# temporarily suppress logging or else it will print a lot of file names
logger_level <- PEcAn.logger::logger.setLevel("OFF")
ens_results <- furrr::future_pmap_dfr(
    ens_dirs,
    function(ens, site_id, dir) {
        out_df <- PEcAn.utils::read.output(
            runid = paste(ens, site_id, sep = "-"),
            outdir = dir,
            start.year = start_year,
            end.year = end_year,
            variables = variables,
            dataframe = TRUE,
            verbose = FALSE
        ) |>
            dplyr::mutate(site_id = .env$site_id, ensemble = as.numeric(.env$ens)) |>
            dplyr::rename(time = posix)
    },
    # Avoids warning "future unexpectedly generated random numbers",
    # which apparently originates from actions taken inside the `units` package
    # when its namespace is loaded by ud_convert inside read.output.
    # The warning is likely spurious, but looks scary and setting seed to
    # silence it does not hurt anything.
    .options = furrr::furrr_options(seed = TRUE)
) |>
    group_by(ensemble, site_id, year) |>
    #filter(year <= end_year) |> # not sure why this was necessary; should be taken care of by read.output
    filter(time == max(time)) |> # only take last value
    ungroup() |>
    arrange(ensemble, site_id, year)  |> 
    tidyr::pivot_longer(cols = all_of(variables), names_to = "variable", values_to = "prediction")

# restore logging
logger_level <- PEcAn.logger::logger.setLevel(logger_level)

## Create Ensemble Output For Downscaling
## Below, three different output formats are created:
## 1. 4-D array (time, site, ensemble, variable)
## 2. long format data frame (time, site, ensemble, variable)
## 3. NetCDF file (time, site, ensemble, variable)

# --- 1. Create 4-D array ---
# Add a time dimension (even if of length 1) so that dimensions are: [time, site, ensemble, variable]
unique_times <- sort(unique(ens_results$time))
if(length(unique_times) != length(start_year:end_year)){
    # this check may fail if we are using > one time point per year, 
    # i.e. if the code above including group_by(.., year) is changed
    PEcAn.logger::logger.warn( 
        "there should only be one unique time per year",
        "unless we are doing a time series with multiple time points per year"
    )
}

# Create a list to hold one 3-D array per variable
ens_arrays <- list()
for (var in variables) {
    # Preallocate 3-D array for time, site, ensemble for each variable
    arr <- array(NA,
        dim = c(length(unique_times), length(site_ids), length(ens_ids)),
        dimnames = list(
            datetime = as.character(unique_times),
            site_id = site_ids,
            ensemble = as.character(ens_ids)
        )
    )
    
    # Get rows corresponding to the current variable
    subset_idx <- which(ens_results$variable == var)
    if (length(subset_idx) > 0) {
        i_time <- match(ens_results$time[subset_idx], unique_times)
        i_site <- match(ens_results$site_id[subset_idx], site_ids)
        i_ens <- match(ens_results$ensemble[subset_idx], ens_ids)
        arr[cbind(i_time, i_site, i_ens)] <- ens_results$prediction[subset_idx]
    }
    
    ens_arrays[[var]] <- arr
}

saveRDS(ens_arrays, file = file.path(outdir, "ensemble_output.rds"))

# --- 2. Create EFI Standard v1.0 long format data frame ---
efi_long <- ens_results |>
    rename(datetime = time) |>
    select(datetime, site_id, ensemble, variable, prediction)

readr::write_csv(efi_long, file.path(outdir, "ensemble_output.csv"))

####--- 3. Create EFI Standard v1.0 NetCDF files
library(ncdf4)
# Assume these objects already exist (created above):
#   unique_times: vector of unique datetime strings
#   design_points: data frame with columns lat, lon, and id (site_ids)
#   ens_ids: vector of ensemble member numbers (numeric)
#   ens_arrays: list with elements "AGB" and "TotSoilCarb" that are arrays
#       with dimensions: datetime, site, ensemble

# Get dimension names / site IDs
time_char <- unique_times

lat <- design_points |>
    filter(site_id %in% site_ids) |> # only required when testing w/ subset
    dplyr::pull(lat)
lon <- design_points |>
    filter(site_id %in% site_ids) |>
    dplyr::pull(lon)

# Convert time to CF-compliant values using PEcAn.utils::datetime2cf
time_units <- "days since 1970-01-01 00:00:00"
cf_time <- PEcAn.utils::datetime2cf(time_char, unit = time_units)

# TODO: could accept start year as an argument to the to_ncdim function if variable = 'time'? Or set default? 
#       Otherwise this returns an invalid dimension 
# time_dim <- PEcAn.utils::to_ncdim("time", cf_time)
time_dim <- ncdf4::ncdim_def(
    name = "ntime",
    longname = "Time middle averaging period",
    units = time_units,
    vals = cf_time,
    calendar = "standard",
    unlim = FALSE
)
site_dim <- ncdim_def("site", "", vals = seq_along(site_ids), longname = "Site ID", unlim = FALSE)
ensemble_dim <- ncdim_def("ensemble", "", vals = ens_ids, longname = "ensemble member", unlim = FALSE)

# Use dims in reversed order so that the unlimited (time) dimension ends up as the record dimension:
dims <- list(time_dim, site_dim, ensemble_dim)

# Define forecast variables:
agb_ncvar <- ncvar_def(
    name = "AGB",
    units = "kg C m-2",
    dim = dims,
    longname = "Total aboveground biomass"
)
soc_ncvar <- ncvar_def(
    name = "TotSoilCarb",
    units = "kg C m-2",
    dim = dims,
    longname = "Total Soil Carbon"
)
time_var <- ncvar_def(
    name = "time",
    units = "days since 1970-01-01 00:00:00",
    dim = time_dim,
    longname = "Time dimension"
)
lat_var <- ncvar_def(
    name = "lat",
    units = "degrees_north",
    dim = site_dim,
    longname = "Latitude"
)

lon_var <- ncvar_def(
    name = "lon",
    units = "degrees_east",
    dim = site_dim,
    longname = "Longitude"
)

nc_vars <- list(
    time = time_var,
    lat  = lat_var,
    lon  = lon_var,
    AGB  = agb_ncvar,
    TotSoilCarb = soc_ncvar
)

nc_file <- file.path(outdir, "ensemble_output.nc")

if (file.exists(nc_file)) {    
    file.remove(nc_file)
}

nc_out <- ncdf4::nc_create(nc_file, nc_vars)
# Add attributes to coordinate variables for clarity
# ncdf4::ncatt_put(nc_out, "time", "bounds", "time_bounds", prec = NA)
# ncdf4::ncatt_put(nc_out, "time", "axis", "T", prec = NA)
# ncdf4::ncatt_put(nc_out, "site", "axis", "Y", prec = NA)
# ncdf4::ncatt_put(nc_out, "ensemble", "axis", "E", prec = NA)

# Write data into the netCDF file.
ncvar_put(nc_out, time_var, cf_time)
ncvar_put(nc_out, lat_var, lat)
ncvar_put(nc_out, lon_var, lon)
ncvar_put(nc_out, agb_ncvar, ens_arrays[["AGB"]])
ncvar_put(nc_out, soc_ncvar, ens_arrays[["TotSoilCarb"]])

## Add global attributes per EFI standards.

# Get Run metadata from log filename
# ??? is there a more reliable way to do this?
forecast_time <- readr::read_tsv(
    file.path(basedir, 'output', "STATUS"),
    col_names = FALSE
) |>
    filter(X1 == "FINISHED") |>
    pull(X3)
forecast_iteration_id <- as.numeric(forecast_time) # or is run_id available?
obs_flag <- 0

ncatt_put(nc_out, 0, "model_name", settings$model$type) 
ncatt_put(nc_out, 0, "model_version", settings$model$revision)
ncatt_put(nc_out, 0, "iteration_id", forecast_iteration_id)
ncatt_put(nc_out, 0, "forecast_time", forecast_time)
ncatt_put(nc_out, 0, "obs_flag", obs_flag)
ncatt_put(nc_out, 0, "creation_date", format(Sys.time(), "%Y-%m-%d"))
# Close the netCDF file.
nc_close(nc_out)

PEcAn.logger::logger.info("EFI-compliant netCDF file 'ensemble_output.nc' created.")
