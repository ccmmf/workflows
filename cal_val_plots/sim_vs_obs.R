#!/usr/bin/env Rscript
# Sim-vs-obs plots for the 3 BU SIPNET ensembles


suppressPackageStartupMessages({
  library(ncdf4)
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(purrr)
  library(stringr)
  library(lubridate)
  library(tibble)
})

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
WORKBOOK_DIR <- Sys.getenv(
  "WORKBOOK_DIR",
  unset = "/projectnb2/dietzelab/ccmmf/usr/adey2/workflows"
)

MAGIC_MAIN    <- file.path(WORKBOOK_DIR, "MAGiC Calibration Validation Dataset(1).xlsx")
MAGIC_RUSSELL <- file.path(WORKBOOK_DIR, "MAGiC Calibration Validation Data_ Russell Ranch.xlsx")

SITES <- list(
  list(name        = "Salinas SOCS",
       short       = "salinas",
       site_id     = "9f296becf416ce87",
       treatment   = "socs_sys1",
       start_year  = 2003,
       end_year    = 2011,
       run_dir     = "/projectnb2/dietzelab/ccmmf/usr/adey2/runs/salinas-socs",
       workbook    = MAGIC_MAIN),
  list(name        = "Modesto Nichols",
       short       = "modesto",
       site_id     = "9cb08ca2174bede7",
       treatment   = "compost",
       start_year  = 2018,
       end_year    = 2019,
       run_dir     = "/projectnb2/dietzelab/ccmmf/usr/adey2/runs/modesto-nichols",
       workbook    = MAGIC_MAIN),
  list(name        = "Russell Ranch",
       short       = "russell",
       site_id     = "ec0e8b4d92044f52",
       treatment   = "conv_corn_tomato",
       start_year  = 2000,
       end_year    = 2014,
       run_dir     = "/projectnb2/dietzelab/ccmmf/usr/adey2/runs/russell-ranch",
       workbook    = MAGIC_RUSSELL)
)
OUT_DIR  <- Sys.getenv("OUT_DIR", unset = "plots")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

# Read a single PEcAn-style NetCDF (one year file) and return a tibble with
# posix + the requested variable. Time is encoded in the standard CF way
# (units = "days since YYYY-01-01" or similar).
read_one_nc <- function(nc_path, variable) {
  nc <- tryCatch(nc_open(nc_path), error = function(e) NULL)
  if (is.null(nc)) return(NULL)
  on.exit(nc_close(nc), add = TRUE)
  if (!(variable %in% names(nc$var))) return(NULL)

  vals <- ncvar_get(nc, variable)
  t_units <- ncatt_get(nc, "time", "units")$value
  t_vals  <- ncvar_get(nc, "time")

  origin <- sub("^[^0-9]*", "", t_units)
  origin <- sub(" .*$", "", origin)
  origin_date <- suppressWarnings(as.Date(origin))
  if (is.na(origin_date)) {
    origin_date <- as.Date(sub(".*since +", "", t_units))
  }
  if (grepl("seconds", t_units)) {
    posix <- as.POSIXct(origin_date) + t_vals
  } else if (grepl("hours", t_units)) {
    posix <- as.POSIXct(origin_date) + t_vals * 3600
  } else {
    posix <- as.POSIXct(origin_date) + t_vals * 86400
  }

  tibble::tibble(posix = posix, !!variable := as.numeric(vals))
}

# Load ensemble output across all ENS-* dirs for one site and one variable.
# Returns a tibble: ens_num, posix, year, <variable>.
read_ensemble <- function(run_dir, variable, start_year, end_year) {
  out_root <- file.path(run_dir, "output", "out")
  if (!dir.exists(out_root)) {
    message("  no output dir: ", out_root)
    return(NULL)
  }
  ens_dirs <- list.files(out_root, pattern = "^ENS-",
                         full.names = TRUE, include.dirs = TRUE)
  if (length(ens_dirs) == 0) {
    message("  no ENS-* dirs in: ", out_root)
    return(NULL)
  }
  rows <- purrr::map_dfr(ens_dirs, function(d) {
    ens_num <- as.integer(stringr::str_extract(basename(d), "(?<=ENS-)\\d+"))
    nc_files <- list.files(d, pattern = "^[0-9]{4}\\.nc$", full.names = TRUE)
    year_in_range <- function(p) {
      y <- as.integer(sub("\\.nc$", "", basename(p)))
      !is.na(y) && y >= start_year && y <= end_year
    }
    nc_files <- nc_files[vapply(nc_files, year_in_range, logical(1))]
    if (length(nc_files) == 0) return(NULL)
    df <- purrr::map_dfr(nc_files, read_one_nc, variable = variable)
    if (nrow(df) == 0) return(NULL)
    df$ens_num <- ens_num
    df
  })
  if (nrow(rows) == 0) return(NULL)
  rows
}

# Per-year ensemble quantiles (q05, q95, mean) at end-of-year.
ensemble_quantiles <- function(ens_df, variable) {
  ens_df |>
    dplyr::mutate(year = lubridate::year(posix)) |>
    dplyr::group_by(ens_num, year) |>
    dplyr::summarise(value = mean(.data[[variable]], na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      mean = mean(value, na.rm = TRUE),
      q05  = quantile(value, 0.05, na.rm = TRUE),
      q95  = quantile(value, 0.95, na.rm = TRUE),
      .groups = "drop"
    )
}

# Load workbook observations matching a treatment + variable.
load_obs <- function(workbook, treatment_id, variable) {
  if (!file.exists(workbook)) {
    message("  workbook not found: ", workbook)
    return(dplyr::tibble())
  }
  obs <- readxl::read_excel(workbook, sheet = "observations",
                            .name_repair = "minimal")
  obs |>
    dplyr::filter(treatment_id == !!treatment_id,
                  variable     == !!variable) |>
    dplyr::mutate(
      value    = suppressWarnings(as.numeric(value)),
      min_date = as.Date(min_date),
      max_date = as.Date(max_date),
      date     = as.Date((as.numeric(min_date) + as.numeric(max_date)) / 2,
                         origin = "1970-01-01"),
      year     = as.integer(format(date, "%Y"))
    ) |>
    dplyr::filter(!is.na(value))
}

# Derive Russell Ranch SOC stock (Mg C ha-1) from per-layer C% and BD.
# Per David's guidance (Slack):
#   1. Use only the 0-30 cm depth window.
#   2. Compute SOC stock per layer = C% * BD * depth, then sum across layers.
#   3. Assumptions:
#      - total C = SOC (pH < 7 at this site)
#      - coarse fraction negligible (sandy loam, not mentioned in source text)
#
# Formula (per layer): stock_Mg_ha = C(%) * BD(g/cm3) * layer_depth_cm
#   ((g C / 100 g soil) * (g soil / cm3) * cm) = g C / (100 cm^2) -> Mg/ha
#   Net factor of 1.0 once the % and unit conversions cancel for these units.
derive_russell_soc_stock <- function(workbook, treatment_id,
                                     year_min = NULL, year_max = NULL) {
  if (!file.exists(workbook)) return(dplyr::tibble())

  raw <- readxl::read_excel(workbook, sheet = "observations",
                            .name_repair = "minimal")
  pick <- function(varname) {
    raw |>
      dplyr::filter(treatment_id == !!treatment_id,
                    variable     == !!varname) |>
      dplyr::mutate(value = suppressWarnings(as.numeric(value)),
                    min_depth_cm = suppressWarnings(as.numeric(min_depth)),
                    max_depth_cm = suppressWarnings(as.numeric(max_depth)),
                    year = as.integer(format(as.Date(
                      (as.numeric(as.Date(min_date)) +
                       as.numeric(as.Date(max_date))) / 2,
                      origin = "1970-01-01"), "%Y"))) |>
      dplyr::filter(!is.na(value), !is.na(year), max_depth_cm <= 30)
  }

  c_rows  <- pick("total_carbon_pct")
  bd_rows <- pick("bulk_density_g_cm3")

  if (nrow(c_rows) == 0 || nrow(bd_rows) == 0) {
    message("  Russell Ranch: missing total_carbon_pct or bulk_density_g_cm3 rows in 0-30 cm")
    return(dplyr::tibble())
  }

  # Average within (year, replicate, depth window) so multiple sub-samples or
  # duplicate rows don't get double-counted in the layer sum.
  c_layer <- c_rows |>
    dplyr::group_by(year, replicate_id,
                    min_depth_cm, max_depth_cm) |>
    dplyr::summarise(c_pct = mean(value, na.rm = TRUE), .groups = "drop")

  bd_layer <- bd_rows |>
    dplyr::group_by(year, replicate_id,
                    min_depth_cm, max_depth_cm) |>
    dplyr::summarise(bd_g_cm3 = mean(value, na.rm = TRUE), .groups = "drop")

  # Join C% with BD per (rep, depth). Use nearest-year BD where the BD year
  # doesn't match the C% year (BD is measured less often than C%).
  # Note: capture row values into local scalars so the nested filter doesn't
  # collide with the bd_layer column names.
  merged <- c_layer |>
    dplyr::rowwise() |>
    dplyr::mutate(
      bd_g_cm3 = {
        rep_id_  <- replicate_id
        mindep_  <- min_depth_cm
        maxdep_  <- max_depth_cm
        year_    <- year
        cand <- bd_layer |>
          dplyr::filter(replicate_id == rep_id_,
                        min_depth_cm == mindep_,
                        max_depth_cm == maxdep_)
        if (nrow(cand) == 0) NA_real_
        else cand$bd_g_cm3[which.min(abs(cand$year - year_))]
      }
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(bd_g_cm3)) |>
    dplyr::mutate(layer_cm    = max_depth_cm - min_depth_cm,
                  stock_Mg_ha = c_pct * bd_g_cm3 * layer_cm)

  if (nrow(merged) == 0) return(dplyr::tibble())

  out <- merged |>
    dplyr::group_by(year, replicate_id) |>
    dplyr::summarise(value = sum(stock_Mg_ha, na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::mutate(date = as.Date(sprintf("%d-07-01", year)))

  if (!is.null(year_min)) out <- dplyr::filter(out, year >= year_min)
  if (!is.null(year_max)) out <- dplyr::filter(out, year <= year_max)
  out
}

# Plot ensemble band + observed points.
plot_sim_vs_obs <- function(site, variable, label, obs_var, units_conv = 1,
                            ylab = NULL) {
  cat("- ", site$name, " :: ", variable, "\n", sep = "")
  ens <- read_ensemble(site$run_dir, variable, site$start_year, site$end_year)
  if (is.null(ens)) {
    message("  skip: no ensemble data")
    return(invisible(NULL))
  }
  ens_q <- ensemble_quantiles(ens, variable)

  obs <- load_obs(site$workbook, site$treatment, obs_var)
  if (nrow(obs) == 0) {
    message("  skip: no observations matched (", site$treatment, ", ", obs_var, ")")
    return(invisible(NULL))
  }
  obs <- obs |>
    dplyr::mutate(value_model_units = value * units_conv)

  p <- ggplot() +
    geom_ribbon(data = ens_q, aes(year, ymin = q05, ymax = q95),
                fill = "gray70", alpha = 0.5) +
    geom_line(data = ens_q, aes(year, mean), color = "black", linewidth = 0.8) +
    geom_point(data = obs, aes(year, value_model_units),
               color = "firebrick", size = 2) +
    labs(title = sprintf("%s — %s (%d–%d)",
                         site$name, site$treatment, site$start_year, site$end_year),
         subtitle = label,
         x = "Year",
         y = ylab %||% variable) +
    theme_minimal(base_size = 12)

  out_file <- file.path(OUT_DIR,
                        sprintf("%s_%s.png", site$short, variable))
  ggsave(out_file, p, width = 9, height = 5, dpi = 150)
  cat("  saved ", out_file, "\n", sep = "")
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ----------------------------------------------------------------------------
# Main — 3 sites × TotSoilCarb, plus Modesto N2O
# ----------------------------------------------------------------------------
cat("Sim-vs-obs plots — issue #238\n")
cat("Workbook dir: ", WORKBOOK_DIR, "\n", sep = "")
cat("Output dir: ", OUT_DIR, "\n\n", sep = "")

for (site in SITES) {
  if (site$short == "russell") {
    # Russell Ranch workbook stores per-layer C% + BD, not SOC stock directly.
    # Derive the 0-30 cm SOC stock per David's guidance (Slack), then plot.
    cat("- ", site$name, " :: TotSoilCarb (derived from C% x BD x depth)\n", sep = "")
    ens <- read_ensemble(site$run_dir, "TotSoilCarb",
                         site$start_year, site$end_year)
    if (is.null(ens)) {
      message("  skip: no ensemble data")
      next
    }
    ens_q <- ensemble_quantiles(ens, "TotSoilCarb")

    obs <- derive_russell_soc_stock(site$workbook, site$treatment,
                                    year_min = site$start_year,
                                    year_max = site$end_year)
    if (nrow(obs) == 0) {
      message("  skip: no derivable SOC observations for ", site$treatment)
      next
    }
    obs$value_model_units <- obs$value * 0.1  # Mg C ha-1 -> kg C m-2

    p <- ggplot() +
      geom_ribbon(data = ens_q, aes(year, ymin = q05, ymax = q95),
                  fill = "gray70", alpha = 0.5) +
      geom_line(data = ens_q, aes(year, mean), color = "black", linewidth = 0.8) +
      geom_point(data = obs, aes(year, value_model_units),
                 color = "firebrick", size = 2) +
      labs(
        title    = sprintf("%s — %s (%d–%d)",
                           site$name, site$treatment,
                           site$start_year, site$end_year),
        subtitle = "Total Soil Carbon — derived obs (0-30 cm: C% x BD x depth, summed)\nAssumptions: total C = SOC (pH < 7); coarse fraction ignored (sandy loam)",
        x = "Year", y = "Soil C (kg C m⁻²)"
      ) +
      theme_minimal(base_size = 12)

    out_file <- file.path(OUT_DIR, "russell_TotSoilCarb.png")
    ggsave(out_file, p, width = 9, height = 5, dpi = 150)
    cat("  saved ", out_file, "\n", sep = "")
  } else {
    plot_sim_vs_obs(
      site,
      variable   = "TotSoilCarb",
      label      = "Total Soil Carbon — model ensemble (5–95% band, mean line) vs observed SOC stock",
      obs_var    = "SOC_stock_Mg_ha",
      units_conv = 0.1,                 # Mg C ha-1 -> kg C m-2
      ylab       = "Soil C (kg C m⁻²)"
    )
  }
}

modesto <- Filter(function(s) s$short == "modesto", SITES)[[1]]
plot_sim_vs_obs(
  modesto,
  variable   = "N2O_flux",            # SIPNET variable name (if N cycle was on)
  label      = "N₂O flux — model ensemble vs observed chamber flux",
  obs_var    = "N2O_flux_g_N_ha_d",
  units_conv = 1,
  ylab       = "N₂O flux (g N ha⁻¹ d⁻¹)"
)

cat("\nDone. Plots in: ", normalizePath(OUT_DIR, mustWork = FALSE), "\n", sep = "")
