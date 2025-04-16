#' ---
#' title: "Cluster and Select Design Points"
#' author: "David LeBauer"
#' ---
#' 
#' # Overview
#' 
#' This workflow will:
#' 
#' - Read in a dataset of site environmental data
#' - Perform K-means clustering to identify clusters
#' - Select design points for each cluster
#' - create design_points.csv and anchor_sites.csv
#' 
#' 
#' ## Setup
#' 
## ----setup--------------------------------------------------------------------
# general utilities
library(tidyverse)
# spatial
library(sf)
library(terra)
library(caladaptr) # to plot climate regions
# parallel computing
library(furrr)
library(doParallel)
library(dplyr)
# analysis
library(cluster)
library(factoextra)
library(pathviewr) #???

# plotting
library(GGally)

# settings
set.seed(42)
ca_albers_crs <- 3310 # use California Albers projection (EPSG:3310) for speed
data_dir <- "/projectnb/dietzelab/ccmmf/data"
#'
#' ## Load Site Environmental Data Covariates
#'
#' Environmental data was pre-processed in the previous workflow 00-prepare.qmd.
#'
#' Below is a sumary of the covariates dataset
#'
#' - site_id: Unique identifier for each polygon
#' - temp: Mean Annual Temperature from ERA5
#' - precip: Mean Annual Precipitation from ERA5
#' - srad: Solar Radiation
#' - vapr: Vapor pressure deficit
#' - clay: Clay content from SoilGrids
#' - ocd: Organic Carbon content from SoilGrids
#' - twi: Topographic Wetness Index

site_covariates_csv <- file.path(data_dir, "site_covariates.csv")
site_covariates <- readr::read_csv(site_covariates_csv) 

#' ## Anchor Site Selection
#'
#' Load Anchor Sites from UC Davis, UC Riverside, and Ameriflux.
#'
## ----anchor-sites-selection---------------------------------------------------

anchor_sites_with_ids <- readr::read_csv(file.path(data_dir, "anchor_sites_ids.csv"))

anchor_sites_pts <- anchor_sites_with_ids |>
  sf::st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
  sf::st_transform(crs = ca_albers_crs)

# create map of anchor sites
ca_climregions <- caladaptr::ca_aoipreset_geom("climregions") |>
  rename(climregion_name = name, climregion_id = id)
p <- anchor_sites_pts |>
  ggplot() +
  geom_sf(data = ca_climregions, aes(fill = climregion_name), alpha = 0.25) +
  labs(color = "Climate Region") +
  geom_sf(aes(color = pft)) +
  scale_color_brewer(palette = "Dark2") +
  labs(color = "PFT") +
  theme_minimal()
ggsave(p, filename = "downscale/figures/anchor_sites.png", dpi = 300, bg = "white")

anchorsites_for_clust <-
  anchor_sites_with_ids |>
  select(-pft) |>                                             
  left_join(site_covariates, by = 'site_id')                  
  
  
#'
#' ### Subset LandIQ fields for clustering
#'
#' The following code does:
#' - Read in a dataset of site environmental data
#' - Removes anchor sites from the dataset that will be used for clustering
#' - Subsample the dataset - 136GB RAM is insufficient to cluster 100k rows
#' - Bind anchor sites back to the dataset
#'
## ----subset-for-clustering----------------------------------------------------
# 10k works
# 2k sufficient for testing
sample_size <- 10000

data_for_clust <- site_covariates |>
  # remove anchor sites
  dplyr::filter(!site_id %in% anchorsites_for_clust$site_id) |>
  # subset to woody perennial crops
  # dplyr::filter(pft == "woody perennial crop") |>
  # dplyr::mutate(pft = ifelse(pft == "woody perennial crop", "woody perennial crop", "other")) |>
  sample_n(sample_size - nrow(anchorsites_for_clust)) |>
  # now add anchor sites back
  bind_rows(anchorsites_for_clust) |>
  dplyr::mutate(
    crop = factor(crop),
    climregion_name = factor(climregion_name)
  ) |>
  select(-lat, -lon) 
assertthat::assert_that(nrow(data_for_clust) == sample_size)

PEcAn.logger::logger.info("Summary of data for clustering before scaling:")
skimr::skim(data_for_clust)

#' 
#' ### K-means Clustering
#' 
#' K-means on the numeric columns of covariates 
#' Full list printed in message; currently (temp, precip, srad, vapr, clay, ocd, twi)
#' could include 'crop' as categorical with one-hot encoding) i.e.
#' crop1 crop2 crop3
#' 0     1    0
#' 1     0    0
#' by changing function below w/ 
# perform_clustering <- function(data, k_range = 2:20) {
  # Perform one-hot encoding for the 'crop' variable
  # encoded_crop <- model.matrix(~ crop - 1, data = data)
  # clust_data <- data |>
  #   select(where(is.numeric), -ends_with("id")) |>
  #   cbind(encoded_crop)
  # extract metrics


perform_clustering <- function(data, k_range = 2:20) {
  # Select numeric variables for clustering
  clust_data <- data |>
    select(where(is.numeric), -ends_with("id"))
  
  PEcAn.logger::logger.info(
    "Columns used for clustering: ",
    paste(names(clust_data), collapse = ", ")
  )
  # Standardize data
  clust_data_scaled <- scale(clust_data)
  gc()   # free up memory
  PEcAn.logger::logger.info("Summary of scaled data used for clustering:")
  print(skimr::skim(clust_data_scaled))
  
  # Determine optimal number of clusters using elbow method
  metrics_list <- furrr::future_map(
    k_range,
    function(k) {
      model <- hkmeans(clust_data_scaled, k)
      total_withinss <- model$tot.withinss
      sil_score <- mean(silhouette(model$cluster, dist(clust_data_scaled))[, 3])
 #     dunn_index <- 
 #     calinski_harabasz <- 
      list(model = model, total_withinss = total_withinss, sil_score = sil_score)
    },
    .options = furrr_options(seed = TRUE)
  )



  metrics_df <- data.frame(
    # see also https://github.com/PecanProject/pecan/blob/b5322a0fc62760b4981b2565aabafc07b848a699/modules/assim.sequential/inst/sda_backup/bmorrison/site_selection/pick_sda_sites.R#L221
    k = k_range,
    tot.withinss = map_dbl(metrics_list, "total_withinss"),
    sil_score = map_dbl(metrics_list, "sil_score")
#    dunn_index = map_dbl(metrics_list, "dunn_index")
#    calinski_harabasz = map_dbl(metrics_list, "calinski_harabasz")
  )

  elbow_k <- find_curve_elbow(
    metrics_df[, c("k", "tot.withinss")],
    export_type = "k" # default uses row number instead of k
  )["k"]

## TODO check other metrics (b/c sil and elbow disagree)
# other metrics
#  sil_k <- metrics_df$k[which.max(metrics_df$sil_score)]
#  dunn_k <- metrics_df$k[which.max(metrics_df$dunn_index)]
#  calinski_harabasz_k <- metrics_df$k[which.max(metrics_df$calinski_harabasz)]

  txtplot::txtplot(
    x = metrics_df$k, y = metrics_df$tot.withinss, 
    xlab = "k (number of clusters)",
    ylab = "SS(Within)"
  )
  PEcAn.logger::logger.info(
    "Optimal number of clusters according to Elbow Method: ", elbow_k, 
    "(where the k vs ss(within) curve starts to flatten.)"
  )

  PEcAn.logger::logger.info("Silhouette scores computed. Higher values indicate better-defined clusters.")
  txtplot::txtplot(
    x = metrics_df$k, y = metrics_df$sil_score,
    xlab = "Number of Clusters (k)", ylab = "Score"
  )  

  # Perform hierarchical k-means clustering with optimal k
  final_hkmeans <- hkmeans(clust_data_scaled, elbow_k)
  clust_data <- cbind(
    site_id = data$site_id,
    clust_data, 
    cluster = final_hkmeans$cluster
  )

  return(clust_data)
}

#' 
#' Apply clustering function to the sampled dataset.
#' 
## ----clustering, eval=FALSE---------------------------------------------------

PEcAn.logger::logger.info("Starting clustering")
sites_clustered <- perform_clustering(data_for_clust, k = 5:15)

#'
#' ### Check Clustering
#'
## ----check-clustering---------------------------------------------------------
# Summarize clusters
cluster_summary <- sites_clustered |>
  group_by(cluster) |>
  summarise(across(where(is.numeric), \(x) mean(x, na.rm = TRUE)))

knitr::kable(cluster_summary, digits = 0)

# Plot all pairwise numeric variables
ggpairs_plot <- sites_clustered |>
  select(-site_id) |>
  # need small # pfts for ggpairs
  sample_n(1000) |>
  ggpairs(
    # plot all values except site_id and cluster
    columns = setdiff(names(sites_clustered), c("site_id", "cluster")),
    mapping = aes(color = as.factor(cluster), alpha = 0.8)
  ) +
  theme_minimal()
ggsave(ggpairs_plot,
  filename = "downscale/figures/cluster_pairs.png",
  dpi = 300, width = 10, height = 10, units = "in"
)

# scale and reshape to long for plotting

# Normalize the cluster summary data
scaled_cluster_summary <- cluster_summary |>
  mutate(across(-cluster, scale)) |>
  pivot_longer(
    cols = -cluster,
    names_to = "variable",
    values_to = "value"
  )

cluster_plot <- ggplot(
  scaled_cluster_summary,
  aes(x = factor(variable), y = value)
) +
  geom_bar(stat = "identity", position = "dodge") +
  facet_wrap(~cluster) +
  coord_flip() +
  labs(x = "Variable", y = "Normalized Value") +
  theme_minimal()

ggsave(cluster_plot, filename = "downscale/figures/cluster_plot.png", dpi = 300)

#' 
#' #### Stratification by Crops and Climate Regions
#' 
## ----check-stratification-----------------------------------------------------
# Check stratification of clusters by categorical factors

# cols should be character, factor
crop_ids <- read_csv(
  file.path(data_dir, "crop_ids.csv"),
  col_types = cols(
    crop_id = col_factor(),
    crop = col_character()
  )
)

climregion_ids <- read_csv(
  file.path(data_dir, "climregion_ids.csv"),
  col_types = cols(
    climregion_id = col_factor(),
    climregion_name = col_character()
  )
)

## ----stratification-----------------------------------------------------------
# The goal here is to check the stratification of the clusters by crop and climregion
# to ensure that the clusters are not dominated by a single crop or climregion
# BUT probably best to normalize by the total number of fields in each cluster 
# if this is to be useful
# is this useful?

# ca_attributes <- read_csv(file.path(data_dir, "ca_field_attributes.csv"))
# site_covariates <- read_csv(file.path(data_dir, "site_covariates.csv"))

# sites_clustered <- sites_clustered |>
#   left_join(ca_attributes, by = "site_id") |>
#   left_join(site_covariates, by = "site_id")

# factor_stratification <- list(
#     crop_id = table(sites_clustered$cluster, sites_clustered$crop),
#     climregion_id = table(sites_clustered$cluster, sites_clustered$climregion_name))

# normalize <- function(x) {
#   round(100 * x / rowSums(x), 1)
# }
# normalized_stratification <- lapply(factor_stratification, normalize)
# lapply(normalized_stratification, knitr::kable)

#' 
#' ## Design Point Selection
#' 
#' For phase 1b we need to supply design points for SIPNET runs. 
#' For development we will use 100 design points from the clustered dataset that are _not_ already anchor sites.
#' 
#' For the final high resolution runs we expect to use approximately 10,000 design points.
#' For woody croplands, we will start with a number proportional to the total number of sites with woody perennial pfts.
#'
#' 

#'
#' ### How Many Design Points?
#'
#' Calculating Woody Cropland Proportion
#'
#' Here we calculate percent of California croplands that are woody perennial crops,
#' in order to estimate the number of design points that will be selected in the clustering step
#' This is commented out because it takes a while and the number won't change
## ----woody-proportion---------------------------------------------------------
ca_attributes <- read_csv(file.path(data_dir, "ca_field_attributes.csv"))
ca_fields <- sf::st_read(file.path(data_dir, "ca_fields.gpkg"))
# pft_area <- ca_fields |>
#   left_join(ca_attributes, by = "site_id") |>
#   dplyr::select(site_id, pft, area_ha) |>
#   dtplyr::lazy_dt() |>
#   dplyr::mutate(woody_indicator = ifelse(pft == "woody perennial crop", 1L, 0L)) |>
#   dplyr::group_by(woody_indicator) |>
#   dplyr::summarize(pft_area = sum(area_ha)) |>
#   # calculate percent of total area
#   dplyr::mutate(pft_area_pct = pft_area / sum(pft_area) * 100)

# knitr::kable(pft_area, digits = 0)
# answer: 17% of California croplands were woody perennial crops in the
# 2016 LandIQ dataset
# So ... if we want to ultimately have 2000 design points, we should have ~ 400
# design points for woody perennial crops


## ----design-point-selection---------------------------------------------------
# From the clustered data, remove anchor sites to avoid duplicates in design point selection.

design_points_ids <- sites_clustered |>
  filter(!site_id %in% anchorsites_for_clust$site_id) |>
  select(site_id)  |>
  sample_n(100 - nrow(anchorsites_for_clust))  |>
  select(site_id)

anchor_site_ids <- anchorsites_for_clust |>
   select(site_id)

design_points <- bind_rows(design_points_ids,
   anchor_site_ids)  |>
   left_join(ca_fields, by = "site_id")

design_points |>
   as_tibble()  |>
   select(site_id, lat, lon) |>
   write_csv(file.path(data_dir, "design_points.csv"))

#' 
#' ### Design Point Map
#' 
#' Now some analysis of how these design points are distributed
#' 
## ----design-point-map---------------------------------------------------------
# plot map of california and climregions

design_points_clust <- design_points |>
  left_join(sites_clustered, by = "site_id") |>
  select(site_id, lat, lon, cluster) |>
  drop_na(lat, lon) |>
  mutate(cluster = as.factor(cluster)) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326)

ca_fields_pts <- ca_fields  |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326)

design_pt_plot <- ggplot() +
  geom_sf(data = ca_climregions, fill = 'white') +
  theme_minimal() +
  geom_sf(data = ca_fields, fill = "lightgrey", color = "lightgrey", alpha = 0.25) +
  geom_sf(data = design_points_clust) +
  geom_text(data = design_points_clust, aes(label = cluster, geometry = geometry), 
            size = 2, stat = "sf_coordinates")

ggsave(design_pt_plot, filename = "downscale/figures/design_points.png", dpi = 300, bg = "white")
