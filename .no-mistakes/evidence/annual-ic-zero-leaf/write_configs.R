#!/usr/bin/env Rscript
# Feeds IC member 1 of every site (base and fixed builds) through
# PEcAn.SIPNET::write.config.SIPNET for a 2016-01-01 start and reports the
# laiInit / plantWoodInit / soilWFracInit it writes into sipnet.param.
#
# usage: Rscript write_configs.R <scratch_dir> <out_csv>

args <- commandArgs(trailingOnly = TRUE)
root <- args[[1]]

# Trait sets per site PFT. Annual PFTs get fracLeafFall = 0 like the real
# annual_crop PFT, which is exactly why write.config.SIPNET never zeroes
# their laiInit. The perennial gets fracLeafFall 0.3 so write.config.SIPNET
# also keeps its laiInit on Jan 1 and the IC LAI is visible end to end.
traits <- list(
  annual          = list(SLA = 20, leafC = 45, leafGrowth = 0, fracLeafFall = 0),
  mixed           = list(SLA = 20, leafC = 45, leafGrowth = 0, fracLeafFall = 0),
  nonveg          = list(leafGrowth = 50, fracLeafFall = 0),
  perennial       = list(SLA = 15, leafC = 48, leafGrowth = 126, fracLeafFall = 0.3),
  perennial_nolai = list(SLA = 15, leafC = 48, leafGrowth = 126, fracLeafFall = 0.3)
)

res <- list()
for (version in c("base", "fixed")) {
  for (site in names(traits)) {
    rundir <- file.path(root, "configs", version, "run")
    outdir <- file.path(root, "configs", version, "out")
    run.id <- site
    dir.create(file.path(rundir, run.id), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(outdir, run.id), recursive = TRUE, showWarnings = FALSE)
    ic_path <- file.path(root, version, "IC_files", site, paste0("IC_site_", site, "_1.nc"))
    settings <- list(
      rundir = rundir, modeloutdir = outdir,
      host = list(name = "localhost"),
      model = list(binary = "sipnet", revision = "git"),
      run = list(
        site = list(lat = 38, lon = -121),
        start.date = "2016-01-01", end.date = "2016-12-31",
        inputs = list(
          met = list(path = "unused.clim"),
          poolinitcond = list(path = ic_path)
        )
      )
    )
    PEcAn.SIPNET::write.config.SIPNET(
      defaults = list(list(constants = NULL)),
      trait.values = list(pft = traits[[site]]),
      settings = settings,
      run.id = run.id
    )
    p <- utils::read.table(file.path(rundir, run.id, "sipnet.param"))
    val <- function(name) p[p[, 1] == name, 2]
    res[[length(res) + 1]] <- data.frame(
      version = version, site = site, member = 1,
      laiInit = val("laiInit"),
      plantWoodInit = val("plantWoodInit"),
      soilWFracInit = val("soilWFracInit"),
      fracLeafFall = val("fracLeafFall"),
      sipnet_param = file.path(rundir, run.id, "sipnet.param")
    )
  }
}
res <- do.call(rbind, res)
res <- res[order(res$site, res$version), ]
write.csv(res, args[[2]], row.names = FALSE)
cat("\n== sipnet.param values written by PEcAn.SIPNET::write.config.SIPNET (start 2016-01-01, IC member 1) ==\n")
options(width = 200)
print(res[, c("version", "site", "member", "laiInit", "plantWoodInit", "soilWFracInit", "fracLeafFall")], row.names = FALSE)
