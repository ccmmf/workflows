#!/usr/bin/env Rscript
# Reads every IC netCDF that 02_ic_build.R wrote for the base and the fixed
# script and prints the leaf / LAI / wood pools side by side.
#
# usage: Rscript inspect_ic.R <base_IC_files_dir> <fixed_IC_files_dir> <out_csv>

args <- commandArgs(trailingOnly = TRUE)
read_ic <- function(dir, version) {
  files <- list.files(dir, pattern = "\\.nc$", recursive = TRUE, full.names = TRUE)
  do.call(rbind, lapply(files, function(f) {
    nc <- ncdf4::nc_open(f)
    on.exit(ncdf4::nc_close(nc))
    get <- function(v) if (v %in% names(nc$var)) ncdf4::ncvar_get(nc, v) else NA_real_
    data.frame(
      version = version,
      site = basename(dirname(f)),
      member = as.integer(sub(".*_(\\d+)\\.nc$", "\\1", basename(f))),
      LAI = get("LAI"),
      leaf_carbon_content = get("leaf_carbon_content"),
      AbvGrndWood = get("AbvGrndWood"),
      wood_carbon_content = get("wood_carbon_content"),
      SoilMoistFrac = get("SoilMoistFrac")
    )
  }))
}
base <- read_ic(args[[1]], "base")
fixed <- read_ic(args[[2]], "fixed")
all <- rbind(base, fixed)
all <- all[order(all$site, all$member, all$version), ]
# write.csv turns NaN into NA, so keep the distinction in its own column
all$leaf_carbon_content_is_nan <- is.nan(all$leaf_carbon_content)
write.csv(all, args[[3]], row.names = FALSE)

fmt <- function(x) formatC(x, digits = 4, format = "g")
show <- all
show[4:8] <- lapply(show[4:8], fmt)
show$leaf_carbon_content_is_nan <- NULL
options(width = 200)
cat("== IC pools read back from the written netCDF files ==\n")
print(show, row.names = FALSE)

cat("\n== Per-site summary (fixed script) ==\n")
for (s in unique(fixed$site)) {
  f <- fixed[fixed$site == s, ]
  b <- base[base$site == s, ]
  b <- b[match(f$member, b$member), ]
  same <- function(v) isTRUE(all.equal(f[[v]], b[[v]]))
  cat(sprintf(
    paste(
      "%-16s LAI range [%s, %s]  leafC range [%s, %s]  NaN leafC: %d",
      "| members zeroed vs base: %d/%d | unchanged vs base: LAI %s leafC %s wood %s\n"
    ),
    s, fmt(min(f$LAI)), fmt(max(f$LAI)),
    fmt(min(f$leaf_carbon_content)), fmt(max(f$leaf_carbon_content)),
    sum(is.nan(f$leaf_carbon_content)),
    sum(f$LAI %in% 0 & !(b$LAI %in% 0)), nrow(f),
    same("LAI"), same("leaf_carbon_content"), same("wood_carbon_content")
  ))
}
