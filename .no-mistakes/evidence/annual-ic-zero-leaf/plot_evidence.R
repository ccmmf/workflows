#!/usr/bin/env Rscript
# Renders the PR evidence images from the CSVs the other scripts wrote.
# usage: Rscript plot_evidence.R <evidence_dir>
suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)
})
ev <- commandArgs(trailingOnly = TRUE)[[1]]

pal <- c(base = "#eb6834", fixed = "#2a78d6")
lab <- c(base = "Base (1a2a4f1)", fixed = "Fixed (6e8b522)")
surface <- "#fcfcfb"; ink <- "#0b0b0b"; ink2 <- "#52514e"; grid <- "#e6e5e1"
theme_ev <- theme_minimal(base_size = 12) +
  theme(
    plot.background = element_rect(fill = surface, colour = NA),
    panel.background = element_rect(fill = surface, colour = NA),
    panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(colour = grid, linewidth = 0.4),
    axis.text = element_text(colour = ink2), axis.title = element_text(colour = ink2),
    plot.title = element_text(colour = ink, face = "bold"),
    plot.subtitle = element_text(colour = ink2),
    legend.position = "top", legend.justification = "left",
    legend.text = element_text(colour = ink), legend.title = element_blank()
  )

# ---- 1. IC pools per member, base vs fixed ----
ic <- read.csv(file.path(ev, "ic_pools_base_vs_fixed.csv"))
site_lab <- c(
  annual = "annual_crop\n(leafGrowth 0)",
  mixed = "mixed PFT\n(leafGrowth 0 in 7/10)",
  nonveg = "non-vegetative PFT\n(no SLA / leafC)",
  perennial = "temperate.deciduous",
  perennial_nolai = "temperate.deciduous\n(MODIS LAI missing)"
)
ic$site_f <- factor(site_lab[ic$site], levels = rev(site_lab))
ic$version_f <- factor(ic$version, levels = c("base", "fixed"))
dodge <- ifelse(ic$version == "base", 0.17, -0.17)
ic$y <- as.numeric(ic$site_f) + dodge

panel <- function(var, title, xlab) {
  d <- ic[!is.na(ic[[var]]) & !is.nan(ic[[var]]), ]
  miss <- unique(ic[is.na(ic[[var]]), c("site_f", "version", "y")])
  nan_flag <- if (var == "leaf_carbon_content") ic$leaf_carbon_content_is_nan else is.nan(ic[[var]])
  miss$what <- ifelse(nan_flag[match(paste(miss$site_f, miss$version),
                                     paste(ic$site_f, ic$version))],
                      "NaN in all 10 members", "NA (no LAI) in all 10 members")
  ggplot(d, aes(x = .data[[var]], y = y, colour = version_f, shape = version_f)) +
    geom_point(size = 2.6, alpha = 0.85, stroke = 0.9) +
    geom_text(data = miss, aes(x = 0, y = y, label = what), inherit.aes = FALSE,
              hjust = 0, colour = ink2, size = 3.3, nudge_y = 0) +
    scale_colour_manual(values = pal, labels = lab, drop = FALSE) +
    scale_shape_manual(values = c(base = 1, fixed = 16), labels = lab, drop = FALSE) +
    scale_y_continuous(breaks = seq_along(levels(ic$site_f)), labels = levels(ic$site_f),
                       limits = c(0.6, length(levels(ic$site_f)) + 0.4)) +
    labs(title = title, x = xlab, y = NULL) +
    theme_ev
}
p1 <- panel("LAI", "LAI written to the IC file", "LAI (m² m⁻²)")
p2 <- panel("leaf_carbon_content", "leaf_carbon_content written to the IC file", "leaf C (kg C m⁻²)") +
  theme(axis.text.y = element_blank())
fig1 <- (p1 | p2) + plot_layout(guides = "collect") +
  plot_annotation(
    title = "02_ic_build.R output, 10 IC members per site (each dot is one member)",
    subtitle = "Real script run on a synthetic 5-site input set, LAI looked up near 2016-07-01, run start 2016-01-01",
    theme = theme(plot.title = element_text(face = "bold", colour = ink),
                  plot.subtitle = element_text(colour = ink2),
                  plot.background = element_rect(fill = surface, colour = NA),
                  legend.position = "top", legend.justification = "left")
  )
ragg::agg_png(file.path(ev, "ic_lai_leafc_base_vs_fixed.png"), width = 1500, height = 680, res = 120)
print(fig1)
invisible(dev.off())

# ---- 2. SIPNET Jan-Mar, annual member 1 ----
sp <- read.csv(file.path(ev, "sipnet_annual_JanMar_daily.csv"))
sp$date <- as.Date(sp$day - 1, origin = "2016-01-01")
sp$version_f <- factor(sp$version, levels = c("base", "fixed"))
ends <- do.call(rbind, lapply(split(sp, sp$version), function(x) x[nrow(x), ]))
line_panel <- function(var, title, ylab) {
  ggplot(sp, aes(date, .data[[var]], colour = version_f)) +
    geom_line(linewidth = 1) +
    geom_text(data = ends, aes(label = lab[version]), hjust = 0, nudge_x = 1.5,
              colour = ink, size = 3.4, show.legend = FALSE) +
    scale_colour_manual(values = pal, labels = lab) +
    scale_x_date(date_labels = "%b %d", expand = expansion(mult = c(0.01, 0.22))) +
    labs(title = title, x = NULL, y = ylab) +
    theme_ev + theme(panel.grid.major.y = element_line(colour = grid, linewidth = 0.4),
                     panel.grid.major.x = element_blank())
}
q1 <- line_panel("plantLeafC", "Plant leaf C", "g C m⁻²")
q2 <- line_panel("gpp", "Daily GPP", "g C m⁻² day⁻¹")
tot <- tapply(sp$gpp, sp$version, sum)
fig2 <- (q1 / q2) + plot_layout(guides = "collect") +
  plot_annotation(
    title = "SIPNET, annual_crop IC member 1, Jan 1 – Mar 31 2016, no planting events",
    subtitle = sprintf(
      "laiInit from write.config.SIPNET: base %.2f, fixed 0. Jan–Mar GPP total: base %.0f, fixed %.0f g C m⁻²",
      read.csv(file.path(ev, "sipnet_param_base_vs_fixed.csv")) |>
        subset(site == "annual" & version == "base", laiInit, drop = TRUE),
      tot[["base"]], tot[["fixed"]]
    ),
    theme = theme(plot.title = element_text(face = "bold", colour = ink),
                  plot.subtitle = element_text(colour = ink2),
                  plot.background = element_rect(fill = surface, colour = NA),
                  legend.position = "top", legend.justification = "left")
  )
ragg::agg_png(file.path(ev, "sipnet_annual_leafc_gpp_base_vs_fixed.png"), width = 1300, height = 820, res = 120)
print(fig2)
invisible(dev.off())
cat("wrote images to", ev, "\n")
