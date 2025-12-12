# Sipnet model runs for Sarah Kanee 2025 AGU talk

Design: 17 anchor sites, run with and without events for tillage, planting, harvest, irrigation, and phenology from the monitoring pipeline.

Goal: Compare model predictions of LAI, SoilMoist, GPP, SoilResp, AGB, and NEE modeled with and without events.


## Create workflow directory

I'll do this inside the existing `workflows` repo and symlink in the files I need; May make sense later to archive this separately, but this is easy and avoids duplicating files too early.

Files reused here:
* Weather data: ERA5 0.5-degree grid, 2016-2024 is already prepared in Sipment `.clim` format for the whole state (~5.6 GB).
* Initial condition files (~23.5 MB, takes an hour or so generate): Aboveground biomass from LandTrendr 2016, SOC from SoilGrids, soil moisture from ECMWF multi-satellite data, LAI from MODIS; plus leaf and wood carbon content from combining AGB, LAI, and PFT-specific SLA estimates.
	- Note that these do not yet incorporate any of the remote-sensed values from the monitoring pipeline -- we'll add those later.
* Run scripts 03_xml_build.R, 04_set_up_runs.R, 05_run_model.R
* For the unmanaged run, irrigation via static events.in file

```{sh}
cd workflows
export EXISTING_WORKFLOW=$(realpath 3_rowcrop)
mkdir one_off_analyses/kanee_agu_2025 && cd one_off_analyses/kanee_agu_2025
ln -s $(realpath ../../data_raw) data_raw
mkdir data
ln -s "$EXISTING_WORKFLOW"/data/ERA5_CA_SIPNET data/ERA5_CA_SIPNET
ln -s "$EXISTING_WORKFLOW"/data/IC_files data/IC_files
ln -s "$EXISTING_WORKFLOW"/sipnet.git sipnet.git
```


## Fetch event files from BU server

Note: The filenames are a bit confusing because of some rapid updates while iterating. As of 2025-12-11, _most_ event types in these files start in 2018. `anchors_combinedEvents_2018-2023.csv` has irrigation starting in 2016 and other events still starting in 2018, while `anchors_irrigation_events_2018-2023.csv` is also still 2018-2023 as labeled.

Why do most events start in 2018 instead of 2016? To avoid fighting format differences between the 2016 and 2018 DWR crop maps. Sarah plans to extend all event types to 2016 soon and we will edit this pipeline when that's complete.

```{sh}
scp -r \
	cblack1@geo.bu.edu:/projectnb/dietzelab/ccmmf/management/event_files/ \
	data_raw/kanee_anchor_event_files/
```

Recording the versions used on 2025-12-11:

```{sh}
mv anchors_harvestEvents_2018-2023 anchors_harvestEvents_2018-2023.csv
shasum data_raw/kanee_anchor_event_files/*
```

Which produces:

```
cb911f85a9847738b0ff0b1bd5b4f38edbfbfde4  data_raw/kanee_anchor_event_files/anchors_combinedEvents_2018-2023.csv
07dd633b71bbc5588d5a85050f44accd5f8efb07  data_raw/kanee_anchor_event_files/anchors_combinedEvents_2018-2023.json
bc189100778219743dc92f738739589a394c4bb7  data_raw/kanee_anchor_event_files/anchors_event_overlap_2018-2023.csv
e226c31f7cf6bd20963868fb34427291f6946d01  data_raw/kanee_anchor_event_files/anchors_harvestEvents_2018-2023.csv
501876a53a16b44e46591b8a342a1aca0932bb92  data_raw/kanee_anchor_event_files/anchors_harvestEvents_2018-2023.json
82680206b2bfb6cd21c0c6272a2084bd39119388  data_raw/kanee_anchor_event_files/anchors_irrigation_events_2018-2023.csv
abe53309470576582d87d137189ca85fd32aed53  data_raw/kanee_anchor_event_files/anchors_irrigation_events_2018-2023.json
62a758fba1946ba1bf9d40ded0f3d1db6e84d4a0  data_raw/kanee_anchor_event_files/anchors_phenoParams_2018-2023.csv
f95878325d53f37838e7d3ae8086e5bcca571222  data_raw/kanee_anchor_event_files/anchors_phenoParams_2018-2023.json
5c70b67312f7be594d44bd8622e939ba9a683257  data_raw/kanee_anchor_event_files/anchors_plantingEvents_2018-2023.csv
50f31594d27b1e2cfb4099c301b7af043816899e  data_raw/kanee_anchor_event_files/anchors_plantingEvents_2018-2023.json
451f69136e0d022db41b5d1c961da0878c7c2c4b  data_raw/kanee_anchor_event_files/anchors_tillageEvents_2018-2023.csv
b3bea17a301001038fc7fb0997b56071df91fa24  data_raw/kanee_anchor_event_files/anchors_tillageEvents_2018-2023.json
```


## Convert phenology files 

All expected columns are present already, just need to lowercase `leafOnDay` and `leafOffDay` columns.

The result will be a single CSV containing all years of data from each site that had information available, and we'll pass the same path into every site of settings.xml.

When processing each site, write.configs.SIPNET will try first to use that site's record for the starting year if available, else the average of all available years from that site, else the DOY 144/285 hardcoded in PEcAn's default parameter template.

Note 1: Since we'll run Sipnet from 2016-2024 and all phenology starts in 2018, the net effect will be that PEcAn uses the mean of the dates reported for each site. That seems reasonable for this run.

Note 2: Even though all sites see the same file, no cross-site info is used here. Sites with no data will _not_ take their leaf-on and leaf-off dates from other sites in the same file. In the context of a California-specific pipeline we might want to provide state-specific values in the template or include gapfilling in the monitoring workflow (filling missing phenology from nearby sites with the same crop type) rather than let the model use DOY 144/285 (which were probably chosen for Niwot Ridge, Colorado).

TODO: As far as I can tell the phenology file is the only place we use fully lowercase names for these parameters. Should write.config.SIPNET be updated to accept files that call them `leafOnDay`/`leafOffDay` as well/instead?

```{sh}
sed -e 's/leafOnDay/leafonday/g' \
	-e 's/leafOffDay/leafoffday/g' \
	data_raw/kanee_anchor_event_files/anchors_phenoParams_2018-2023.csv \
	> data/phenology.csv
```


## Set up management event files

As noted above, these files contain only irrigation in 2016 or 2017 -- planting/harvest/tillage start in 2018. Since all sites are treated as woody this won't make a huge difference, but we should revisit it if not adding events for these years soon.

The currently available JSON files do not follow the PEcAn events schema (they are lists of events each with its own site_id; the events schema calls for lists of sites each with its own block of events), so first convert to the PEcan events standard. TODO: upstream tools ought to generate this in the first place.

```{R}
read.csv("data_raw/kanee_anchor_event_files/anchors_combinedEvents_2018-2023.csv") |>
	dplyr::filter(
		event_type != "phenology",
		!(event_type == "irrigation" & amount_mm == 0)
	) |>
	dplyr::mutate(pecan_events_version = "0.1.0") |>
	dplyr::nest_by(site_id, pecan_events_version, .key="events") |>
	jsonlite::write_json("data/events/combined_events.json")
```

Now we can convert from JSON to Sipnet events format.
```{R}
PEcAn.SIPNET::write.events.SIPNET(
	"data/events/combined_events.json",
	"data/events/"
)
```

For the unmanaged comparison, we'll use a fixed events file that contains 1520 mm irrigation each year,
as used in statewide runs to date. To keep the managed and unmanaged pipelines parallel, let's copy it into (identical!) files named for each site:

```{sh}
mkdir data/events_fixedirri
cd data/events
find . -name 'events-*.in' -exec cp "$EXISTING_WORKFLOW"/data/events.in ../events_fixedirri/{} \;
cd -
```


## Set up site info

```{R}
anchor_sites <- read.csv(
  file.path(Sys.getenv("EXISTING_WORKFLOW"), "site_info.csv"),
  colClasses = "character"
)
sites_wanted <- read.csv(
  "data_raw/kanee_anchor_event_files/anchors_combinedEvents_2018-2023.csv",
  colClasses = "character"
)$site_id
write.csv(
  anchor_sites[anchor_sites$id %in% sites_wanted,],
  file = "site_info.csv",
  row.names = FALSE
)
```


## Set up template.xml

This step is done manually rather than rerunnable by clicking through the notebook -- We _could_ do this as a horrible set of sed commands, but they'd be hard to read and the payoff seems minimal.

1. Set output variables for the ensemble analysis. Note: These are a convenience but not essential -- variables not listed here can always be retrieved from the full output files for posthoc analysis.

2. For the managed run only, set path to the phenology file.

Started by copying `"$EXISTING_WORKFLOW"/template.xml`, then hand-edited:

```
--- /Users/chrisb/cur/ccmmf/workflows/3_rowcrop/template.xml	2025-12-08 20:50:39
+++ template_unmanaged.xml	2025-12-09 10:03:56
@@ -26,11 +26,12 @@
  </pfts>
  <ensemble>
   <size><!-- inserted at config time --></size>
-  <variable>NPP</variable>
-  <variable>TotSoilCarb</variable>
-  <variable>AbvGrndWood</variable>
-  <variable>Qle</variable>
-  <variable>SoilMoistFrac</variable>
+  <variable>LAI</variable>
+  <variable>SoilMoist</variable>
+  <variable>GPP</variable>
+  <variable>SoilResp</variable>
+  <variable>AGB</variable>
+  <variable>NEE</variable>
   <samplingspace>
    <parameters>
     <method>uniform</method>
```

```
--- template_unmanaged.xml	2025-12-09 10:03:56
+++ template_managed.xml	2025-12-08 23:46:53
@@ -74,6 +74,9 @@
      <ensemble><!-- inserted at config time --></ensemble>
      <path><!-- inserted at config time --></path>
    </events>
+   <leaf_phenology>
+     <path>data/phenology.csv</path>
+   </leaf_phenology>
   </inputs>
   <start.date><!-- inserted at config time --></start.date>
   <end.date><!-- inserted at config time --></end.date>
```

TODO: It's a little inelegant that phenology gets set and unset in the template file while events get set and unset at the settings build stage. Consider picking one approach for both (which might involve adding yet another configuration option to xml_build.R).


## Generate settings files, set up rundirs 

```{sh}
"$EXISTING_WORKFLOW"/03_xml_build.R \
	--ic_dir=data/IC_files \
	--site_file=site_info.csv \
	--template_file=template_managed.xml \
	--output_file=settings_managed.xml \
	--output_dir_name=output_managed \
	--event_dir=data/events
"$EXISTING_WORKFLOW"/04_set_up_runs.R --settings=settings_managed.xml
```

```{sh}
"$EXISTING_WORKFLOW"/03_xml_build.R \
	--ic_dir=data/IC_files \
	--site_file=site_info.csv \
	--template_file=template_unmanaged.xml \
	--output_file=settings_unmanaged.xml \
	--output_dir_name=output_unmanaged \
   	--event_dir=data/events_fixedirri
"$EXISTING_WORKFLOW"/04_set_up_runs.R --settings=settings_unmanaged.xml
```


## Run model

```{sh}
export NCPUS=8
"$EXISTING_WORKFLOW"/05_run_model.R --settings=output_managed/pecan.CONFIGS.xml
"$EXISTING_WORKFLOW"/05_run_model.R --settings=output_unmanaged/pecan.CONFIGS.xml
```


## Extract results

The output directory already contains single-site timeseries and histogram plots for each variable of interest, but they're named with opaque hashes that are hard to compare between treatments. Let's get a single table of results instead.

Caution: 9 years of half-hourly model output is over 150k rows, so beware that loading all 20 replicates from 17 sites in both management conditions will produce `2*20*17*9*365*48` = more than 100M rows.

For a first pass, here are daily means of each variable (aggregated as we read each file) to get it down to 2.2M rows; note that some of these variables (GPP, NEE, soilResp) would probably be more intuitive as sums instead.

```{R}
library(tidyverse)

list_output_files <- function(modeldir) {
  file.path(modeldir, "out") |>
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
    mutate(across(c("ens_num", "year"), as.numeric))
}

read_daymeans <- function(ncfile, variables) {
  PEcAn.utils::read.output(
   	ncfiles = ncfile,
    dataframe = TRUE,
    variables = variables,
    print_summary = FALSE,
    verbose = FALSE
  ) |>
    mutate(doy = yday(posix)) |>
    summarize(across(everything(), mean), .by = doy) |>
    select(-year) # already present outside nested cols
}

output_files <- bind_rows(
  managed = list_output_files("output_managed"),
  unmanaged = list_output_files("output_unmanaged"),
  .id = "condition"
)
vars <- c("LAI", "SoilMoist", "GPP", "SoilResp", "AGB", "NEE")
results <- output_files |>
  nest_by(condition, ens_num, site, year, .key = "path") |>
  mutate(contents = map(path, \(x) read_daymeans(x, vars))) |>
  select(-path) |>
  unnest(contents)

save(results, file="results_daily_means.Rdata")
results |>
  mutate(across(c(where(is.double), -posix), zapsmall)) |>
  write.csv(file = "results_daily_means.csv", row.names = FALSE)

result_ci <- results |>
  group_by(condition, site, year, doy, posix) |>
  summarize(across(-ens_num,
  				   c(q5 = ~quantile(., 0.05),
  				     mean = mean,
  				     q95 = ~quantile(., 0.95))))
save(result_ci, file="results_intervals.Rdata")
result_ci |>
  mutate(across(c(where(is.double), -posix), zapsmall)) |>
  write.csv(file = "results_intervals.csv", row.names = FALSE)

by_var <- result_ci |>
  pivot_longer(
  	cols = ends_with(c("q5", "mean", "q95")),
  	names_to = c("variable", ".value"),
  	names_pattern = "(.*)_([^_]+)")


save_gg <- function(plt, title) {
  name <- paste0(gsub(" ", "_", title), ".png")
  ggsave(
   	file = file.path("plots", name),
   	plot = plt,
   	width = 12,
   	height = 8
  )
}

plot_by_var <- function(df, title) {
  plt <- ggplot(df) +
    aes(x = posix, y = mean, color = condition) +
    facet_wrap(~variable, scales = "free_y") +
    geom_line() +
    geom_line(aes(y=q5), lty = "dashed") +
    geom_line(aes(y=q95), lty = "dashed") +
    theme_bw() +
    xlab(NULL) +
    ggtitle(title)
  save_gg(plt, title)
}

plot_by_site <- function(df, title) {
  plt <- ggplot(df) +
    aes(x = posix, y = mean, color = condition) +
    facet_wrap(~site, scales = "free_y") +
    geom_line() +
    geom_line(aes(y=q5), lty = "dashed") +
    geom_line(aes(y=q95), lty = "dashed") +
    theme_bw() +
    xlab(NULL) +
    ggtitle(title)
   save_gg(plt, title)
}

dir.create("plots")

by_var |>
  group_by(site) |>
  group_walk(~plot_by_var(df = .x, title = paste0("Site", .y$site)))
by_var |>
  group_by(variable) |>
  group_walk(~plot_by_site(df = .x, title = .y$variable))

lai_doy <- result_ci |>
  ggplot() +
  aes(doy, LAI_mean, color = condition, group = paste(condition, year)) +
  geom_ribbon(aes(ymin=LAI_q5, ymax = LAI_q95, fill = condition), alpha = 0.01, lty = "dotted") +
  geom_line() +
  facet_wrap(~site) +
  theme_bw() +
  ylab("LAI") +
  xlab("DOY") +
save_gg(lai_doy, "LAI by day")
```
