#!/usr/bin/env Rscript
# Builds a disposable input set for workflow/02_ic_build.R so the real script
# runs end to end offline: every per-site cache CSV the script checks for is
# pre-populated, so no SoilGrids / CDS / MODIS / LandTrendr download happens.
#
# usage: Rscript make_fixture.R <scratch_dir>

args <- commandArgs(trailingOnly = TRUE)
root <- args[[1]]
data_dir <- file.path(root, "data", "IC_prep")
pft_dir <- file.path(root, "pfts")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

# Five sites, one per case the change has to handle.
site_info <- data.frame(
  id = c("annual", "nonveg", "perennial", "perennial_nolai", "mixed"),
  field_id = c("f1", "f2", "f3", "f4", "f5"),
  lat = c(38.5, 38.6, 37.6, 37.7, 36.6),
  lon = c(-121.8, -121.9, -121.0, -121.1, -121.6),
  name = "",
  site.pft = c(
    "annual_crop",          # leafGrowth == 0 for every draw
    "soil_only",            # no SLA / leafC -> SLA = leafC = 0
    "temperate.deciduous",  # woody, leafGrowth > 0
    "temperate.deciduous",  # woody, MODIS LAI missing (NA)
    "mixed_growth"          # leafGrowth drawn 0 or 1 per replicate
  )
)
write.csv(site_info, file.path(root, "site_info.csv"), row.names = FALSE)

# Cache files, in the formats the script reads them back in.
write.csv(
  data.frame(
    Site_ID = site_info$id, Site_Name = "",
    `Total_soilC_0-30cm` = 5, `Std_soilC_0-30cm` = 0.5,
    check.names = FALSE
  ),
  file.path(data_dir, "soilgrids_soilC_data.csv"), row.names = FALSE
)
write.csv(
  data.frame(site.id = site_info$id, sm.mean = 30, sm.uncertainty = 3),
  file.path(data_dir, "sm.csv"), row.names = FALSE
)
write.csv(
  data.frame(
    site_id = site_info$id,
    `2016-07-01_LAI` = c(2.5, 1.5, 3.0, NA, 2.0),
    `2016-07-01_SD` = c(0.66, 0.66, 0.66, NA, 0.66),
    check.names = FALSE
  ),
  file.path(data_dir, "LAI_bysite.csv"), row.names = FALSE
)
write.csv(
  data.frame(site_id = site_info$id, AGB_median_Mg_ha = 20, AGB_sd = 2),
  file.path(data_dir, "aboveground_biomass_landtrendr.csv"), row.names = FALSE
)

# PFT posteriors, same shape PEcAn writes: rownames = trait, distn/parama/paramb/n
write_pft <- function(name, df) {
  d <- file.path(pft_dir, name)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  post.distns <- df
  save(post.distns, file = file.path(d, "post.distns.Rdata"))
}
pd <- function(...) {
  x <- rbind(...)
  data.frame(
    distn = x[, 1], parama = as.numeric(x[, 2]), paramb = as.numeric(x[, 3]),
    n = 0, row.names = rownames(x)
  )
}
write_pft("annual_crop", pd(
  SLA = c("norm", 20, 1), leafC = c("norm", 45, 1),
  leafGrowth = c("unif", 0, 0)
))
write_pft("soil_only", pd(leafGrowth = c("norm", 50, 1)))
write_pft("temperate.deciduous", pd(
  SLA = c("norm", 15, 1), leafC = c("norm", 48, 1),
  leafGrowth = c("norm", 126, 5)
))
write_pft("mixed_growth", pd(
  SLA = c("norm", 20, 1), leafC = c("norm", 45, 1),
  leafGrowth = c("binom", 1, 0.5)
))
cat("fixture written to", root, "\n")
