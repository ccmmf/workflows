# Running statewide inventory and projections, 2026-09-26

## Context

This is the Markdown file where Chris Black manually recorded steps while
trial-and-erroring through a first complete run of the statewide MAGiC
ensemble workflow (inventories and projections, 1000 sites) on a new-to-him HPC.

My current plan is to move pieces of this to README.md as we retest them,
then eventually remove this file. But meanwhile here's what I actually did.


## OK here we go

Have already: Existing 20260923 inventory output using v2 management data is
run and available at /work/hdd/bgat/cblack3/magic/magic-inventory-20260923/

* Run 3-ens-member and 10-ens-member projection tests of all three scenarios, with 09/23 inventory as IC

* Rerun inventory with v5 mgmt on the nvme partition -> expect it to finish
faster than others

Kick off data prep for all 3 full-sized projections while the above tests run


```sh
conda activate pecan-all-1.18
export AWS_PROFILE=magic
export PROJECT_ROOT=/work/hdd/bgat/cblack3/magic/
export CONFIGS=/work/hdd/bgat/cblack3/magic/magic-ensemble-configs-20260925/
cd "$PROJECT_ROOT"
```


## pull data/inputs/code updates

```sh
aws s3 sync s3://carb/management/crops/ data_raw/management/crops/
aws s3 sync s3://carb/management/harvest/ data_raw/management/harvest/
aws s3 sync s3://carb/management/planting/ data_raw/management/planting/
aws s3 sync s3://carb/management/phenology/ data_raw/management/phenology/
aws s3 sync s3://carb/management/tillage/ data_raw/management/tillage/
aws s3 sync s3://carb/management/irrigation/ data_raw/management/irrigation/
aws s3 sync s3://carb/management/fertilization/ \
  data_raw/management/fertilization/
aws s3 sync s3://carb/management/ncc/ data_raw/management/ncc/
# aws s3 sync s3://carb/met/ data_raw/met/ # NB contains 13 GB raw wrf tarball
# Sync hung, copied instead:
aws s3 cp s3://carb/met/wrf_met_CA_45km_2024_2051.tgz data_raw/met/ \
  wrf_met_CA_45km_2024_2051.tgz
aws s3 sync s3://carb/IC/ data_raw/IC/
aws s3 sync s3://carb/pfts/magic_v1.2 data_raw/pfts/magic_v1.2
aws s3 cp s3://carb/inventory/magic-ensemble-configs-20260925.tgz .
tar xf magic-ensemble-configs-20260925.tgz
cd data_raw/met/
tar xf ERA5_CA_nc_2016_2024.tgz
tar xf wrf_met_CA_45km_2024_2051.tgz # NB expands to 17 GB
cd -

cd workflows
git fetch
git checkout projections
git pull origin projections
cd "$PROJECT_ROOT"
```


## Grab restarts from previous inventory

(output path chosen to match what's already in the debug yamls)

```sh
sbatch --job-name collect-restart --account bgat-delta-cpu -p cpu \
  --mem=2GB --time=01:00:00 \
  --nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
  --wrap="./tools/collect_inventory_restarts_and_samples.R \
    --rundir ${PROJECT_ROOT}/magic-inventory-20260923/output \
    --out ${PROJECT_ROOT}/magic-inventory-end-restarts-20260923"
```
This took a long time!


## Clear up nvme execution space

```sh
mkdir ${PROJECT_ROOT}/from-nvme
mv /work/nvme/bgat/cblack3/magic/*.tgz ${PROJECT_ROOT}/from-nvme
```


## Inventory prep

```sh
cd workflows
sbatch --job-name inv-prep \
--output=/work/nvme/bgat/cblack3/magic/inv-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu \
--mem=8GB --time 48:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_queue/inventory.yaml prepare-example-3"
```





## Full-sized projection prep

This feels a bit inefficient because BAU and NBS will prepare the same met data
twice and BAU and SSP585 will prepare the same events twice, but let's just let
'em do it.

Creating empty restart folder now for projections to point to while setup runs,
must remember to populate before run-projections

```sh
mkdir /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925
```

[note `20230925` typo -- see corrected run below]

```sh
sbatch --job-name BAU-prep \
--output=/work/hdd/bgat/cblack3/magic/BAU-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_queue/BAU.yaml prepare-projections"

sbatch --job-name NBS-prep \
--output=/work/hdd/bgat/cblack3/magic/NBS-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_queue/NBS.yaml prepare-projections"

sbatch --job-name SSP585-prep \
--output=/work/hdd/bgat/cblack3/magic/SSP585-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_queue/SSP585.yaml prepare-projections"
```





## 100-site projection prep

Decision on the fly: These should fit in the nvme space; run them there.

```sh
vim "$CONFIGS"/delta_debug/BAU_100site.yaml \
  "$CONFIGS"/delta_debug/NBS_100site.yaml \
  "$CONFIGS"/delta_debug/SSP585_100site.yaml
```
edited run_dir in line 11 of each file from `/work/hdd/...` to `/work/nvme/...`

Full-sized inventory is already started in nvme, no need for a 100-site version
 [Notice the `20230925` typo in BAU and NBS log names -- see below]

```sh
sbatch --job-name BAU100-prep \
--output=/work/nvme/bgat/cblack3/magic/BAU100-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_100site.yaml prepare-projections"

sbatch --job-name NBS100-prep \
--output=/work/nvme/bgat/cblack3/magic/NBS100-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_100site.yaml prepare-projections"

sbatch --job-name SSP585100-prep \
--output=/work/nvme/bgat/cblack3/magic/SSP585100-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_100site.yaml prepare-projections"
```

All of these use /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925
as their previous-inventory link. Realized that if they get to the
copy-prev-restarts step before I update this, the script will confusingly create
run dirs for all the old-run sites not present in the new run.
Changed all three of these instead to the still-empty 20260925 restart dir --
if any projection outraces the inventory, it will stop cleanly and can be
finished with an out-of-cli call to 05_run_model.R.

```sh
ln -sfT /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925 \
  /work/nvme/bgat/cblack3/magic/magic-projected-BAU-20230925-100site/run-inventory-output
ln -sfT /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925 \
  /work/nvme/bgat/cblack3/magic/magic-projected-NBS-20230925-100site/run-inventory-output
ln -sfT /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925 \
  /work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-100site/run-inventory-output
```

...Which made me realize the typos in the dates of the BAU and NBS logs!
I did this in both the log name and the output folder name in the config files,
so both BAU and NBS appear in directories whose names end in `20230925` where
they should be `20260925`
Additionally, the NBS scenarios are run with v2 management while inventory, BAU
and SSP585 use v5.

Corrected these in the config files:

```sh
vim "$CONFIGS"/delta_debug/BAU_100site.yaml \
  "$CONFIGS"/delta_debug/NBS_100site.yaml
```

`:s!20230925!20260925!`
`:s!20260923!20260925!`
`:s!projections/NBS!projections/v5/NBS!`

...Let's just rerun those.

```sh
sbatch --job-name BAU100-prep \
--output=/work/nvme/bgat/cblack3/magic/BAU100-prep-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_100site.yaml prepare-projections"

sbatch --job-name NBS100-prep \
--output=/work/nvme/bgat/cblack3/magic/NBS100-prep-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_100site.yaml prepare-projections"
```


## Inventory run

[note `20230925` typo here too! This one only affected the logfile]

```sh
sbatch --job-name inv-run \
--output=/work/nvme/bgat/cblack3/magic/inv-run-20230925.log \
--account=bgat-delta-cpu --partition=cpu \
--mem=8GB --time=24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_queue/inventory.yaml run-ensembles"
```

## Reprep full-sized BAU and NBS projection

The date and mmanagement version issues I saw for 100-site runs above are
present in the full-sized configs too. Might as well fix there too
(even though not clear when these will run yet.)

```sh
vim "$CONFIGS"/delta_debug/BAU_100site.yaml \
  "$CONFIGS"/delta_debug/NBS_100site.yaml
```

`:%s!20230925!20260925!`
`:%s!20260923!20260925!`
`:%s!projections/NBS!projections/v5/NBS!`

```sh
sbatch --job-name BAU-prep \
--output=/work/hdd/bgat/cblack3/magic/BAU-prep-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_queue/BAU.yaml prepare-projections"

sbatch --job-name NBS-prep \
--output=/work/hdd/bgat/cblack3/magic/NBS-prep-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_queue/NBS.yaml prepare-projections"
```


## Full inventory config status check

I have to wait to launch projections until the full-sized inventory completes,
so they can use its end-of-run model state. How long will I be waiting?

Inventory is currently ~2 hours into run and almost 1/3 done with segmented
configs. I calculated this by seeing that

```sh
find magic-inventory-20260925/output/run/ -maxdepth 2 -name segments.csv \
| wc -l
```
= 5386 rundirs have a segments.csv. We expect 17540 when it's done,
as determined by 

```sh
ls -1 magic-inventory-20260925/data/events/**/cycles* \
  | xargs -n1 wc -l \
  | grep -v '1 ' \
  | wc -l
```

i.e. 20k cycles.csv files with the ones that are one line (empty csvs) removed.

This approach also can tell us how many segments to expect in total:

```sh
ls -1 magic-inventory-20260925/data/events/**/cycles* \
  | xargs -n1 wc -l \
  | awk '{n+=$1};END{print n}'
```

wich gives 62080 lines, 20k of which are from csv headers, leaving 42080
`segment_<nnn>` directories to be created.
The 20000 - 17540 = 2460 dirs with empty cycle CSVs will be run as single
segments, so we expect runtime to make 42080 + 2460 = 44540 Sipnet invocations
all told.

[Apparently this calculation wasn't exact: The last time I checked a few minutes
before Sipnet runs started (and therefore before run dirs started getting
deleted), there were 17671 segments.csv in the run dir)]

2026-09-28:

Run script was terminated by cluster after 24 hours walltime, but all Sipnet
jobs were submitted and in queue by then -> model runs finish, just don't have
end times in the run log for the ones still active after this.

Quick checks of directory counts show 19901 successes (with yearly netcdfs and
restart.out in out/ directory) and 99 failures (run/ directory not deleted).
Very quick skim of a few logs from failed runs finds only cases where model
crashed after soil C went to 0, but this is not a systematic check.




## Save inventory results

### Restarts: full set, subsets

First save all restart files and samples.

```sh
"$PROJECT_ROOT"/workflows/tools/collect_inventory_restarts_and_samples.R \
  --rundir "/work/nvme/bgat/cblack3/magic/magic-inventory-20260925/output" \
  --out "${PROJECT_ROOT}/magic-inventory-end-restarts-20260925"
```

Now take subsets: The restart-copying script for projections does not check
whether the number of restarts provided aligns with the number in the current
design, and would create extra subdirectories in the new rundir to match
ensemble members not found.
This should be fixed in the script, but meanwhile here's a workaround:
Save subsets of the restarts for each subset to use for projection. I'll save
one that's just ens member 1 for a single-replicate projection run, and another
of all 20 reps of the first 100 sites for a focused-site subset.

* 1 ens member: easy, only copy `restart-*-00001.out`

```sh
mkdir "$PROJECT_ROOT"/magic-inventory-end-restarts-20260925_1ens
cp "$PROJECT_ROOT"/magic-inventory-end-restarts-20260925/samples.Rdata \
  "$PROJECT_ROOT"/magic-inventory-end-restarts-20260925_1ens/samples.Rdata
find "$PROJECT_ROOT"/magic-inventory-end-restarts-20260925/ \
  -name 'restart-*-00001.out' \
  -exec cp "{}" "$PROJECT_ROOT"/magic-inventory-end-restarts-20260925_1ens/ \;
```

* 100 sites: grab from site_info_100.csv

```sh
cd "${PROJECT_ROOT}"
mkdir magic-inventory-end-restarts-20260925_100site
cp "$PROJECT_ROOT"/magic-inventory-end-restarts-20260925/samples.Rdata \
  "$PROJECT_ROOT"/magic-inventory-end-restarts-20260925_100site/samples.Rdata
srun --account bgat-delta-cpu -p cpu --time 1:00:00 --mem=4GB \
Rscript -e '
  files <- read.csv("magic-ensemble-configs-20260925/site_info_100.csv") |>
    dplyr::cross_join(data.frame(ens_id = 1:20)) |>
    dplyr::select(site_id, ens_id) |>
    dplyr::mutate(filename = sprintf("restart-%s-%05d.out", site_id, ens_id)) |>
    dplyr::pull(filename)

  res <- file.copy(
    file.path("magic-inventory-end-restarts-20260925", files),
    file.path("magic-inventory-end-restarts-20260925_100site", files)
  )
  if (!all(res)) {
    warning("Could not copy ", length(which(!res)), " files")
    if (length(which(!res)) < 1000) warning(files[!res])
  }
'
```
11 files not copied, all from models that errored (i.e. restart doesn't exist).


### Compress, relocate, upload

```sh
sbatch --job-name inv-pack \
--output=/work/nvme/bgat/cblack3/magic/inv-pack.log \
--account=bgat-delta-cpu --partition=cpu \
--mem=16GB --tasks=1 --cpus-per-task=1 \
--time=06:00:00 \
--wrap="tar czf /tmp/magic-inventory-ensembles-20260925.tgz \
    /work/nvme/bgat/cblack3/magic/magic-inventory-20260925/ \
  && mv /tmp/magic-inventory-ensembles-20260925.tgz \
    /work/hdd/bgat/cblack3/magic/magic-inventory-ensembles-20260925.tgz"
```

For reasons I didn't determine (detour through /tmp? absolute paths
changing tar behavior?) the output landed in /work/hdd/ with different
permissions than other tarballs:

```
drwxrws---+  2 cblack3 delta_bgat  68K Sep 28 04:57 magic-inventory-end-restarts-20260925_1ens
-rw-rw----+  1 cblack3 delta_bgat  29G Sep 25 20:15 magic-inventory-ensembles-20260923.tgz
-rw-rw----   1 cblack3 grp_202     29G Sep 28 06:37 magic-inventory-ensembles-20260925.tgz
-rw-rw----+  1 cblack3 delta_bgat 8.0M Sep 20 19:45 magic-inventory-inputs-20260920.tgz
-rw-rw----+  1 cblack3 delta_bgat 8.0M Sep 21 18:48 magic-inventory-inputs-20260921.tgz
```

Changed group membership and permissions with 

```sh
chgrp delta_bgat magic-inventory-ensembles-20260925.tgz 
chmod g+rw magic-inventory-ensembles-20260925.tgz 
```

```
-rw-rw----+ 1 cblack3 delta_bgat  29G Sep 25 20:15 magic-inventory-ensembles-20260923.tgz
-rw-rw----  1 cblack3 delta_bgat  29G Sep 28 06:37 magic-inventory-ensembles-20260925.tgz
-rw-rw----+ 1 cblack3 delta_bgat 8.0M Sep 20 19:45 magic-inventory-inputs-20260920.tgz
```


...but I'm not actally sure what the `+` in the 11th column for the other files
means (it's not restricted deletion, that's column 10), so not sure whether it
matters. TODO: Any further adjustment needed here?


Now upload:

```sh
aws s3 cp /work/hdd/bgat/cblack3/magic-inventory-ensembles-20260925.tgz \
  s3://carb/inventory/magic-inventory-ensembles-20260925.tgz
```

shasum of uploaded file: 6a6feb090624e261b63705c72aaa00dcc0b8b297



## 1-replicate projection runs

Uploaded an updated set of config files that corrects the typos found above
and adds projections with only 1 replicate (per Dietze suggestion).
Unpacked these before continuing.

```sh
mv magic-ensemble-configs-20260925 magic-ensemble-configs-20260925_0
aws s3 cp s3://carb/inventory/magic-ensemble-configs-20260925_2.tgz .
tar xf magic-ensemble-configs-20260925_2.tgz
# inspect what changed
diff -u --recursive \
  magic-ensemble-configs-20260925_0 \
  magic-ensemble-configs-20260925 \
  | less
```

Prep to run in nvme:

```sh
cd "$PROJECT_ROOT"/workflows
sbatch --job-name BAU-1-prep \
--output=/work/nvme/bgat/cblack3/magic/BAU-prep-1ens-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_1ens_nvme.yaml prepare-projections"

sbatch --job-name NBS-1-prep \
--output=/work/nvme/bgat/cblack3/magic/NBS-prep-1ens-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_1ens_nvme.yaml prepare-projections"

sbatch --job-name SSP585-1-prep \
--output=/work/nvme/bgat/cblack3/magic/SSP585-prep-1ens-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_1ens_nvme.yaml prepare-projections"
```

These config files assume taking restarts from the full inventory output.
Update to use the 1-ens version.

```sh
ln -sfT \
  /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925_1ens \
  /work/nvme/bgat/cblack3/magic/magic-projected-BAU-20260925-1ens/run-inventory-output
ln -sfT \
  /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925_1ens \
  /work/nvme/bgat/cblack3/magic/magic-projected-NBS-20260925-1ens/run-inventory-output
ln -sfT \
  /work/hdd/bgat/cblack3/magic/magic-inventory-end-restarts-20260925_1ens \
  /work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens/run-inventory-output
```


And launch once ready

```sh
sbatch --job-name BAU-1-run \
--output=/work/nvme/bgat/cblack3/magic/BAU-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_1ens_nvme.yaml run-projections"

sbatch --job-name NBS-1-run \
--output=/work/nvme/bgat/cblack3/magic/NBS-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_1ens_nvme.yaml run-projections"

sbatch --job-name SSP585-1-run \
--output=/work/nvme/bgat/cblack3/magic/SSP585-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_1ens_nvme.yaml run-projections"
```


After 1 hour, SSP run was 630/1000 dirs through segmented configs;
BAU and NBS both still logging 
'step creation still disabled, retrying (Requested nodes are busy)'


SSP585 finishes setup, then fails with

```
2026-09-28 08:21:34.390326 INFO   [start_model_runs] : 
   ------------------------------------------------------------------- 
  |                                                                      |   0%
  |                                                                      |   0%Error in `<current-expression>` : error in running command
Calls: <Anonymous> -> start_model_runs -> <Anonymous> -> system2
```


...because I left workflow-parallelism-mode and pecan-parallelism mode set to
"local" in the config:

```
magic-ensemble: WARNING: step 'run-model' is marked slurm: true in the manifest, but workflow_parallelism_mode is set to 'local' in your config -- running it unwrapped, as configured.
magic-ensemble: Rscript: /u/cblack3/.conda/envs/pecan-all-1.18/bin/Rscript
 (cd "/work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens" && Rscript "/work/hdd/bgat/cblack3/magic/workflows/workflow/05_run_model.R" --settings /work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens/output/pecan.CONFIGS.xml --check_interva
l 60)
```


Let's try an off-cli hack

```sh
module load parallel
cd "$PROJECT_ROOT"/workflows
sbatch --job-name SSP585-run-manual \
--output=/work/nvme/bgat/cblack3/magic/SSP585-run-1ens-20230925-manual-launch.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="(cd /work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens && Rscript /work/hdd/bgat/cblack3/magic/workflows/workflow/05_run_model.R --settings /work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens/output/pecan.CONFIGS.xml --check_interval 60)"
```


no, this produces a logfile with the  pecan_version output and "PEcAn Workflow Complete",
but apparently no models run.


Canceled still-hanging BAU and NBS runs. Their settings use slurm submission
already, so that is not their issue.


```sh
vim magic-projected-SSP585-20260925-1ens/settings.xml
```
Edited host section to replace `<modellauncher>` and `<stat>` with

```
<qsub>sbatch -J @NAME@ -o @STDOUT@ -e @STDERR@ --account=bgat-delta-cpu --partition=cpu --tasks=1 --cpus-per-task=1 --mem=2GB --time=00:05:00 </qsub>
<qsub.jobid>Submitted batch job ([0-9]+)</qsub.jobid>
<qstat>if test -z &quot;$(squeue -h -j @JOBID@)&quot;; then echo &quot;DONE&quot;; fi</qstat>
```

This should be enough to avoid rerunning prepare-projections, but still need to
rerun all of run-projections.

```sh
rm -rf magic-projected-SSP585-20260925-1ens/output
cd "$PROJECT_ROOT"/workflows
sbatch --job-name BAU-1-run \
--output=/work/nvme/bgat/cblack3/magic/BAU-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_1ens_nvme.yaml run-projections"

sbatch --job-name NBS-1-run \
--output=/work/nvme/bgat/cblack3/magic/NBS-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_1ens_nvme.yaml run-projections"

sbatch --job-name SSP585-1-run \
--output=/work/nvme/bgat/cblack3/magic/SSP585-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_1ens_nvme.yaml run-projections"
```


These hung too. Do I need to allocate more memory in the wrapper?





```sh
sbatch --job-name BAU-1-run \
--output=/work/nvme/bgat/cblack3/magic/BAU-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu \
--mem=8GB --time=24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_1ens_nvme.yaml run-projections"

sbatch --job-name NBS-1-run \
--output=/work/nvme/bgat/cblack3/magic/NBS-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu \
--mem=8GB --time=24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_1ens_nvme.yaml run-projections"

sbatch --job-name SSP585-1-run \
--output=/work/nvme/bgat/cblack3/magic/SSP585-run-1ens-20230925.log \
--account=bgat-delta-cpu --partition=cpu \
--mem=8GB --time=24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_1ens_nvme.yaml run-projections"
```


These go through queue without further hangs, but every Sipnet run errors:
restart files did not actually get copied into rundirs.

Found and fixed the missing `full.names = TRUE` in workflows commit 6c92eb3,
re-pulled branch.

To avoid waiting for segmented configs to rerun, commented out steps 1 and 2 of
`run-projection` in the workflow manifest, then cleaned up outdirs and reran:

```sh
find /work/nvme/bgat/cblack3/magic/magic-projected-BAU-20260925-1ens/output/out -type f -delete
find /work/nvme/bgat/cblack3/magic/magic-projected-NBS-20260925-1ens/output/out -type f -delete
find /work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens/output/out -type f -delete
sbatch --job-name BAU-1-run2 \
  --output=/work/nvme/bgat/cblack3/magic/BAU-run-1ens-20230925-run2.log \
  --account=bgat-delta-cpu --partition=cpu \
  --mem=8GB --time=24:00:00 \
  --nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
  --wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_1ens_nvme.yaml run-projections"
sbatch --job-name NBS-1-run2 \
  --output=/work/nvme/bgat/cblack3/magic/NBS-run-1ens-20230925-run2.log \
  --account=bgat-delta-cpu --partition=cpu \
  --mem=8GB --time=24:00:00 \
  --nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
  --wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_1ens_nvme.yaml run-projections"
sbatch --job-name SSP585-1-run2 \
  --output=/work/nvme/bgat/cblack3/magic/SSP585-run-1ens-20230925-run2.log \
  --account=bgat-delta-cpu --partition=cpu \
  --mem=8GB --time=24:00:00 \
  --nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
  --wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_1ens_nvme.yaml run-projections"
```


...These go through the queue but do nothing because all three STATUS files have
existing MODEL lines that make run_model.R skip starting model runs.

Renamed each STATUS file to STATUS_, submitted same commands above again.

Output dirs now appear populated.


## Compress and archive 1-site projections

```sh
sbatch --job-name BAU-pack \
  --output=/work/nvme/bgat/cblack3/magic/BAU-pack.log \
  --account=bgat-delta-cpu --partition=cpu \
  --mem=16GB --tasks=1 --cpus-per-task=1 \
  --time=06:00:00 \
  --wrap="tar czf /tmp/magic-projected-BAU-20260925-1ens.tgz \
      /work/nvme/bgat/cblack3/magic/magic-projected-BAU-20260925-1ens/ \
    && mv /tmp/magic-projected-BAU-20260925-1ens.tgz \
      /work/hdd/bgat/cblack3/magic/magic-projected-BAU-20260925-1ens.tgz"
sbatch --job-name NBS-pack \
  --output=/work/nvme/bgat/cblack3/magic/NBS-pack.log \
  --account=bgat-delta-cpu --partition=cpu \
  --mem=16GB --tasks=1 --cpus-per-task=1 \
  --time=06:00:00 \
  --wrap="tar czf /tmp/magic-projected-NBS-20260925-1ens.tgz \
      /work/nvme/bgat/cblack3/magic/magic-projected-NBS-20260925-1ens/ \
    && mv /tmp/magic-projected-NBS-20260925-1ens.tgz \
      /work/hdd/bgat/cblack3/magic/magic-projected-NBS-20260925-1ens.tgz"
sbatch --job-name SSP585-pack \
  --output=/work/nvme/bgat/cblack3/magic/SSP585-pack.log \
  --account=bgat-delta-cpu --partition=cpu \
  --mem=16GB --tasks=1 --cpus-per-task=1 \
  --time=06:00:00 \
  --wrap="tar czf /tmp/magic-projected-SSP585-20260925-1ens.tgz \
      /work/nvme/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens/ \
    && mv /tmp/magic-projected-SSP585-20260925-1ens.tgz \
      /work/hdd/bgat/cblack3/magic/magic-projected-SSP585-20260925-1ens.tgz"
```











# End completed work

The submissions below are considered but not yet run.

Will move them up in the form actually run as I submit each job.














## Debugging segment config time

Plan: Set up a small run, execute it with time profiling enabled in R during
execution of write_segmented_configs(). This should help clarify where the
bottleneck lies.

* copied magic-ensemble-configs/delta_debug/inventory_3ens.yaml to 
magic-ensemble-configs/delta_debug/inventory_3ens_10site.yaml
* Edited run_dir from "/work/nvme/bgat/cblack3/magic/magic-inventory-20260925-3ens"
to "/work/nvme/bgat/cblack3/magic/magic-inventory-20260925-3ens-10site_10site"
* edited site_info_file from "/work/hdd/bgat/cblack3/magic/magic-ensemble-configs-20260925/site_info.csv"
to "/work/hdd/bgat/cblack3/magic/magic-ensemble-configs-20260925/site_info_10.csv"
* edited workflow/04_set_up_runs.R to save to R profiler info to
"Rprof_segconf.out" in cwd:

```
diff --git a/workflow/04_set_up_runs.R b/workflow/04_set_up_runs.R
index 307b5a7..66a7567 100755
--- a/workflow/04_set_up_runs.R
+++ b/workflow/04_set_up_runs.R
@@ -110,6 +110,7 @@ look_up_pft <- function(crop) {
     dplyr::left_join(pft_lookup, by = "crop_code") |>
     dplyr::pull(pft)
 }
+Rprof("Rprof_segconf.out")
 run_script_paths <- papply(
   settings,
   \(s) PEcAn.SIPNET::write_segmented_configs.SIPNET(
@@ -118,4 +119,5 @@ run_script_paths <- papply(
     crop2pft = look_up_pft
   )
 )
+Rprof(NULL)
 PEcAn.utils::status.end()
```

Note that I have projection runs in queue while I do this, but they are using
run-projections with the setup step commented out. Do be sure to unwind this
before running anything else.

```sh
sbatch --job-name seg-prof-prep \
  --output=/work/nvme/bgat/cblack3/magic/seg-prof-prep.log \
  --account=bgat-delta-cpu --partition=cpu \
  --mem=8GB --time 48:00:00 \
  --nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
  --wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/inventory_3ens_10site.yaml prepare-example-3"
```

```sh
sbatch --job-name seg-prof-run \
--output=/work/nvme/bgat/cblack3/magic/seg-prof-run.log \
--account=bgat-delta-cpu --partition=cpu \
--mem=8GB --time=24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/inventory_3ens_10site.yaml run-ensembles"
```








## 100-site projection runs



```sh
sbatch --job-name BAU100-run \
--output=/work/nvme/bgat/cblack3/magic/BAU100-run-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_100site.yaml run-projections"

sbatch --job-name NBS100-run \
--output=/work/nvme/bgat/cblack3/magic/NBS100-run-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=1 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_100site.yaml run-projections"

sbatch --job-name SSP585100-run \
--output=/work/nvme/bgat/cblack3/magic/SSP585100-run-20260925.log \
--account=bgat-delta-cpu --partition=cpu --time 24:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_100site.yaml run-projections"
```





































## 3-rep prep

Note that I'm running all 5 3-rep ones in nvme -- will need to watch quota when deciding which order to kick off run-projections later

```sh
sbatch --job-name inv3-prep \
--output=/work/nvme/bgat/cblack3/magic/inv3-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/inventory_3ens.yaml prepare-example-3"

sbatch --job-name BAU3-prep \
--output=/work/nvme/bgat/cblack3/magic/BAU3-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_3ens.yaml prepare-projections"

sbatch --job-name NBS3-prep \
--output=/work/nvme/bgat/cblack3/magic/NBS3-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_3ens.yaml prepare-projections"

sbatch --job-name SSP5853-prep \
--output=/work/nvme/bgat/cblack3/magic/SSP5853-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_3ens.yaml prepare-projections"
```


## 10-rep prep

```sh
sbatch --job-name inv10-prep \
--output=/work/nvme/bgat/cblack3/magic/inv10-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/inventory_10ens.yaml prepare-example-3"


sbatch --job-name BAU10-prep \
--output=/work/hdd/bgat/cblack3/magic/BAU10-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/BAU_10ens.yaml prepare-projections"


sbatch --job-name NBS10-prep \
--output=/work/hdd/bgat/cblack3/magic/NBS10-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/NBS_10ens.yaml prepare-projections"

sbatch --job-name SSP58510-prep \
--output=/work/hdd/bgat/cblack3/magic/SSP5810-prep-20230925.log \
--account=bgat-delta-cpu --partition=cpu --time 12:00:00 \
--nodes=1 --tasks=1 --tasks-per-node=1 --cpus-per-task=24 \
--wrap="./magic-ensemble --verbose --config ${CONFIGS}/delta_debug/SSP585_10ens.yaml prepare-projections"
```



## Compress and share inventory

## 10-site projection run (move up if ready sooner)

## 100-site projection run (move up if ready sooner)

## Full-sized projection run


