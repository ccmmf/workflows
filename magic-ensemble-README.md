# magic-ensemble CLI

`magic-ensemble` is a command-line interface for running SIPNET carbon flux
ensemble workflows. It fetches or stages input data, builds initial conditions
and model settings, and dispatches ensemble runs locally or via Slurm.

---

## Prerequisites

| Tool | Notes |
|---|---|
| `yq` | mikefarah/yq v4 (jq-style). Other `yq` implementations are not supported. |
| `aws` | AWS CLI v2; required only for `get-demo-data`. |
| `Rscript` | With packages listed per step (see *Commands* below). |
| `python3` | Required for `prepare` (patches template.xml). |
| `apptainer` | Required only when `use_apptainer: true` in your config. |

---

## Quick Start

**Using the 2a grass example:**
```bash
# 1. Copy and edit the example config
cp examples/2a_grass/example_user_config.yaml my_config.yaml
$EDITOR my_config.yaml   # at minimum, set run_dir

# 2. Fetch demo data (skip if you have your own inputs — see "Supplying Your Own Data")
./magic-ensemble get-demo-data --config my_config.yaml

# 3. Prepare: stage inputs, build climate files, ICs, and settings XML
./magic-ensemble prepare-example-2a --config my_config.yaml

# 4. Run the ensemble
./magic-ensemble run-ensembles --config my_config.yaml
```

**Using the canonical workflow (bring your own data):**
```bash
cp examples/2a_grass/example_user_config.yaml my_config.yaml
$EDITOR my_config.yaml   # set run_dir, pecan_dispatch, and external_paths
./magic-ensemble prepare --config my_config.yaml
./magic-ensemble run-ensembles --config my_config.yaml
```

Add `--verbose` to any command to echo the exact shell and Rscript calls as
they execute.

---

## Configuration

Copy `examples/2a_grass/example_user_config.yaml` or
`examples/1b_statewide_woody/example_user_config.yaml` as a starting point.
All keys except `run_dir` are optional and fall back to the defaults shown below.

| Key | Default | Description |
|---|---|---|
| `run_dir` | **required** | Directory for all run outputs. Relative paths are resolved from the directory where you invoke `./magic-ensemble`. |
| `start_date` | `2016-01-01` | Run start date (YYYY-MM-DD). |
| `end_date` | `2023-12-31` | Run end date (YYYY-MM-DD). |
| `run_LAI_date` | `2016-07-01` | Date used for LAI lookup during IC build. |
| `n_ens` | `20` | Number of parameter ensemble members. |
| `n_met` | `10` | Number of meteorology ensemble members. |
| `ic_ensemble_size` | `100` | IC ensemble draw size. |
| `n_workers` | `1` | Parallel workers for the ERA5 conversion step. |
| `use_apptainer` | `false` | Run R steps inside the workflow Apptainer container. |
| `pecan_dispatch` | _(none)_ | Dispatch mode for `run-ensembles`. Required for `prepare` and `run-ensembles`. |
| `external_paths` | _(none)_ | User-provided input files to stage into `run_dir` before `prepare` runs (see below). |

Fixed internal paths, S3 coordinates, dispatch XML, and Apptainer image
details are defined in `workflow/workflow_manifest.yaml` and are not set in
user configs.

---

## Commands

### `get-demo-data`

Downloads demo input data from S3 and creates the run directory. Use this if
you do not have your own ERA5, IC, or site data.

**Requires:** `aws` CLI; S3 credentials for the CCMMF bucket.

**Produces:** ERA5 NetCDF files, IC files, and site info CSV inside `run_dir`.

### `prepare`

Runs the canonical `workflow/` scripts (steps 00–03). Use this with your own
data supplied via `external_paths`.

| Step | Script | R packages |
|---|---|---|
| 00 | Stage external inputs; create run directory | — |
| 01 | `workflow/01_ERA5_nc_to_clim.R` | `future`, `furrr` |
| 02 | `workflow/02_ic_build.R` | `tidyverse` |
| 03 | `workflow/03_xml_build.R` | `PEcAn.settings` |

After step 00, `template.xml` is patched with the `<host>` dispatch block
selected by `pecan_dispatch` (and the Apptainer SIF path when applicable).

**Requires:** `pecan_dispatch` set in config; `python3` on PATH.

**Produces:** `settings.xml` in `run_dir`, ready for `run-ensembles`.

### `prepare-example-2a`

Runs preparation steps using the `examples/2a_grass/` scripts (statewide
2-PFT grassland). Use with `examples/2a_grass/example_user_config.yaml`.

### `prepare-example-1b`

Runs preparation steps using the `examples/1b_statewide_woody/` scripts
(statewide woody crops). Use with
`examples/1b_statewide_woody/example_user_config.yaml`.

Both `prepare-example-*` commands follow the same four-step sequence as
`prepare` and accept the same config keys.

### `run-ensembles`

Runs `workflow/04_run_model.R` using the `settings.xml` produced by any
`prepare` or `prepare-example-*` command. The R script runs on the host and
dispatches ensemble members to workers (local or Slurm) as configured in the
patched `settings.xml`.

**Requires:** `PEcAn.all` R package; `settings.xml` present in `run_dir`.

---

## Dispatch Options

Set `pecan_dispatch` in your config to one of the following:

| Value | Description |
|---|---|
| `local-gnu-parallel` | Runs ensemble members locally using GNU parallel. No cluster required. |
| `slurm-dispatch` | Submits ensemble members as Slurm batch jobs via `sbatch`. |

The corresponding `<host>` XML block is injected into `template.xml` during
`prepare` step 00.

---

## Using Apptainer

Set `use_apptainer: true` in your config to run the R steps inside the
workflow container. The CLI will:

1. Attempt `module load apptainer` if `apptainer` is not already on PATH.
2. Look for the SIF file in `run_dir`. If absent, pull it from the registry
   defined in `workflow_manifest.yaml`.
3. Bind `run_dir` and the repo root into the container for each R step.

`run-ensembles` always runs `04_run_model.R` on the host, but when
`use_apptainer: true` the SIF must be present in `run_dir` because dispatched
job scripts reference it directly.

---

## Supplying Your Own Data

If you have your own ERA5, site, or template files, skip `get-demo-data` and
use `external_paths` in your config to inject them:

```yaml
external_paths:
  template_file: /path/to/my-template.xml
```

Each key must match a key under `paths` in `workflow/workflow_manifest.yaml`.
The file is copied into `run_dir` at the location the workflow expects, before
`prepare` runs. Paths may be absolute or relative to the directory where you
invoke `./magic-ensemble`.

---

## Troubleshooting

**`yq` not found or manifest parse fails**
Install mikefarah/yq v4. The `yq` distributed with some Linux package managers
is a different tool and is not compatible.

**`run_dir is required`**
Your config file is missing `run_dir`. This is the only key with no default.

**`Unknown pecan_dispatch value`**
The value of `pecan_dispatch` in your config does not match any key in
`workflow_manifest.yaml`. Valid options are printed when this error occurs.

**`staged template.xml not found`**
`prepare` could not find `template.xml` in `run_dir`. Either run
`get-demo-data` first, or supply `external_paths.template_file` in your config.

**`apptainer` not available**
Run `module load apptainer` before invoking the CLI, or ensure `apptainer` is
on your PATH. Singularity is not supported.
