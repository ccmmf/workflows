# Demo artifact comparison: example 3 (row crop) vs. canonical/1b/2a

Comparison of the S3-sourced demo data bundles for row crop
(`ERA5_CA_nc_2016_2024.tgz`, `magic_example3_input_data_20260711.tgz`,
`s3://carb/management/`) against the bundles used by canonical/1b/2a
(`ensembles_data_artifact.tar.gz`, `ca_biomassfiaald_2016_{median,stdv}.tif`,
`moisture_20160101_20160110.tgz`). All sourced from the same `carb` bucket.

MD5 comparisons were run against actual extracted file contents, not just
filenames — see the MD5 column for what was actually verified.

| Artifact | ex3 (row crop) placement | other examples (canonical/1b/2a) placement | MD5 comparison | Recommendations |
|---|---|---|---|---|
| ERA5 climate netCDFs (~2,150 grid-cell × ensemble dirs, 19,350 files) | `ERA5_CA_nc/ERA5_<gridcell>_<ens>/*.nc` — from `ERA5_CA_nc_2016_2024.tgz` | `data_raw/ERA5_nc/ERA5_<gridcell>_<ens>/*.nc` — from `ensembles_data_artifact.tar.gz` | md5 identical | standardize to example 3 |
| Soil moisture netCDFs (10 daily files) | `data/IC_prep/soil_moisture/*.nc` — bundled inline in `magic_example3_input_data_20260711.tgz` | `data/IC_prep/soil_moisture/*.nc` — separate fetch, `moisture_20160101_20160110.tgz` | md5 identical (all 10 files) | standardize to example 3 |
| PFT posterior — `temperate.deciduous/post.distns.Rdata` | `data_raw/pfts/temperate.deciduous/post.distns.Rdata` | `pfts/temperate.deciduous/post.distns.Rdata` | md5 identical | standardize to example 3 |
| ERA5 grid reference (`ca_half_degree_grid.csv`) | `ERA5_CA_nc/ca_half_degree_grid.csv` | `data_raw/ERA5_nc/ca_half_degree_grid.csv` | Only difference is the header: column 3 is named `"id"` (ex3) vs `"grid_id"` (other) — all data rows identical | standardize to example 3? |
| IC_prep intermediates (`IC_means.csv`, `LAI.csv`, `LAI_bysite.csv`, `sm.csv`, `soilgrids_soilC_data.csv`, `aboveground_biomass_landtrendr.csv`) | `data/IC_prep/*` — from `magic_example3_input_data_20260711.tgz` | `data/IC_prep/*` — from `ensembles_data_artifact.tar.gz` | All 6 files different by MD5. Not a duplicate. | group in directories below IC_prep |
| PFT posterior — `grass/post.distns.Rdata` | `data_raw/pfts/grass/post.distns.Rdata` | `pfts/grass/post.distns.Rdata` | **Different by MD5** (same size, 4.0K, different content) | ? |
| `site_info.csv` | top-level — from `magic_example3_input_data_20260711.tgz` | top-level — from `ensembles_data_artifact.tar.gz` | Different content, different format. | ? |
| PFT posterior — `annual_crop/post.distns.Rdata` | `data_raw/pfts/annual_crop/post.distns.Rdata` | *absent* | n/a — no counterpart to compare | combine? |
| PFT trait MCMC (`trait.mcmc.Rdata`) | *absent* | `pfts/{grass,temperate.deciduous}/trait.mcmc.Rdata` — from `ensembles_data_artifact.tar.gz` | n/a — no counterpart to compare | combine? |
| LandTrendr biomass rasters (median/stdv) | *absent* | top-level standalone files — separate fetch, `ca_biomassfiaald_2016_{median,stdv}.tif` | n/a — no counterpart to compare | combine? |
| Static SIPNET events file (`events.in`) | *absent* | `data/events.in` — from `ensembles_data_artifact.tar.gz` | n/a — no counterpart to compare | combine? |
| Management/event source data (parquet, by type/version) | `management/{crops,harvest,irrigation,phenology,planting,tillage}/v*` — separate `aws s3 sync s3://carb/management/` | *absent* | n/a — no counterpart to compare | combine? |

## Summary

- **Real, wholesale duplication confirmed**: the entire ERA5 climate driver dataset (19,350 files) is shipped twice, byte-identical, under two different directory-naming schemes — plus its grid-reference CSV, which matches on all data rows and differs only in a header column name (`id` vs `grid_id`). This is pure waste and a clean target for consolidation.
- **Mixed result on PFT posteriors**: `temperate.deciduous` is duplicated exactly; `grass` is not — same name, different content. Worth checking with whoever maintains PFT posteriors before assuming either is stale.
- **IC_prep outputs are not duplicates** despite identical filenames/schema — they're independently computed per-site outputs for different (though similarly-sized) site sets, keyed by different ID conventions (numeric field/parcel ID vs. hex site-id hash) between the two example groupings.
