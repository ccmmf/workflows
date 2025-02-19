library(targets)
library(tarchetypes)

tar_option_set(
    packages = c(
        "tidyverse", "dplyr", "sf", "terra",
        "randomForest", "keras3", "PEcAn.all", "caladaptr"
    )
)

list(
    tar_target(prepare_data, {
        source("downscale/00-prepare.R")
        data_for_clust_with_ids # output from 00-prepare.R
    }),
    tar_target(cluster_sites,
        {
            source("downscale/01_cluster_and_select_design_points.R")
            cluster_output # output from 01_cluster_and_select_design_points.R
        },
        deps = prepare_data
    ),
    tar_target(simulations,
        {
            source("downscale/02_design_point_simulations.R")
            design_point_wide # output from 02-design_point_simulations.R
        },
        deps = cluster_sites
    ),
    tar_target(downscale,
        {
            source("downscale/03_downscale_and_agregate.R")
            ensemble_data # output from 03_downscale_and_agregate.R
        },
        deps = simulations
    ),
    tar_quarto(
        analysis_report,
        path = "04-analysis.qmd",
        deps = list(simulations, downscale)
    )
)
