# magic-ensemble Developer Guide

This document covers the internal design of `magic-ensemble` and the
`2a_grass/` workflow: how the pieces fit together, where the boundaries are,
and what to change when adapting this CLI to a different workflow.

---

## Architecture Overview

The CLI is built on a three-layer configuration model:

```
workflow_manifest.yaml   — fixed contract: internal paths, step definitions,
                           S3 coords, dispatch XML, Apptainer image
        +
user_config.yaml         — runtime overrides: run_dir, dates, ensemble sizes,
                           dispatch mode, use_apptainer, external_paths
        +
external_paths (staged)  — user-provided files copied into run_dir before
                           prepare runs, mapped to manifest-defined destinations
```

The manifest is the source of truth for everything that is fixed per workflow.
The user config contains only the values a user legitimately needs to vary
between runs. External paths are the mechanism for injecting user-owned files
(e.g. a custom `template.xml`) without making manifest paths user-overridable.
As written, a user can only inject files that are expected by the pipeline.

---

## Execution Graph

### `get-demo-data`

```
00_fetch_s3_and_prepare_run_dir.sh
  → creates run_dir
  → downloads and extracts S3 artifact into run_dir
```

### `prepare`

```
00_stage_external_inputs.sh
  → creates run_dir
  → copies external_paths files into run_dir (manifest-defined destinations)
  → [patch_dispatch() runs after this step]
      → reads pecan_dispatch host_xml from manifest
      → substitutes @SIF@ if use_apptainer is set
      → patches <host> block in run_dir/template.xml via tools/patch_xml.py

01_ERA5_nc_to_clim.R
  reads:  run_dir/data_raw/ERA5_nc, run_dir/site_info.csv
  writes: run_dir/data/ERA5_SIPNET/

02_ic_build.R
  reads:  run_dir/site_info.csv, run_dir/data_raw/dwr_map/...,
          run_dir/data/IC_prep/, run_dir/pfts/,
          run_dir/data_raw/ca_biomassfiaald_*.tif
  writes: run_dir/IC_files/, run_dir/data/IC_prep/

03_xml_build.R
  reads:  run_dir/site_info.csv, run_dir/template.xml,
          run_dir/IC_files/, run_dir/data/ERA5_SIPNET/
  writes: run_dir/settings.xml
```

### `run-ensembles`

```
04_run_model.R  (CWD = run_dir)
  reads:  run_dir/settings.xml
  writes: run_dir/output/  (via PEcAn dispatch)
```

---

## Configuration Contract

### What belongs in the manifest

- `steps`: ordered list of scripts per command, with declared inputs/outputs and R library checks
- `paths`: all internal file/directory locations relative to `run_dir`
- `s3`: S3 endpoint, bucket, and per-resource key prefix and filename
- `pecan_dispatch`: named dispatch modes, each with a `host_xml` (and optionally `host_xml_apptainer`) block
- `apptainer`: remote registry URL, container name, tag, and SIF filename

None of these are user-overridable. Adding a new workflow means replacing or
extending the manifest, not the user config. As the underlying R-scripts evolve,
the manifest must be kept in-sync with any i/o changes made in R-scripts.

### What belongs in the user config

Scalar values that vary between runs: `run_dir`, dates, ensemble sizes,
`n_workers`, `use_apptainer`, `pecan_dispatch`. These all have fallback
defaults in `magic-ensemble`; only `run_dir` is required.

### What belongs in `external_paths`

File paths for user-owned inputs that must be injected into `run_dir` before
`prepare` runs. Keys must match entries under `manifest.paths`. The destination
is `run_dir/$(basename manifest.paths.<key>)` — derived from the manifest, not
from the source filename, so downstream scripts always find files where they
expect them.

---

## CLI Internals

### Argument parsing (`magic-ensemble` lines 50–77)

Command is the first positional argument. `--config` and `--verbose` are global
options that may appear in any order after the command. The config path is
resolved relative to the actual `pwd` at invocation time and stored as an
absolute path immediately after parsing.

### `get_val()` resolution order

```
get_val "key" "default"
  1. If CONFIG_FILE is set and the key is present and non-null → use config value
  2. Otherwise → use the default passed as the second argument
```

Only `run_dir` has an explicit post-resolution check for empty/null; all other
keys silently fall back to their defaults if absent from the config. This makes
the config contract forward-compatible: adding new keys to the CLI does not
break existing user configs.

### Path normalization

`run_dir` is resolved in two steps:
1. If relative, it is prepended with `INVOCATION_CWD` (the directory where the
   CLI was invoked, not `REPO_ROOT`).
2. The trailing slash is stripped so that `run_dir + "/" + manifest_path` never
   produces double slashes.

All manifest paths are then resolved as `run_dir/manifest_path` and passed as
absolute paths to R scripts.

---

## Dispatch and XML Patching

### How dispatch modes work

Each named mode under `manifest.pecan_dispatch` carries a `host_xml` block —
the complete `<host>...</host>` XML to inject into `template.xml`. 

When `use_apptainer` is set to `true` and the mode also defines `host_xml_apptainer`, that
variant is used instead. The `@SIF@` string substituted with the SIF filename
relative to `run_dir` (since dispatched jobs execute there).

### `patch_dispatch()` (`magic-ensemble` lines 390–422)

Called immediately after step 00 in `prepare`. Steps:
1. Resolve `template_path` as `run_dir + manifest.paths.template_file`.
2. Select `host_xml` or `host_xml_apptainer` based on `use_apptainer` and
   manifest availability.
3. Substitute `@SIF@` via `sed`.
4. Call `tools/patch_xml.py` with `--block` to replace the entire `<host>` element.

### `tools/patch_xml.py`

Regex-based in-place XML patcher. In `--block` mode it replaces the entire
`<tag>...</tag>` element (tags included). Limitations: assumes tags have no
attributes; single substitution only (first match). The tool is intentionally
minimal and workflow-agnostic.

---

## Apptainer Integration

When `use_apptainer: true`:

1. `ensure_apptainer_available()` — tries `module load apptainer` if not on PATH.
2. `ensure_sif_present()` — looks for the SIF at `run_dir/<sif_name>`. If absent,
   pulls from `manifest.apptainer.remote.url/container.name:tag`. The SIF always
   lives in `run_dir` so it is co-located with the run for reproducibility.
3. R library pre-checks run inside the container (`check_r_libs_for_step_in_apptainer`).
4. Each R step is wrapped: `apptainer run --bind REPO_ROOT --bind run_dir`.

`run-ensembles` always executes `04_run_model.R` on the host (it submits jobs;
it does not run model code itself). When `use_apptainer: true`, the SIF must
be present because the patched `host_xml_apptainer` references it in the
`<binary>` or `<qsub>` command that PEcAn generates for each ensemble member.

---

## External Inputs Staging (`00_stage_external_inputs.sh`)

The script accepts `--repo-root`, `--config`, `--invocation-cwd`, and
optionally `--manifest`. Manifest defaults to
`<repo-root>/2a_grass/workflow_manifest.yaml`.

For each entry in `config.external_paths`:
1. Key must exist under `manifest.paths`; if not, the script exits with an error.
2. Source path is resolved: absolute as-is, relative paths prepended with
   `INVOCATION_CWD`.
3. Destination is `run_dir/$(basename manifest.paths.<key>)` — manifest-derived,
   not source-derived.
4. Parent directories are created if needed; file is copied with `cp -f`.

This staging runs before `patch_dispatch()`, so `template.xml` is guaranteed
to be present when the XML patching step fires.

---

## Adapting to a New Workflow

The CLI skeleton (`magic-ensemble`) and the staging/dispatch infrastructure are
designed to be reused. When adapting:

### Replace in the manifest

- `steps`: update script paths and input/output path keys for the new workflow
- `paths`: replace with the new workflow's internal file layout
- `params_from_pft`, `additional_params`: workflow-specific fixed values
- `s3`: update bucket, key prefixes, and filenames
- `pecan_dispatch`: keep as-is if PEcAn dispatch is reused; otherwise replace
- `apptainer`: update container name and tag

### Replace the step scripts

Each script under `steps` should accept its inputs as named CLI arguments (R
scripts via `optparse`; shell scripts via `--flag value`). The CLI passes all
paths as absolute values so scripts do not need to be CWD-aware.

### Keep in `magic-ensemble`

- Argument parsing, `get_val()`, path normalization
- `check_aws` (for any command that fetches from S3)
- `ensure_apptainer_available`, `ensure_sif_present`, `check_r_libs_for_step*`
- `run_script`, `run_shell_script`, `patch_dispatch`

### Update in `magic-ensemble`

- The argument mappings in `run_prepare()` (the `case "$i"` block) — these are
  the per-step CLI arguments passed to each R script and are workflow-specific.
- `usage()` — update command descriptions and examples.
- The manifest path constant (`MANIFEST=`) if the new workflow lives in a
  different subdirectory.

---

## Testing

_(Placeholder — expand on this.)_

Proposed tiers:
- **Unit (bats/shunit2):** `get_val()` fallback behavior, `patch_dispatch()` XML
  output, path normalization and `external_paths` destination derivation using
  fixture configs and manifests.
- **Integration:** End-to-end `prepare` against a minimal fixture that exercises
  the full step sequence without live R script execution (mock scripts that
  assert their arguments and touch their expected outputs).
