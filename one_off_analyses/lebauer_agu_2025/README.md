# Sipnet runs for David LeBauer 2025 AGU talk

Design: 100 row-crop anchor sites, run with event files corresponding to 6 hypothetical management scenarios `baseline`, `compost`, `reduced_till`, `zero_till`, `reduced_irrig_drip`, and `stacked`.

Goal: Compare statewide predictions of [variables TK] under differing managements.


## Create workflow directory

Many of the files needed are already set up for the MAGiC phase 3 workflow. I'll symlink those rather than duplicate them.


```{sh}
# cd path/to/ccmmf
export SCENARIO_REPO=$(realpath scenarios)
cd workflows
export EXISTING_WORKFLOW=$(realpath 3_rowcrop)
mkdir one_off_analyses/lebauer_agu_2025 && cd one_off_analyses/lebauer_agu_2025
ln -s $(realpath ../../data_raw) data_raw
mkdir data
ln -s "$EXISTING_WORKFLOW"/data/ERA5_CA_SIPNET data/ERA5_CA_SIPNET
ln -s "$EXISTING_WORKFLOW"/data/IC_files data/IC_files
ln -s "$EXISTING_WORKFLOW"/sipnet.git sipnet.git
```


## Set up site info

```{R}
read.csv(
  file.path(Sys.getenv("EXISTING_WORKFLOW"), "site_info.csv"),
  colClasses = "character"
) |> 
  dplyr::filter(site.pft == "grass") |>
  dplyr::mutate(site.pft = "annual_crop") |>
  write.csv(
    file = "site_info.csv",
    row.names = FALSE
  )
```


## Add event files

The json versions of these are maintained in a separate repo. We'll read them from the external location and write the sipnet (`*.in`) versions as local artifacts.

Note that this analysis uses a single event file per scenario and the JSON files use the same dummy sitename (`herb_site_1`) for all of them, while write.events.SIPNET and steps downstream of it expect there to be a directory one events file per site, named `events-<siteid>.in`. We'll make whole directories full of duplicates for each scenario.

```{sh}
	mkdir data/events
	export SCENARIOS=(
		baseline
		compost
		reduced_till
		zero_till
		reduced_irrig_drip
		stacked
	)
	# Caution: assumes site id is 2nd column
	export SITES=(
		$(tail -n+2 site_info.csv | cut -d, -f2 | uniq | tr -d \")
	)
	for s in ${SCENARIOS[@]}; do
		s_dir=data/events/"$s"
		mkdir -p "$s_dir"
		json_file="$SCENARIO_REPO"/data/events_"$s".json
		Rscript \
			-e 'PEcAn.SIPNET::write.events.SIPNET(' \
			-e '  events_json = "'"$json_file"'",' \
			-e '  outdir = "data/events"' \
			-e ')'
		event_files=("${SITES[@]/#/$s_dir/events-}")
		event_files=("${event_files[@]/%/.in}")
		for f in ${event_files[@]}; do
			cp data/events/events-herb_site_1.in $f
		done
		rm data/events/events-herb_site_1.in
	done
```


## Create annual PFT

Runs for cropland have until now used a PFT calibrated for perennial semiarid grasslands, with phenology controlled by growing degree day. To avoid unwanted interactions between the GDD model and the annual crop cycle, we zero out the biomass change at the computed leaf-on and leaf-off date so that these have no effect.

Note that this simplification means leaf-off is assumed to only happen at harvest, which isn't technically true -- some crops such as cotton, soy, and rice are often fully deleafed before harvest. However, since the MAGiC system's estimates of harvest date will be primarily derived from remote-sensed NDVI, estimated "harvest" will always be tied to end of greenness anyway (though potentially with crop-specific offsets that can be tuned to account for relative timing of harvest and leaf-off).
off happen only at planting and harvest

```{R}
pd <- new.env()
load("data_raw/pfts/grass/post.distns.Rdata", envir = pd)
post.distns <- pd$post.distns
pheno_rows <- rownames(post.distns) %in% c("fracLeafFall", "leafGrowth")
post.distns$parama[pheno_rows] <- 0.0
post.distns$paramb[pheno_rows] <- 0.0
dir.create("data_raw/pfts/annual_crop")
save(post.distns, file = "data_raw/pfts/annual_crop/post.distns.Rdata")
```


## Set up template.xml

These edits were done by hand -- decided it wasn't worth the trouble of doing them programmatically.

* `cp "$EXISTING_WORKFLOW"/template.xml template.xml`
* Removed all variables but TotSoilCarb from the ensemble block -- we won't be looking site-by-site at the PDF output from running ensemble analysis, so why spend time extracting them. Left TotSoilCarb only because get.results throws a logger.severe if there are zero variables to extract.
* Updated PFT paths to point to new annnual_crop distns.

Diff between existing workflow template and the result:

```
--- /Users/chrisb/cur/ccmmf/workflows/3_rowcrop/template.xml	2025-12-08 20:50:39
+++ template.xml	2025-12-10 00:52:16
@@ -10,27 +10,17 @@
  <rundir><!-- altered at config time -->output/run</rundir>
  <pfts>
   <pft>
-   <name>temperate.deciduous</name>
-   <posterior.files>data_raw/pfts/temperate.deciduous/post.distns.Rdata</posterior.files>
-   <outdir>data_raw/pfts/temperate.deciduous/</outdir>
+   <name>annual_crop</name>
+   <posterior.files>data_raw/pfts/annual_crop/post.distns.Rdata</posterior.files>
+   <outdir>data_raw/pfts/annual_crop/</outdir>
   </pft>
   <pft>
-   <name>grass</name>
-   <posterior.files>data_raw/pfts/grass/post.distns.Rdata</posterior.files>
-   <outdir>data_raw/pfts/grass</outdir>
-  </pft>
-  <pft>
    <name>soil</name>
    <outdir>data_raw/pfts/soil/</outdir>
   </pft>
  </pfts>
  <ensemble>
   <size><!-- inserted at config time --></size>
-  <variable>NPP</variable>
   <variable>TotSoilCarb</variable>
-  <variable>AbvGrndWood</variable>
-  <variable>Qle</variable>
-  <variable>SoilMoistFrac</variable>
   <samplingspace>
    <parameters>
     <method>uniform</method>
```


## Generate settings files, set up rundirs 


```{sh}
for s in ${SCENARIOS[@]}; do
	"$EXISTING_WORKFLOW"/03_xml_build.R \
		--n_ens=20 \
		--ic_dir=data/IC_files \
		--site_file=site_info.csv \
		--template_file=template.xml \
		--output_file=settings_"$s".xml \
		--output_dir_name=output_"$s" \
		--event_dir=data/events/"$s"
	"$EXISTING_WORKFLOW"/04_set_up_runs.R --settings=settings_"$s".xml
done
```


## Run model

```{sh}
export NCPUS=8
for s in ${SCENARIOS[@]}; do
	"$EXISTING_WORKFLOW"/05_run_model.R --settings=output_"$s"/pecan.CONFIGS.xml
done
```



## Extract results

This output was really intended for the downscaling workflow, but I'll tke a quick look: let's look only at differences between treatments in soil C on monthly time steps. Since soil C changes slowly, I'll simply take the value at the end of each month rather than averaging.

First some function definitions:

```{R}
library(tidyverse)
logger_level <- PEcAn.logger::logger.setLevel("WARN")

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

read_monthly <- function(ncfile, variables) {
  PEcAn.utils::read.output(
   	ncfiles = ncfile,
    dataframe = TRUE,
    variables = variables,
    print_summary = FALSE,
    verbose = FALSE
  ) |>
  	mutate(month = month(posix)) |>
  	group_by(year, month) |>
    slice_max(posix) |>
    ungroup() |>
    select(-year) # already present outside this fn call
}

make_long_quantiles <- function(grouped_df, cols) {
  grouped_df |>
    summarize(
      across({{cols}},
             c(q5 = ~quantile(., 0.05),
               mean = mean,
               q95 = ~quantile(., 0.95))
    )) |>
    pivot_longer(
      cols = ends_with(c("q5", "mean", "q95")),
      names_to = c("variable", ".value"),
      names_pattern = "(.*)_([^_]+)"
    )
}

save_gg <- function(plt, title) {
  name <- paste0(gsub(" ", "_", title), ".png")
  ggsave(
   	file = file.path("plots", name),
   	plot = plt,
   	width = 12,
   	height = 8
  )
}
```

Now read files (this took at least half an hour on my machine)

```{R}
output_files <- c(
	"baseline", "compost", "reduced_till",
	"zero_till", "reduced_irrig_drip", "stacked"
  ) |>
  setNames(nm = _) |>
  map_chr(~paste0("output_", .)) |>
  map(list_output_files) |>
  bind_rows(.id = "scenario")

# soil C from all sites*reps*months
results <- output_files |>
  nest_by(scenario, ens_num, site, year, .key = "path") |>
  mutate(contents = map(path, \(x) read_monthly(x, "TotSoilCarb"))) |>
  select(-path) |>
  unnest(contents)
save(results, file="results_monthly_TotSoilCarb.Rdata")
results |>
  mutate(across(c(where(is.double), -posix), zapsmall)) |>
  write.csv(file = "results_monthly_TotSoilCarb.csv", row.names = FALSE)
```

...and now aggregate...

```{R}
# Treatment effects for each site*rep*month,
# first as raw diff (treatment - baseline), then as relative difference ((treat - base)/base)
result_diff <- results |>
  pivot_wider(names_from = "scenario", values_from = "TotSoilCarb") |>
  mutate(
  	d_compost = compost - baseline,
  	d_reduced_irrig_drip = reduced_irrig_drip - baseline,
  	d_reduced_till = reduced_till - baseline,
  	d_stacked = stacked - baseline,
  	d_zero_till = zero_till - baseline
  )
result_relative_diff <- results |>
  pivot_wider(names_from = "scenario", values_from = "TotSoilCarb") |>
  mutate(
  	d_compost = (compost - baseline)/baseline,
  	d_reduced_irrig_drip = (reduced_irrig_drip - baseline)/baseline,
  	d_reduced_till = (reduced_till - baseline)/baseline,
  	d_stacked = (stacked - baseline)/baseline,
  	d_zero_till = (zero_till - baseline)/baseline
  )

# Ensemble averages+quantiles within site*month
diff_ci <- result_diff |>
  group_by(site, year, month, posix) |>
  make_long_quantiles(-ens_num)
diff_relative_ci <- result_relative_diff |>
  group_by(site, year, month, posix) |>
  make_long_quantiles(-ens_num)

# Cross-site averages+quantiles for each timepoint
# Note I'm only calculating relative;
# not sure averaging raw diffs across sites is meaningful
#
# TODO this collapses ensemble and site both at once --
# should it be rolled up stepwise instead?
mean_relative_diff_ci <- result_relative_diff |>
  group_by(year, month, posix) |>
  make_long_quantiles(c(-ens_num, -site))
```

Now plotting.

These site-by-site visualizations obviously won't scale to more than a handful of sites.
I'll choose 8 sites at random; might be better to choose top and bottom most/least responsive sites?


```{R}
dir.create("plots")

selected_sites <- output_files |>
	distinct(site) |>
	slice_sample(n = 8) |>
	pull(site)

diff_plt <- diff_ci |>
  filter(
  	grepl("^d_", variable),
  	site %in% selected_sites
  ) |>
  ggplot() +
  aes(x=posix, y=mean) +
  facet_grid(variable~site, scales = "free_y") +
  geom_line() +
  geom_line(aes(y=q5), lty = "dashed") +
  geom_line(aes(y=q95), lty = "dashed") +
  theme_bw() +
  xlab(NULL) +
  ylab("Change in soil C (kg C m-2) from baseline scenario") +
  geom_hline(yintercept = 0, color="lightgreen")

rel_plt <- diff_relative_ci |>
  filter(
  	grepl("^d_", variable),
  	site %in% selected_sites
  ) |>
  ggplot() +
  aes(x=posix, y=mean*100) +
  facet_grid(variable~site, scales = "free_y") +
  geom_line() +
  geom_line(aes(y=q5*100), lty = "dashed") +
  geom_line(aes(y=q95*100), lty = "dashed") +
  theme_bw() +
  xlab(NULL) +
  ylab("Percent change in soil C from baseline scenario") +
  geom_hline(yintercept = 0, color="lightgreen")


rel_mean_plt <- mean_relative_diff_ci |>
  filter(grepl("^d_", variable)) |>
  ggplot() +
  aes(x=posix, y=mean*100) +
  facet_wrap(~variable, scales = "free_y") +
  geom_line() +
  geom_line(aes(y=q5*100), lty = "dashed") +
  geom_line(aes(y=q95*100), lty = "dashed") +
  theme_bw() +
  xlab(NULL) +
  ylab("Percent change in soil C from baseline scenario") +
  ggtitle("cross-site means") +
  geom_hline(yintercept = 0, color="lightgreen")



save_gg(diff_plt, "scenario_diffs")
save_gg(rel_plt, "scenario_pct_change")
save_gg(rel_mean_plt, "scenario_mean_pct_change")
```

