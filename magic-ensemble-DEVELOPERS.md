# magic-ensemble Developer Guide

This document covers the internal design of `magic-ensemble` and the
workflow scripts: how the pieces fit together, where the boundaries are,
and what to change when adding a new example or adapting this CLI.

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

The manifest (`workflow/workflow_manifest.yaml`) is the source of truth for
everything that is fixed per workflow. The user config contains only the values
a user legitimately needs to vary between runs. External paths are the mechanism
for injecting user-owned files (e.g. a custom `template.xml`) without making
manifest paths user-overridable. As written, a user can only inject files that
are expected by the pipeline.

---

## Execution Graph

### `get-demo-data`

```
00_fetch_s3_and_prepare_run_dir.sh
  → creates run_dir
  → downloads and extracts S3 artifact into run_dir
```

### `prepare` / `prepare-example-*`

All `prepare` variants follow the same four-step sequence. The manifest
defines which scripts run at steps 1–3 per command; step 0 always uses
`workflow/00_stage_external_inputs.sh`.

```
workflow/00_stage_external_inputs.sh  (step 0, all prepare variants)
  → creates run_dir
  → copies external_paths files into run_dir (manifest-defined destinations)
  → [patch_xml_block() runs twice after this step]
      → patches <host> block: reads pecan_dispatch host_xml from manifest,
        substitutes @SIF@ if use_apptainer is set
      → patches <model> block: reads sipnet_model model_xml from manifest,
        selects model_xml_apptainer variant if use_apptainer is set
      → both use tools/patch_xml.py --block

[step 1]  01_ERA5_nc_to_clim.R
  reads:  run_dir/data_raw/ERA5_nc, run_dir/site_info.csv
  writes: run_dir/data/ERA5_SIPNET/

[step 2]  02_ic_build.R
  reads:  run_dir/site_info.csv, run_dir/data_raw/dwr_map/...,
          run_dir/data/IC_prep/, run_dir/pfts/,
          run_dir/data_raw/ca_biomassfiaald_*.tif
  writes: run_dir/IC_files/, run_dir/data/IC_prep/

[step 3]  03_xml_build.R
  reads:  run_dir/site_info.csv, run_dir/template.xml,
          run_dir/IC_files/, run_dir/data/ERA5_SIPNET/
  writes: run_dir/settings.xml
```

For `prepare`, steps 1–3 come from `workflow/`. For `prepare-example-2a`,
they come from `examples/2a_grass/`. For `prepare-example-1b`, from
`examples/1b_statewide_woody/`. The manifest's `steps` block for each
command defines which scripts are used.

### `run-ensembles`

```
workflow/04_run_model.R  (CWD = run_dir)
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

None of these are user-overridable. Adding a new example verb means adding a
`steps.<verb-name>` block to `workflow/workflow_manifest.yaml` pointing at the
appropriate example scripts, then registering the verb in the CLI (see below).
As the underlying R-scripts evolve, the manifest must be kept in-sync with any
i/o changes made in R-scripts.

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

### `patch_xml_block()` (`magic-ensemble`)

Generic XML block patcher called immediately after step 00 in `prepare`.

```
patch_xml_block <xml_tag> <plain_yq_path> <apptainer_yq_path>
```

Steps:
1. Resolve `template_path` as `run_dir + manifest.paths.template_file`.
2. If `use_apptainer=1` and `<apptainer_yq_path>` resolves to a non-null value
   in the manifest, use it; otherwise use `<plain_yq_path>`.
3. Substitute `@SIF@` via `sed` (no-op when `@SIF@` is absent from the block).
4. Call `tools/patch_xml.py` with `--block` to replace the entire element.

Called twice in `run_prepare()`: once for `<host>` (dispatch XML) and once for
`<model>` (SIPNET binary path). Adding a new patched block requires only one
more `patch_xml_block` call with the appropriate manifest yq paths.

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

The script accepts `--repo-root`, `--manifest`, `--config`, `--invocation-cwd`.
The CLI always passes `--manifest "$MANIFEST"` explicitly. The script's built-in
default (`<repo-root>/workflow/workflow_manifest.yaml`) is only a fallback for
standalone invocation.

For each entry in `config.external_paths`:
1. Key must exist under `manifest.paths`; if not, the script exits with an error.
2. Source path is resolved: absolute as-is, relative paths prepended with
   `INVOCATION_CWD`.
3. Destination is `run_dir/$(basename manifest.paths.<key>)` — manifest-derived,
   not source-derived.
4. Parent directories are created if needed; file is copied with `cp -f`.

This staging runs before `patch_xml_block()`, so `template.xml` is guaranteed
to be present when the XML patching step fires.

---

## Adding a New Example Verb

To wire up a new `prepare-example-*` command (e.g. for a future `3_rowcrop`
example):

### 1. Add a steps block to the manifest

In `workflow/workflow_manifest.yaml`, add:

```yaml
steps:
  prepare-example-3:
    - script: "workflow/00_stage_external_inputs.sh"
      r_libraries: []
      inputs: []
      outputs: []
    - script: "examples/3_rowcrop/01_ERA5_nc_to_clim.R"
      r_libraries: [future, furrr]
      ...
    - script: "examples/3_rowcrop/02_ic_build.R"
      r_libraries: [tidyverse]
      ...
    - script: "examples/3_rowcrop/03_xml_build.R"
      r_libraries: [PEcAn.settings]
      ...
```

### 2. Register the verb in `magic-ensemble`

Three locations:
- Add `prepare-example-3` to the recognized commands in the argument parser
  (`help|get-demo-data|prepare|...|run-ensembles`)
- Add it to the unknown-command guard
- Add a case in the main dispatch block: `prepare-example-3) run_prepare ;;`

### 3. Write an `example_user_config.yaml`

Place it at `examples/3_rowcrop/example_user_config.yaml`. Include
`external_paths` entries for any files in the example directory that need
to be staged into `run_dir` (typically `template_file` and `site_info_file`).

### 4. Update `usage()` and docs

Add the new command to `usage()` in `magic-ensemble`, and to the *Commands*
section of `magic-ensemble-README.md`.

---

## Testing

_(Placeholder — expand on this.)_

Proposed tiers:
- **Unit (bats/shunit2):** `get_val()` fallback behavior, `patch_xml_block()` XML
  output, path normalization and `external_paths` destination derivation using
  fixture configs and manifests.
- **Integration:** End-to-end `prepare` against a minimal fixture that exercises
  the full step sequence without live R script execution (mock scripts that
  assert their arguments and touch their expected outputs).
