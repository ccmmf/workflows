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

read_ncdir <- function(path, start, end, vars = NULL) {
  path |>
    list.files(pattern = "ENS-", full.names = TRUE) |>
    data.frame(path = _) |>
    separate_wider_regex(
      cols = path,
      patterns = c(
        ".*/ENS-",
        ens_num = "\\d+",
        "-",
        site = ".*?"
      ),
      cols_remove = FALSE
    ) |>
    mutate(ens_num = as.numeric(ens_num)) |>
    nest_by(ens_num, site, .key = "path") |>
    mutate(
      contents = map(
        path,
        ~ PEcAn.utils::read.output(
          outdir = .x,
          runid = "", # included in outdir already
          dataframe = TRUE,
          variables = vars,
          print_summary = FALSE,
          verbose = FALSE,
          start.year = start,
          end.year = end
        )
      )
    ) |>
    unnest(contents)
}


## Read model output, summarize to end-of-year values
## (SOC doesn't change very fast)

# read.output is FAR too chatty; suppress info-level messages
logger_level <- PEcAn.logger::logger.setLevel("WARN")


soc_sim <- read_ncdir(
  file.path(args$model_dir, "out"),
  start = 2016,
  end = 2024,
  vars = "TotSoilCarb"
) |>
  group_by(ens_num, site, year) |>
  slice_max(posix)


## Read validation data, align with sims

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

soc_compare <- soc_sim |>
  left_join(soc_obs) |>
  # ??
  drop_na(obs_SOC)
  # TODO will eventually want to have PFTs labeled here


## Scatterplot

if (!dir.exists(args$output_dir)) dir.create(args$output_dir, recursive = TRUE)
soc_lm_plot <- ggplot(soc_compare) +
  aes(obs_SOC, TotSoilCarb) +
  geom_point() +
  geom_abline(lty = "dotted") +
  geom_smooth(method = "lm") +
  xlab("Measured 0-30 cm soil C stock (kg C / m2)") +
  ylab("Simulated 0-30 cm soil C stock (kg C / m2)") +
  theme_bw()
ggsave(
  file.path(args$output_dir, "SOC_scatter.png"),
  plot = soc_lm_plot,
  height = 8,
  width = 8
)



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
  ) |>
  select(-data, -fit)
write.csv(
  soc_fits,
  file.path(args$output_dir, "SOC_model_fit.csv"),
  row.names = FALSE
)

soc_fits |>
  ungroup() |>
  summarize(across(r2:bias, c(mean = mean, sd = sd))) |>
  pivot_longer(everything(), names_to = c("stat", ".value"), names_sep = "_") |>
  write.csv(
    file.path(args$output_dir, "SOC_fit_summary.csv"),
    row.names = FALSE
  )
