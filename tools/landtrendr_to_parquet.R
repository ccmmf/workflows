#!/usr/bin/env Rscript

# extract LandTrendr-estimated aboveground biomass for 2016
# from 30 m gridded geotiffs to a single estimate and uncertainty for each DWR
# parcel, as computed by bootstrap sampling each parcel from the pixel-level
# medians and sds reported by Landtrendr.
#
# Writes several intermediate files into cwd for debug/checkpointing;
# these can be removed when we're confident it works in one shot.
#
# Should be able to work for other years by refactoring out the hardcoded
# "ca_biomassfiaald_2016_median" column names.
#
# Run used around ~16 GB of memory and took just under 3 hours on the NCSA test
# cluster when invoked as
# srun --mem=0 --time=1440 landtrendr_to_parquet.R \
#   --parcel_file=parcels-consolidated.gpkg \
#   --landtrendr_medians_file=ca_biomassfiaald_2016_median.tif \
#   --landtrendr_stdevs_file=ca_biomassfiaald_2016_stdv.tif
# Extracting raw pixels took ~20 min, remainder was bootstrap.
# If neneded, it's likely this could be sped up by finding ways to parallelize
# the bootstrap operation / avoid keeping all ~62M pixels in memory at once.
#
# About the inputs:
# The biomass data being converted here were estimated using Landtrendr by the
# Kennedy group at Oregon State University.
# Medians are available by anonymous FTP at islay.ceoas.oregonstate.edu and by
# web (but possibly this is a different version?) from",
# https://emapr.ceoas.oregonstate.edu/pages/data/viz/index.html
# The uncertainty layer was formerly distributed by FTP but I cannot find it on
# the ceoas server at the moment.
# TODO find out whether this is available from a supported source.
# Files ca_biomassfiaald_2016_median.tif and ca_biomassfiaald_2016_stdv.tif
# are a subset (year 2016 clipped to the CA state boundaries) of the 30-m CONUS
# median and stdev maps that are stored on the Dietze lab server.

options <- list(
  optparse::make_option("--parcel_file",
    default = "data_raw/management/crops/v4.1.2/parcels-consolidated.gpkg",
    help = paste("Spatial vector file containing parcel geometries.",
      "ID field must be named 'parcel_id'.")
  ),
  optparse::make_option("--landtrendr_medians_file",
    default = "data_raw/ca_biomassfiaald_2016_median.tif",
    help = "Geotiff containing aboveground biomass for each pixel."
  ),
  optparse::make_option("--landtrendr_stdevs_file",
    default = "data_raw/ca_biomassfiaald_2016_stdv.tif",
    help = "Geotiff containing std dev of the biomass estimate for each pixel."
  ),
  optparse::make_option("--output_file",
    default = "landtrendr_2016_biomass_by_dwr_parcel.parquet",
    help = paste("Path to write results. This will be a Parquet file with",
      "columns 'parcel_id', 'mean', 'median', 'sd', 'q5', 'q95'.")
  )
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()



# vectors of point estimates and uncertainties ->
# bootstrap mean, median, sd, and 5/95% interval of their mean.
boot_pixels <- function(means, sds, n_boot = 1000) {
  stopifnot(
    length(means) > 0,
    length(means) == length(sds),
    is.numeric(means),
    is.numeric(sds),
    !anyNA(means),
    !anyNA(sds)
  )
  
  draws <- replicate(
    n = n_boot,
    mean(rnorm(n = length(means), mean = means, sd = sds))
  )
  dq <- quantile(draws, c(0.05, 0.50, 0.95))

  data.frame(
    mean = mean(draws),
    median = dq[["50%"]],
    sd = sd(draws),
    q5 = dq[["5%"]],
    q95 = dq[["95%"]]
  )
}

start_time <- Sys.time()
print(paste("Starting at", start_time))

# landtrendr files are ~1.8 GB geotiffs
median_biomass <- terra::rast(args$landtrendr_medians_file)
parcels <- terra::vect(args$parcel_file) |>
  terra::project(median_biomass)
parcel_ids <- parcels |>
  as.data.frame() |>
  tibble::rowid_to_column("parcel_num")
med_px <- terra::extract(median_biomass, parcels, fun = NULL) |>
  tibble::rowid_to_column("px_num")
# Just in case this crashes / is ultra-slow -
# save this work before moving on to stdv
# output is ~250 MB
# arrow::write_parquet(
#   med_px,
#   "landtrendr_2016_biomass_dwr_parcel_px_medians.parquet",
#   compression = "ZSTD")
now <- Sys.time()
elapsed <- signif(now - start_time, 3)
print(paste(now, "medians done in", elapsed, units(elapsed)))


stdv_biomass <- terra::rast(args$landtrendr_stdevs_file)
stdv_px <- terra::extract(stdv_biomass, parcels, fun = NULL) |>
  tibble::rowid_to_column("px_num")
# arrow::write_parquet(
#   stdv_px,
#   "landtrendr_2016_biomass_dwr_parcel_px_stdv.parquet",
#   compression = "ZSTD")
elapsed <- signif(Sys.time() - now, 3)
now <- Sys.time()
print(paste(now, "stdevs done in", elapsed, units(elapsed)))


biomass_px <- dplyr::left_join(
  med_px,
  stdv_px,
  by = c ("px_num", "ID"),
  relationship = "one-to-one") |>
  dplyr::rename(
    parcel_num = ID,
    median = ca_biomassfiaald_2016_median,
    sd = ca_biomassfiaald_2016_stdv)

fld_px <- parcel_ids |>
  dplyr::left_join(
    biomass_px,
    by = "parcel_num",
    relationship = "one-to-many")
# One possible route to speedup if needed: Chunk this file along group
# boundaries, then process chunks in parallel reading back from disk.
# file is ~300 MB
# arrow::write_parquet(
#   fld_px,
#     "landtrendr_2016_biomass_dwr_parcel_pixels.parquet",
#     compression = "ZSTD"
# )

# Drop missing values before bootstrapping,
# confirming this doesn't lose any parcels
na_px <- fld_px |>
  dplyr::summarize(
    na_med = sum(is.na(median)),
    na_sd = sum(is.na(sd)),
    n = dplyr::n(),
    frac_med_na = na_med/n,
    frac_sd_na = na_sd/n,
    .by = parcel_id
  ) |>
  dplyr::filter(na_med > 0 | na_sd > 0)
if (nrow(na_px) > 0) {
  write.csv(na_px, "landtrendr_parcels_with_NAs.csv", row.names = FALSE)
}
if (any(na_px$frac_med_na >= 1) || any(na_px$frac_sd_na >= 1)) {
  na_parcels <- na_px |>
    dplyr::filter(frac_med_na >= 1 | frac_sd_na >= 1) |>
    dplyr::pull(parcel_id) |>
    toString()
  warning(
    "Some parcels have NA values for all pixels.",
    " See 'landtrendr_parcels_with_NAs.csv' for details (parcel_ids ",
    na_parcels,
    ")"
  )
}


fld_px |>
  tidyr::drop_na(median, sd) |>
  dplyr::summarize(
    boot_pixels(median, sd),
    .by = parcel_id) |>
  # All the numbers PEcAn needs, in one 20-MB file instead of two 2GB ones!
  arrow::write_parquet("landtrendr_2016_biomass_by_dwr_parcel.parquet")

end_time <- Sys.time()
elapsed <- signif(end_time - start_time, 3)
print(paste("Done at", end_time, "Elapsed time:", elapsed, units(elapsed)))
