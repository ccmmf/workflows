#!/usr/bin/env Rscript

options <- list(
  optparse::make_option("--val_data_path",
    default = "data_raw/private/HSP/Harmonized_Data_Croplands.csv",
    help = "CSV containing nonpublic soil C data shared by HSP program"
  ),
  optparse::make_option("--model_dir",
    default = "output",
    help = "directory containing PEcAn output to validate"
  ),
  optparse::make_option("--output_dir",
    default = "validation_output",
    help = "directory in which to save plots and summary stats"
  )
  # TODO lots of assumptions still hardcoded below
) |>
  # Show default values in help message
  purrr::modify(\(x) {
    x@help <- paste(x@help, "[default: %default]")
    x
  })

args <- optparse::OptionParser(option_list = options) |>
  optparse::parse_args()



library(tidyverse)


## Function definitions

# Calculate change per year from successive timepoints.
# @param df: dataframe containing at least column `year`
#  plus any others to be converted to differences between years
# @return dataframe one row shorter than input, with year column removed
#  and all others converted to difference on a yearly basis
# @examples
# data.frame(
#   year = c(2020, 2021, 2025),
#   x = c(1, 2, 4),
#   y = c(10, 5, 1)
# ) |> diff_years()
# #    x  y
# # 2 1.0 -5
# # 3 0.5 -1
diff_years <- function(df) {
  df |>
  arrange(year) |>
  mutate_all(\(x) (x - lag(x))) |>
  mutate(across(-year, \(x) x / year)) |>
  select(-year) |>
  _[-1,]
}



## Read validation data, identify target years from each site

soc_obs <- read.csv(args$val_data_path) |>
  # recreate hashes used in site_info
  # TODO can we save steps here?
  # One advantage of recreating: private IDs never leave the source file
  mutate(
    BaseID = gsub("\\s+", "", BaseID),
    site = paste(ProjectName, BaseID, Latitude, Longitude) |>
      purrr::map_chr(rlang::hash),
    obs_SOC = PEcAn.utils::ud_convert(SOC_stock_0_30, "tonne/ha", "kg/m2")
  ) |>
  select(site, BaseID, year = Year, obs_SOC)

obs_sites_yrs <- soc_obs |>
  distinct(site, year)

## Read model output, summarize to end-of-year values
## (SOC doesn't change very fast)

sim_files_wanted <- file.path(args$model_dir, "out") |>
  list.files(
    pattern = "\\d\\d\\d\\d.nc",
    full.names = TRUE,
    recursive = TRUE
  ) |>
  data.frame(path = _) |>
  separate_wider_regex(
    cols = path,
    patterns = c(
      ".*/ENS-",
      ens_num = "\\d+",
      "-",
      site = ".*?",
      "/",
      year = "\\d+",
      ".nc"
    ),
    cols_remove = FALSE
  ) |>
  mutate(across(c("ens_num", "year"), as.numeric)) |>
  inner_join(obs_sites_yrs)

# read.output is FAR too chatty; suppress info-level messages
logger_level <- PEcAn.logger::logger.setLevel("WARN")

soc_sim <- sim_files_wanted |>
  nest_by(ens_num, site, year, .key = "path") |>
  mutate(
    contents = map(
      path,
      ~ PEcAn.utils::read.output(
        ncfiles = .x,
        dataframe = TRUE,
        variables = "TotSoilCarb",
        print_summary = FALSE,
        verbose = FALSE
      ) |>
        select(-year) # already present outside nested cols
    )
  ) |>
  unnest(contents) |>
  ungroup() |>
  slice_max(posix, by = c(ens_num, site, year))

## Combine and align obs + sim

soc_compare <- soc_sim |>
  left_join(soc_obs) |>
  # TODO these filters need refinement --
  # eg Are NAs actually expected or should they trigger complaints?
  drop_na(obs_SOC) #|>
  # TODO excluded as surprisingly high
  # May want to re-include after inspecting data for individual sites
  # filter(obs_SOC < 20)
  # TODO will eventually want to have PFTs labeled here

if (!dir.exists(args$output_dir)) dir.create(args$output_dir, recursive = TRUE)

# Debug use only:
# Contains private treatment names, so do not leave this CSV sitting in your output directory
# write.csv(
#   soc_compare |> select(-path),
#   file.path(args$output_dir, "soc_compare_tmp.csv"),
#   row.names = FALSE
# )



# SOC change between sequential measurements, in g/m2/yr
soc_timedelta <- soc_compare |>
  # some years have multiple samples, others don't; can't track individual samples across years.
  # Instead collapse these to treatment means
  # TODO propagate variance?
  summarize(
    across(c(TotSoilCarb, obs_SOC), mean),
    .by = c(ens_num, site, year)
  ) |>
  nest_by(ens_num, site) |>
  filter(nrow(data) > 1) |>
  mutate(yrly_diff = map(list(data), diff_years)) |>
  unnest(yrly_diff)



## lm fit + CIs

soc_fits <- soc_compare |>
  ungroup() |>
  nest_by(ens_num) |>
  mutate(
    fit = list(lm(TotSoilCarb ~ obs_SOC, data = data)),
    r2 = summary(fit)$adj.r.squared,
    nse = 1 - (
      sum((data$obs_SOC - data$TotSoilCarb)^2) /
        sum((data$obs_SOC - mean(data$obs_SOC))^2)
    ),
    rmse = sqrt(mean((data$obs_SOC - data$TotSoilCarb)^2)),
    bias = mean(data$TotSoilCarb - data$obs_SOC)
  )

soc_fits |>
  select(-data, -fit) |>
  mutate(across(everything(), # NB excludes group vars! ens_num not mutated here
                \(x) signif(x, digits = 4))) |>
  write.csv(
    file = file.path(args$output_dir, "SOC_model_fit.csv"),
    row.names = FALSE
  )

soc_ci <- soc_fits |>
  mutate(
    predx = list(seq(min(data$obs_SOC), max(data$obs_SOC), by = 0.1)),
    pred = list(predict(fit, data.frame(obs_SOC = predx)))
  ) |>
  unnest(c(predx, pred)) |>
  ungroup() |>
  group_by(predx) |>
  summarize(
    pred_q5 = quantile(pred, 0.05),
    pred_q95 = quantile(pred, 0.95),
    pred_mean = mean(pred),
  )

soc_timedelta_fits <- soc_timedelta |>
  ungroup() |>
  nest_by(ens_num) |>
  mutate(
    fit = list(lm(TotSoilCarb ~ obs_SOC, data = data)),
    r2 = summary(fit)$adj.r.squared,
    nse = 1 - (
      sum((data$obs_SOC - data$TotSoilCarb)^2) /
        sum((data$obs_SOC - mean(data$obs_SOC))^2)
    ),
    rmse = sqrt(mean((data$obs_SOC - data$TotSoilCarb)^2)),
    bias = mean(data$TotSoilCarb - data$obs_SOC)
  )
soc_timedelta_ci <- soc_timedelta_fits |>
  mutate(
    predx = list(seq(min(data$obs_SOC), max(data$obs_SOC), by = 0.1)),
    pred = list(predict(fit, data.frame(obs_SOC = predx)))
  ) |>
  unnest(c(predx, pred)) |>
  ungroup() |>
  group_by(predx) |>
  summarize(
    pred_q5 = quantile(pred, 0.05),
    pred_q95 = quantile(pred, 0.95),
    pred_mean = mean(pred),
  )


## Scatterplot

soc_lm_plot <- ggplot(soc_compare) +
  aes(obs_SOC, TotSoilCarb) +
  geom_point() +
  geom_abline(lty = "dotted") +
  geom_ribbon(
    data = soc_ci,
    mapping = aes(
      x = predx,
      ymin = pred_q5,
      ymax = pred_q95,
      y = NULL
    ),
    alpha = 0.4
  ) +
  geom_line(
    data = soc_ci,
    mapping = aes(predx, pred_mean),
    col = "blue"
  ) +
  xlab("Measured 0-30 cm soil C stock (kg C / m2)") +
  ylab("Simulated 0-30 cm soil C stock (kg C / m2)") +
  theme_bw()
ggsave(
  file.path(args$output_dir, "SOC_scatter.png"),
  plot = soc_lm_plot,
  height = 8,
  width = 8
)

ggsave(
  file.path(args$output_dir, "SOC_scatter_by_ens.png"),
  plot = soc_lm_plot + facet_wrap(~ens_num),
  height = 8,
  width = 8
)


soc_timedelta_plot <- ggplot(soc_timedelta) +
  aes(obs_SOC, TotSoilCarb) +
  geom_point() +
  geom_abline(lty = "dotted") +
  geom_ribbon(
    data = soc_timedelta_ci,
    mapping = aes(
      x = predx,
      ymin = pred_q5,
      ymax = pred_q95,
      y = NULL
    ),
    alpha = 0.4
  ) +
  geom_line(
    data = soc_timedelta_ci,
    mapping = aes(predx, pred_mean),
    col = "blue"
  ) +
  xlab("Change in measured 0-30 cm soil C stock (kg C / m2 / yr)") +
  ylab("Change in simulated 0-30 cm soil C stock (kg C / m2 / yr)") +
  theme_bw()
ggsave(
  file.path(args$output_dir, "SOC_yrly_scatter.png"),
  plot = soc_timedelta_plot,
  height = 8,
  width = 8
)

soc_fits |>
  ungroup() |>
  summarize(across(r2:bias, c(mean = mean, sd = sd))) |>
  pivot_longer(everything(), names_to = c("stat", ".value"), names_sep = "_") |>
  mutate(across(where(is.numeric),
                \(x) signif(x, digits = 4))) |>
  write.csv(
    file.path(args$output_dir, "SOC_fit_summary.csv"),
    row.names = FALSE
  )

pdf(file.path(args$output_dir, "SOC_fit_diagnostic_plots.pdf"))
soc_fits |> pwalk(\(fit, ens_num, ...) plot(fit, which = 1:6, main = ens_num))
dev.off()
