# Data Provenance Digest — `workflows` repo

Scope: everything under `/project/60007/hpriest/CI/workflows` (the canonical `workflow/` pipeline, the `examples/1a,1b,2a,3` pipelines, `tools/`, `magic-ensemble` CLI, and `.github/ci` configs).

Classification rule used throughout: **INTERNAL** = produced as the output of another script in this repo (a step earlier in the same pipeline). **EXTERNAL** = originates outside this repo's own pipeline logic — a downloaded/queried dataset, a user-supplied raw file, a hardcoded scientific constant, another team's repo/server, or a vendored third-party tool.

---

## 1. The pipeline in one picture

```
 [EXTERNAL raw data + hardcoded constants]
            │
            ▼
01_ERA5_nc_to_clim.R   ──►  data/ERA5_SIPNET/*.clim  (met driver)         ─┐
02_ic_build.R          ──►  IC_files/*.nc  (initial conditions)          ─┤
02a_build_events.R /                                                     ─┤► 03_xml_build.R ──► settings.xml
tools/event_prep/*     ──►  data/events/events-<site>.in                 ─┘        │
                                                                                    ▼
                                                                        04_set_up_runs.R ──► pecan.CONFIGS.xml
                                                                                    │
                                                                                    ▼
                                                                        04/05_run_model.R (SIPNET binary)
                                                                                    │
                                                                                    ▼
                                                                 output/*.nc  ──► validate.R / validate.Rmd / compress_output.sh
```

Everything flowing left-to-right along this chain (met → IC → events → settings → run → validate) is **internal** — each script's output is the next script's input. The digest below is about what feeds in from the *left edge* of this diagram, i.e., what step 01/02/02a and friends actually consume before they ever touch repo-internal data.

Also internal but orthogonal to the science pipeline: the `magic-ensemble` CLI + `workflow/workflow_manifest.yaml` (declares path keys/steps) + `tools/patch_xml.py` (patches `template.xml` from manifest-declared blocks). These wire the pipeline together but don't originate data themselves.

---

## 2. EXTERNAL data artifacts — the handoff list

This is the list to hand to whoever will own "organizing the external data." Grouped by category, with what it feeds and how it currently arrives.

### A. Meteorology
| Artifact | Feeds | Current source / access |
|---|---|---|
| **ERA5 reanalysis netCDFs** (raw ensemble, hourly/3-hourly) | `01_ERA5_nc_to_clim.R` (all pipelines) | ECMWF/Copernicus Climate Data Store. Manual download today (`tools/ERA5_met_extract.R` notes the automated `PEcAn.data.atmosphere::download.ERA5.old()` path is currently broken); one copy lives at a hardcoded BU cluster path (`/projectnb/dietzelab/dongchen/anchorSites/ERA5`). Pre-extracted per-site copies are also distributed via the project's own S3 bucket (`s3://carb/data_raw/...`) so most example pipelines never touch raw ERA5 directly. |
| CA statewide half-degree grid roster (`ca_half_degree_grid.csv`) | `examples/3_rowcrop/01_ERA5_nc_to_clim.R` override | Companion file to the ERA5 extraction; origin/generation process not in repo. |

### B. Site rosters / design
| Artifact | Feeds | Current source / access |
|---|---|---|
| **`data/design_points.csv`** | `tools/build_site_info.R`, `tools/make_site_info_csv.R` | Hand-curated, checked into repo — but the underlying **site-selection process is external/undocumented** (why these lat/lons were chosen isn't captured anywhere in-repo). |
| **`site_info.csv` / `validation_site_info.csv`** | Nearly every downstream script | Technically *generated* by `tools/build_site_info.R` / `build_validation_siteinfo.R` / `make_site_info_csv.R`, so it's "internal build output" — but every ingredient going into that build (design points, DWR parcels, HSP data below) is external. Several examples simply ship a **committed copy** of this CSV (or a CI-specific one at `.github/ci/site_info_1b.csv` / `site_info_2a.csv`) rather than regenerating it. |

### C. Land / crop reference geospatial data
| Artifact | Feeds | Current source / access |
|---|---|---|
| **CA DWR "i15 Crop Mapping" geodatabases** (2018, 2020, 2023-provisional vintages) | `02_ic_build.R` (`field_shape_path`), `tools/read_mapped_planting_year.R`, `allom_compare.Rmd` | California Dept. of Water Resources public dataset (`data.cnra.ca.gov`, statewide crop mapping). Multiple vintages used inconsistently across examples. |
| **DWR/LandIQ parcel + crop-history data** (`parcels-consolidated.gpkg`, `crops_all_years.parq`, v4.1) | `tools/build_site_info.R` | Harmonized California parcel/crop-history product, versioned `v4.1`; not produced in-repo. |
| **CA state outline shapefile** (`data_raw/ca_outline_shp`) | `run_CA_grid_ERA5_nc_extraction.R`, `parameter_sensitivity.Rmd`, `irri_compare_20250319.Rmd` | Public GIS reference layer; exact source unspecified in any script. |

### D. Biomass / soil / vegetation remote-sensing products
| Artifact | Feeds | Current source / access |
|---|---|---|
| **LandTrendr aboveground-biomass GeoTIFFs** (median + stdv, 2016 and 2023 vintages) | `02_ic_build.R` (`landtrendr_raw_files`), several validation Rmds | Kennedy group / Oregon State product, normally via their `emapr` web portal (manual download); this project also mirrors copies in its own S3 bucket (`s3.median_tif`/`s3.stdv_tif` in the manifest). |
| **SoilGrids 250m soil organic carbon** | `02_ic_build.R` via `PEcAn.data.land::soilgrids_soilC_extract()` | Live API/DB query to ISRIC SoilGrids (external web service), result cached to a local CSV. |
| **Copernicus CDS soil moisture** (0.25° multi-satellite) | `02_ic_build.R` via `PEcAn.data.land::extract_SM_CDS()` | Live Copernicus Climate Data Store API call (requires a CDS API key); this project *also* ships a pre-fetched tarball of the same data via S3 (`soil_moisture_tgz`) — **the relationship between the live call and the tarball isn't reconciled in code** (flagged ambiguity, see §4). |
| **MODIS LAI** | `02_ic_build.R` via `PEcAn.data.remote::MODIS_LAI_prep()` | Live download from a MODIS/NASA remote-sensing product. |

### E. Model calibration ("PFT") data
| Artifact | Feeds | Current source / access |
|---|---|---|
| **PFT trait posterior distributions** (`post.distns.Rdata` / `trait.mcmc.Rdata` per PFT: `temperate.deciduous`, `grass`, `annual_crop`, `soil`) | `template.xml` in every pipeline, `02_ic_build.R` | Output of PEcAn's own Bayesian meta-analysis/calibration process (cites Fer et al. 2018 for woody, Dokoohaki et al. 2022 for grass) — a separate research pipeline entirely, not reproduced anywhere in this repo. Treated purely as a pre-supplied input artifact. |
| Hardcoded PFT trait values duplicated as literals (SLA, leaf carbon fraction, wood carbon fraction) | `02_ic_build.R`, `mixed_pfts.Rmd` | Same underlying calibration data, but re-typed as hardcoded numeric literals in multiple places instead of read from the `.Rdata` files — a duplication/consistency risk, not a new source. |

### F. Agronomic management / event data
| Artifact | Feeds | Current source / access |
|---|---|---|
| **Management event parquet files**: irrigation, phenology, planting, harvest, tillage (versioned `v1.0`/`v1.1` subfolders under `data_raw/management/`) | `tools/event_prep/01a-clean-irrigation.R`, `01b-clean-other-events.R` → `02-events-to-json-and-sipnet.R` → `examples/3_rowcrop/02a_build_events.R` | Produced by an external "monitoring pipeline" (per README), synced in via `aws s3 sync s3://carb/management/`. Version subpaths are hardcoded strings in the scripts — fragile. |
| **Prototype per-site irrigation schedules** (`irrigation_eventfile_<hash>.txt`, ~34 files) | `examples/1b_statewide_woody/site_irr_test/` | Described as derived from "daily remote-sensed water balance" — an external monitoring/remote-sensing framework, not generated by any script here. |

### G. Validation / literature reference data
| Artifact | Feeds | Current source / access |
|---|---|---|
| **CARB/CDFA Healthy Soils Program (HSP) cropland data** (`data_raw/private/HSP/Harmonized_{SiteMngmt,Data}_Croplands.csv`) | `tools/build_validation_siteinfo.R`, `examples/3_rowcrop/validate.R` | **Restricted/nonpublic** — explicitly consent-gated research data; repo comments say to contact a named CARB/CDFA contact before use. Flag this one specifically for the external-data owner — it has access-control implications, not just a "where do I get it" question. |
| **`examples/1a_single_site/data_raw/validation_data.csv`** | `05_validation.Rmd` | Manually compiled from published literature (Khalsa et al. 2020, Muhammad et al. 2015, Schellenberg et al. 2012, Falk et al. 2014) — a hand-curated literature digest, not an API/download. |
| **Hardcoded allometric equations** (almond allometry "shared by Tara Seeley"; CARB NWL Inventory per-species density/carbon coefficients) | Several validation Rmds (`05_validation.Rmd`, `allom_compare.Rmd`, `irri_compare_20250319.Rmd`) | Literal numeric constants baked into R scripts, sourced from named external documents/collaborators (one cites a missing `DEMETER_FutureModeling.xlsx` spreadsheet that isn't in the repo). |

### H. Model software & infrastructure
| Artifact | Feeds | Current source / access |
|---|---|---|
| **SIPNET model source/binary** | `04_run_model.R` / `05_run_model.R` (every pipeline) | Upstream `github.com/PecanProject/sipnet`. Vendored as a full copy at `tools/sipnet_src/` *and* separately live-cloned/compiled by `tools/install_sipnet.sh` — two parallel channels for the same external dependency. |
| **PEcAn R package ecosystem** (`PEcAn.all`, `PEcAn.SIPNET`, `PEcAn.data.atmosphere`, `PEcAn.data.land`, `PEcAn.data.remote`, etc.) | Nearly every R script | Installed via `tools/install_pecan.sh` from CRAN + `pecanproject.r-universe.dev`/`ropensci.r-universe.dev`. Not "data" per se, but several PEcAn package internals *are* reference data (e.g. `PEcAn.utils::standard_vars`, `PEcAn.data.land::ndti_to_sipnet_tillage()`'s embedded conversion formula) — external to this repo either way. |
| **Apptainer container image** (`docker://hdpriest0uiuc/sipnet-carb`) | `magic-ensemble` CLI (`use_apptainer: true` path) | External container registry (Docker Hub namespace). |
| **Project S3 bucket** (`s3://carb` @ `s3.garage.ccmmf.ncsa.cloud`) | `workflow/00_fetch_s3_and_prepare_run_dir.sh`, most examples' README setup steps | This is the central external staging point: it's where the pre-built `ensembles_data_artifact.tar.gz` (bundles `site_info.csv`, `pfts/`, `data/events.in`, etc.), the LandTrendr tifs, and the soil-moisture tarball all live. Worth treating as "one external source with many payloads" for organizing purposes. |
| `examples/1b_statewide_woody` prebuilt tarball (`cccmmf_phase_1b_input_artifacts.tgz`) | `examples/1b_statewide_woody/00_install.sh` | Distributed via a **Google Drive link** — a redundant, separate channel from the S3 bucket above for conceptually the same kind of bundle. |

### I. Hardcoded scientific/operational constants (not files, but still external knowledge)
Worth listing separately since these can't be "organized" the same way as a dataset, but they're still non-repo-derived and someone should own tracking their provenance/citations:
- ERA5 half-degree grid-cell arithmetic (duplicated in 3 scripts).
- `wood_carbon_fraction ~ Normal(0.48, 0.005)` — explicitly flagged in-code as an uncited estimate ("TODO update from a citeable source"), and inconsistently re-typed as `0.47` in some validation Rmds.
- Fixed irrigation schedule (~1512–1520 mm/yr, applied every 4 days April–October) in `tools/write_sipnet_event_file.R` — an explicit placeholder pending real sensed-irrigation data.
- SIPNET `<options>` model-run flags in `template.xml` (GDD/NITROGEN_CYCLE/ANAEROBIC/etc.) — modeling choices, not data, but fixed per-example.

---

## 3. INTERNAL data artifacts (produced within this repo's own pipeline)

These are the outputs of one script that become another script's input — nothing for the external-data owner to source, just listed here for completeness/contrast:

- `data/ERA5_SIPNET/*.clim` (or `ERA5_CA_SIPNET`) — met driver files, output of `01_ERA5_nc_to_clim.R`.
- `IC_files/<site>/IC_site_<site>_<n>.nc` — initial conditions, output of `02_ic_build.R`.
- `data_dir` intermediate caches (`soilgrids_soilC_data.csv`, `sm.csv`, `LAI.csv`/`LAI_bysite.csv`, `aboveground_biomass_landtrendr.csv`, `IC_means.csv`) — these are just local caches of the External-category-D API pulls, produced/reused by `02_ic_build.R`.
- `data/events/events-<site>.in`, `cycles-<site>.csv`, intermediate event JSON — output of the `tools/event_prep/*` chain / `02a_build_events.R`, ultimately from External-category-F parquet.
- `settings.xml` — output of `03_xml_build.R`.
- `pecan.CONFIGS.xml`, per-run job directories — output of `04_set_up_runs.R`.
- Model output netCDFs (`output/out/**/*.nc`), `STATUS` — output of `04_run_model.R`/`05_run_model.R`.
- Validation outputs (`SOC_model_fit.csv`, rendered HTML reports, plots) — output of `validate.R`/`validate.Rmd`/etc.
- Redistribution tarballs (`create_input_tarball.sh`, `compress_output.sh` outputs) — internal packaging of the above.
- `settings.xml`'s injected `<host>`/`<model>` blocks — patched in by `magic-ensemble` + `tools/patch_xml.py` from `workflow_manifest.yaml`, which is itself an internal config file (though it embeds external URLs: the S3 endpoint and the Apptainer registry).

---

## 4. Flagged gaps / inconsistencies (worth resolving, not just organizing)

1. **`data/events.in` provenance is undocumented.** Referenced in `template.xml`'s `<prerun>` hook, not declared in `workflow_manifest.yaml`'s `paths:` or any step's declared outputs. Almost certainly rides inside the S3 `ensembles_data_artifact.tar.gz`, but this is inferred, not confirmed anywhere in the code.
2. **Soil moisture has two possibly-redundant sources**: a live Copernicus CDS API call (`extract_SM_CDS`) vs. a pre-staged S3 tarball (`soil_moisture_tgz`). Code doesn't make explicit which one wins or whether they're expected to agree.
3. **`wood_carbon_fraction` is inconsistently hardcoded** as `0.48` in some places and `0.47` in others (different notebooks/scripts) for what's meant to be the same conversion constant.
4. **`workflow_manifest.yaml`'s `params_from_pft: "SLA,leafC"` omits `leafGrowth`**, which `02_ic_build.R`'s own default (`params_read_from_pft`) includes and depends on — possible drift between manifest and script.
5. **`tools/run_ERA5_met_extract.sh` references a script (`prep_getERA5_met.R`) that no longer exists** in the tree (renamed to `ERA5_met_extract.R`) — stale.
6. **Two parallel distribution channels for prebuilt input bundles**: the project's own S3 bucket vs. a Google Drive link used only by `examples/1b_statewide_woody`. Worth consolidating.
7. **HSP validation data is access-restricted** — this isn't just a "where do I download it" task; it needs a data-use/consent process, which the external-data owner should know going in.
8. **Multiple vintages of the same DWR crop-mapping geodatabase** (2018, 2020, 2023-provisional) are used inconsistently across examples/tools — worth deciding on a single canonical version per use case.

---

## 5. Suggested handoff framing

For the person taking over external-data organization, the natural buckets are:
1. **Meteorology** (ERA5) — access/automation is explicitly broken today; highest-value fix.
2. **Geospatial reference layers** (DWR crop maps, parcels, CA outline) — public, but versioned inconsistently.
3. **Remote-sensing/soil products** (LandTrendr, SoilGrids, CDS soil moisture, MODIS LAI) — live API dependencies with ad hoc S3 mirrors; good candidate for a single "external data cache" strategy.
4. **PFT calibration artifacts** — owned by a different (PEcAn/BETY) process; just need a stable, versioned drop-in location.
5. **Management/event data** — external monitoring pipeline output; hardcoded version strings (`v1.0`/`v1.1`) should probably become a real versioning contract.
6. **Restricted validation data (HSP)** — access/legal track, separate from the rest.
