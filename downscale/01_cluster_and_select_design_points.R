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
#' - Select anchor sites for each cluster
#' 
#' ## Setup
#' 
## ----setup--------------------------------------------------------------------
# general utilities
library(tidyverse)

# spatial
library(sf)
library(terra)

# parallel computing
library(cluster)
library(factoextra)
library(pathviewr)
library(furrr)
library(doParallel)
library(dplyr)

# Set up parallel processing with a safe number of cores
no_cores <- parallel::detectCores(logical = FALSE)
plan(multicore,  workers = no_cores - 2)
options(future.globals.maxSize = benchmarkme::get_ram() * 0.9)

# load climate regions for mapping
load("data/ca_climregions.rda")
# environmental covariates
load("cache/data_for_clust_with_ids.rda")
if('mean_temp' %in% names(data_for_clust_with_ids)){
  data_for_clust_with_ids <- data_for_clust_with_ids |>
    rename(temp = mean_temp)
  PEcAn.logger::logger.warn("you should", 
    "change mean_temp --> temp in data_for_clust_with_ids",
    "when it is created in 00-prepare.qmd and then delete",
    "this conditional chunk")
}

#' 
#' ## Load Site Environmental Data
#' 
#' Environmental data was pre-processed in the previous workflow 00-prepare.qmd.
#' 
#' Below is a sumary of the covariates dataset
#' 
#' - id: Unique identifier for each polygon
#' - temp: Mean Annual Temperature from ERA5
#' - precip: Mean Annual Precipitation from ERA5
#' - srad: Solar Radiation
#' - vapr: Vapor pressure deficit
#' - clay: Clay content from SoilGrids
#' - ocd: Organic Carbon content from SoilGrids
#' - twi: Topographic Wetness Index
#' - crop_id: identifier for crop type, see table in crop_ids.csv
#' - climregion_id: Climate Regions as defined by CalAdapt identifier for climate region, see table in climregion_ids.csv
#' 
#' 
#' ## Anchor Site Selection
#' 
#' Load Anchor Sites from UC Davis, UC Riverside, and Ameriflux.
#' 
## ----anchor-sites-selection---------------------------------------------------

# set coordinate reference system, local and in meters for faster joins
ca_albers_crs <- 3310 # California Albers EPSG

anchor_sites_pts <- readr::read_csv("data/anchor_sites.csv") |>
  sf::st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
  sf::st_transform(crs = ca_albers_crs) |>
  dplyr::mutate(pt_geometry = geometry) |> 
  rename(anchor_site_pft = pft)

# ca_woody <- sf::st_read("data/ca_woody.gpkg")

ca_fields <- sf::st_read("data/ca_fields.gpkg") |>
  # must use st_crs(anchor_sites_pts) b/c  !identical(ca_albers_crs, st_crs(ca_albers_crs))
  sf::st_transform(crs = st_crs(anchor_sites_pts))  |> 
  rename(landiq_pft = pft)

# Get the index of the nearest polygon for each point
nearest_idx <- st_nearest_feature(anchor_sites_pts, ca_fields)
site_field_distances <- diag(st_distance(anchor_sites_pts, ca_fields |> slice(nearest_idx)))
ca_field_ids  <- ca_fields |> 
  dplyr::slice(nearest_idx) |>
  dplyr::select(id, lat, lon)

anchor_sites_ids <- dplyr::bind_cols(
  anchor_sites_pts,
  ca_field_ids,
  distance = site_field_distances
) |>
  dplyr::select(id, lat, lon, location, site_name, distance) #,anchor_site_pft, landiq_pft)
  
anchor_sites_ids |>
  readr::write_csv("data/anchor_sites_ids.csv")
# create map of anchor sites
anchor_sites_ids |>
  sf::st_transform(., crs = ca_albers_crs) |>
  ggplot() +
  geom_sf(data = ca_climregions, aes(fill = climregion_name), alpha = 0.25) +
  labs(color = "Climate Region") +
  geom_sf(aes(color = pft)) +
  scale_color_brewer(palette = "Dark2") +
  labs(color = "PFT") +
  theme_minimal()

woody_anchor_sites <-  anchor_sites_pts |>
  dplyr::filter(pft == "woody perennial crop")
anchorsites_for_clust <-
  data_for_clust_with_ids |>
  dplyr::filter(id %in% woody_anchor_sites$id)

message("Anchor sites included in final selection:")
knitr::kable(woody_anchor_sites |> dplyr::left_join(anchorsites_for_clust, by = 'id'))

#' 
#' ### Subset LandIQ fields for clustering
#' 
#' The following code does:
#' - Read in a dataset of site environmental data
#' - Removes anchor sites from the dataset that will be used for clustering
#' - Subsample the dataset - 80GB RAM too small to cluster 100k rows
#' - Bind anchor sites back to the dataset 
#' 
## ----subset-for-clustering----------------------------------------------------
set.seed(42)  # Set seed for random number generator for reproducibility
# subsample for testing (full dataset exceeds available Resources)
sample_size <- 20000

data_for_clust <- data_for_clust_with_ids |>
                    # remove anchor sites
                    dplyr::filter(!id %in% anchorsites_for_clust$id) |>
                    sample_n(sample_size - nrow(anchorsites_for_clust)) |>
                    # row bind anchorsites_for_clust
                    bind_rows(anchorsites_for_clust) |>
                    dplyr::mutate(crop = factor(crop),
                                  climregion_id = factor(climregion_id))
assertthat::assert_that(nrow(data_for_clust) == sample_size)
assertthat::assert_that('temp'%in% colnames(data_for_clust))
skimr::skim(data_for_clust)

#' 
#' ### K-means Clustering
#' 
#' First, create a function `perform_clustering` to perform hierarchical k-means and find optimal clusters.
#' 
#' K-means on the numeric columns (temp, precip, clay, possibly ignoring 'crop'
#' or treat 'crop' as categorical by some encoding if needed).
#' 
## ----k-means-clustering-function----------------------------------------------

perform_clustering <- function(data) {
  # Select numeric variables for clustering
  clust_data <- data |> select(where(is.numeric))

  # Standardize data
  clust_data_scaled <- scale(clust_data)

  # Determine optimal number of clusters using elbow method
  k_range <- 3:12
  tot.withinss <- future_map_dbl(k_range, function(k) {
    model <- hkmeans(clust_data_scaled, k)
    model$tot.withinss
  }, .options = furrr_options(seed = TRUE))

  # Find elbow point
  elbow_df <- data.frame(k = k_range, tot.withinss = tot.withinss)
  optimal_k <- find_curve_elbow(elbow_df)
  message("Optimal number of clusters determined: ", optimal_k)

  # Plot elbow method results
  elbow_plot <- ggplot(elbow_df, aes(x = k, y = tot.withinss)) +
    geom_line() +
    geom_point() +
    labs(title = "Elbow Method for Optimal k", x = "Number of Clusters", y = "Total Within-Cluster Sum of Squares")
  print(elbow_plot)

  # Compute silhouette scores to validate clustering quality
  silhouette_scores <- future_map_dbl(k_range, function(k) {
    model <- hkmeans(clust_data_scaled, k)
    mean(silhouette(model$cluster, dist(clust_data_scaled))[, 3])
  }, .options = furrr_options(seed = TRUE))

  silhouette_df <- data.frame(k = k_range, silhouette = silhouette_scores)

  message("Silhouette scores computed. Higher values indicate better-defined clusters.")
  print(silhouette_df)

  silhouette_plot <- ggplot(silhouette_df, aes(x = k, y = silhouette)) +
    geom_line(color = "red") +
    geom_point(color = "red") +
    labs(title = "Silhouette Scores for Optimal k", x = "Number of Clusters", y = "Silhouette Score")
  print(silhouette_plot)

  # Perform hierarchical k-means clustering with optimal k
  final_hkmeans <- hkmeans(clust_data_scaled, optimal_k)
  data$cluster <- final_hkmeans$cluster

  return(data)
}

#' 
#' Apply clustering function to the sampled dataset.
#' 
## ----clustering, eval=FALSE---------------------------------------------------
# 
# data_clustered <- perform_clustering(data_for_clust)
# save(data_clustered, file = "cache/data_clustered.rda")

#' 
#' ### Check Clustering
#' 
## ----check-clustering---------------------------------------------------------
load("cache/data_clustered.rda")
# Summarize clusters
cluster_summary <- data_clustered |>
                      group_by(cluster) |>
                      summarise(across(where(is.numeric), mean, na.rm = TRUE))
if('mean_temp' %in% names(cluster_summary)){
  cluster_summary <- cluster_summary |>
    rename(temp = mean_temp)
  PEcAn.logger::logger.warn("you should", 
    "change mean_temp --> temp in cluster_summary",
    "when it is created upstream and then delete this",
    "conditional chunk")
}
# use ggplot to plot all pairwise numeric variables

library(GGally)
data_clustered |>
  sample_n(1000) |>
  ggpairs(columns=c(1,2,4,5,6)+1,
          mapping = aes(color = as.factor(cluster), alpha = 0.8))+
  theme_minimal()

ggplot(data = cluster_summary, aes(x = cluster)) +
  geom_line(aes(y = temp, color = "temp")) +
  geom_line(aes(y = precip, color = "precip")) +
  geom_line(aes(y = clay, color = "clay")) +
  geom_line(aes(y = ocd, color = "ocd")) +
  geom_line(aes(y = twi, color = "twi")) +
  labs(x = "Cluster", y = "Value", color = "Variable")

knitr::kable(cluster_summary |> round(0))


#' 
#' #### Stratification by Crops and Climate Regions
#' 
## ----check-stratification-----------------------------------------------------
# Check stratification of clusters by categorical factors

# cols should be character, factor
crop_ids <- read_csv("data/crop_ids.csv",
                     col_types = cols(
                       crop_id = col_factor(),
                       crop = col_character()))
climregion_ids <- read_csv("data/climregion_ids.csv",
                           col_types = cols(
                             climregion_id = col_factor(),
                             climregion_name = col_character()
                           ))

factor_stratification <- list(
    crop_id = table(data_clustered$cluster, data_clustered$crop),
    climregion_id = table(data_clustered$cluster, data_clustered$climregion_name))

lapply(factor_stratification, knitr::kable)
# Shut down parallel backend
plan(sequential)

#' 
#' ## Design Point Selection
#' 
#' For phase 1b we need to supply design points for SIPNET runs. For development we will use 100 design points from the clustered dataset that are _not_ already anchor sites.
#' 
#' For the final high resolution runs we expect to use approximately 10,000 design points.
#' For woody croplands, we will start with a number proportional to the total number of sites with woody perennial pfts.
#' 
## ----design-point-selection---------------------------------------------------
# From the clustered data, remove anchor sites to avoid duplicates in design point selection.

if(!exists("ca_fields")) {
  ca_fields <- sf::st_read("data/ca_fields.gpkg")
}

missing_anchor_sites <- woody_anchor_sites|>
               as_tibble()|>
               left_join(ca_fields, by = 'id') |>
               filter(is.na(id)) |> 
               select(location, site_name, geometry)

if(nrow(missing_anchor_sites) > 0){
  woody_anchor_sites <- woody_anchor_sites |> 
                          drop_na(lat, lon)
  # there is an anchor site that doesn't match the ca_fields; 
  # need to check on this. For now we will just remove it from the dataset.
  PEcAn.logger::logger.warn("The following site(s) aren't within DWR crop fields:", 
                             knitr::kable(missing_anchor_sites))
}   

set.seed(2222222)
design_points_ids <- data_clustered |>
  filter(!id %in% woody_anchor_sites$id) |>
  select(id)  |>
  sample_n(100 - nrow(woody_anchor_sites))  |>
  select(id)

anchor_site_ids <- woody_anchor_sites |>
   select(id)

final_design_points <- bind_rows(design_points_ids,
   anchor_site_ids)  |>
   left_join(ca_fields, by = "id")

final_design_points |>
   as_tibble()  |>
   select(id, lat, lon) |>
   write_csv("data/design_points.csv")


#' 
#' ### Design Point Map
#' 
#' Now some analysis of how these design points are distributed
#' 
## ----design-point-map---------------------------------------------------------
# plot map of california and climregions

final_design_points_clust <- final_design_points |>
  left_join(data_clustered, by = "id") |>
  select(id, lat, lon, cluster) |>
  drop_na(lat, lon) |>
  mutate(cluster = as.factor(cluster)) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326)

ca_fields_pts <- ca_fields  |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326)
ggplot() +
  geom_sf(data = ca_climregions, aes(fill = climregion_name), alpha = 0.5) +
  labs(color = "Climregion") +
  theme_minimal() +
  geom_sf(data = final_design_points_clust, aes(shape = cluster)) +
  geom_sf(data = ca_fields_pts, fill = 'black', color = "grey", alpha = 0.5)




#' 
#' 
#' ## Woody Cropland Proportion
#' 
#' Here we calculate percent of California croplands that are woody perennial crops, in order to estimate the number of design points that will be selected in the clustering step
#' 
## ----woody-proportion---------------------------------------------------------
field_attributes <- read_csv("data/ca_field_attributes.csv")
ca <- ca_fields |>
  dplyr::select(-lat, -lon) |>
  dplyr::left_join(field_attributes, by = "id")

set.seed(5050)
pft_area <- ca |>
  dplyr::sample_n(2000) |>
  dplyr::select(id, pft, area_ha) |>
  dtplyr::lazy_dt() |>
  dplyr::mutate(woody_indicator = ifelse(pft == "woody perennial crop", 1L, 0L)) |>
  dplyr::group_by(woody_indicator) |>
  dplyr::summarize(pft_area = sum(area_ha))

# now calculate sum of pft_area and the proportion of woody perennial crops
pft_area <- pft_area |>
  dplyr::mutate(total_area = sum(pft_area)) |>
  dplyr::mutate(area_pct = round(100 * pft_area / total_area)) |>
  select(-total_area, -pft_area) |>
  dplyr::rename("Woody Crops" = woody_indicator, "Area %" = area_pct) 
  
pft_area |>
  kableExtra::kable()

cluster_output  # final output from clustering and design point selection


