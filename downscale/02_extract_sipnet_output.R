library(PEcAn.logger)
library(lubridate)
library(dplyr)
here::i_am('.here')

# Define base directory for ensemble outputs
basedir <- "/projectnb/dietzelab/ccmmf/ccmmf_phase_1b_98sites_20reps_20250312"
outdir <- file.path(basedir, "out")

# Variables to extract
variables <- c("AGB", "TotSoilCarb")

# Read Settings
settings <- PEcAn.settings::read.settings(file.path(basedir, "pecan.CONFIGS.xml"))
ensemble_size <- settings$ensemble$size |> as.numeric()
start_date <- settings$run$settings.1$start.date # TODO make this unique for each site
end_date <- settings$run$settings.1$end.date
end_year <- lubridate::year(end_date)

#' **Available Variables**
#'
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

# Preallocate 3-D array for 98 sites, 2 variables, and 20 ensemble members
site_ids <- readr::read_csv(here::here("data/design_points.csv")) |>
    pull(id) |>
    unique()
ens_ids <- PEcAn.utils::left.pad.zeros(1:ensemble_size)

##-----TESTING SUBSET-----##
# comment out for full run # 
#site_ids <- site_ids[1:5]
#ens_ids <- ens_ids[1:5]

ens_dirs <- expand.grid(ens = ens_ids, site = site_ids, stringsAsFactors = FALSE) |>
    mutate(dir = file.path(outdir, paste("ENS", ens, site, sep = "-")))
# check that all ens dirs exist
existing_dirs <- file.exists(ens_dirs$dir)
if (!all(existing_dirs)) {
    missing_dirs <- ens_dirs[!existing_dirs]
    PEcAn.logger::logger.warn("Missing expected ensemble directories: ", paste(missing_dirs, collapse = ", "))
}

# Loop through ensemble folders and extract output via read.output
library(furrr)
plan(multisession)

# Use purrr and dplyr to process ensemble directories in parallel
ens_results <- furrr::future_pmap_dfr(
    ens_dirs,
    function(ens, site, dir) {
        out_df <- PEcAn.utils::read.output(
            runid = paste(ens, site, sep = "-"),
            outdir = dir,
            start.year = end_year, # only reading in final year
            end.year = end_year,
            variables = variables,
            dataframe = TRUE,
            verbose = FALSE
        ) |>
            mutate(site = site, ens = ens)
    },
    .options = furrr::furrr_options(seed = TRUE)
) |>
    group_by(ens, site) |>
    filter(posix == max(posix)) |>
    ungroup() |>
    arrange(ens, site)


ens_array <- array(NA,
    dim = c(length(site_ids), length(variables), length(ens_ids)),
    dimnames = list(
        site = site_ids,
        variable = variables,
        ensemble = ens_ids
    )
)

i_site     <- match(ens_results$site, site_ids)
i_variable <- match(ens_results$variable, variables)
i_ens      <- match(ens_results$ens, ens_ids)
ens_array[cbind(i_site, i_variable, i_ens)] <- ens_results$value

save(ens_array, file = file.path(outdir, "ens_array.RData"))

## Create EFI std data structure
logfile <- dir(basedir, pattern = "pecan_workflow_runlog")
pattern <- "^pecan_workflow_runlog_([0-9]{14})_([0-9]+-[0-9]+)\\.log$"
matches <- stringr::str_match(logfile, pattern)
forecast_time_string <- matches[2]
forecast_unique_id <- matches[3]

efi_std <- ens_results |>
    left_join(readr::read_csv("data/design_points.csv") |> distinct(), by = c("site" = "id")) |>
    mutate(
        forecast_iteration_id = forecast_unique_id,
        forecast_time = as.POSIXct(forecast_time_string, format = "%Y%m%d%H%M%S"),
        obs_flag = 0
    ) |>
    rename(time = posix, ensemble = ens, X = lon, Y = lat) |>
    select(time, ensemble, X, Y, TotSoilCarb, AGB, obs_flag)

readr::write_csv(efi_std, file.path(outdir, "efi_std_ens_results.csv"))
