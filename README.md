# Workflow files for CCMMF deliverables

This repo contains the `magic-ensemble` CLI and the scripts it orchestrates for
running SIPNET carbon flux ensemble analyses.

## Structure

```
workflows/
├── magic-ensemble               CLI entry point
├── workflow/                    Canonical, data-agnostic workflow scripts
│   ├── workflow_manifest.yaml   Fixed step definitions, paths, dispatch config
│   ├── 00_fetch_s3_and_prepare_run_dir.sh
│   ├── 00_stage_external_inputs.sh
│   ├── 01_ERA5_nc_to_clim.R
│   ├── 02_ic_build.R
│   ├── 03_xml_build.R
│   ├── 04_run_model.R
│   └── template.xml
├── examples/                    Example analyses (phase-specific data prep)
│   ├── 1a_single_site/
│   ├── 1b_statewide_woody/
│   ├── 2a_grass/
│   └── 3_rowcrop/
└── tools/                       Shared utility scripts
```

The `workflow/` directory holds the canonical implementation. The `examples/`
directories contain phase-specific preparation scripts (steps 01–03) and
their own `template.xml` and `site_info.csv`. Step 04 (`run_model`) is
shared — all workflows dispatch through `workflow/04_run_model.R`.

See `magic-ensemble-README.md` for usage and `magic-ensemble-DEVELOPERS.md`
for architecture details.
