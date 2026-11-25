# Build disposable pft folder layouts for find_posterior scenarios.
args <- commandArgs(TRUE); root <- args[1]
set.seed(42)
n <- 1000
mk_chain <- function(x) coda::mcmc.list(coda::mcmc(matrix(x, ncol = 1, dimnames = list(NULL, "beta.o"))))
# Paired draws: leaf, wood, fine root fractions from one Dirichlet draw, so
# leaf + wood + fineroot < 1 on every row (coarse root = remainder > 0).
g <- matrix(rgamma(n * 4, shape = c(6, 3, 5, 0.6)), ncol = 4, byrow = TRUE)
d <- g / rowSums(g)
trait.mcmc <- list(
  leafAllocation = mk_chain(d[, 1]),
  woodAllocation = mk_chain(d[, 2]),
  fineRootAllocation = mk_chain(d[, 3]),
  Amax = mk_chain(rnorm(n, 100, 10))
)
post.distns <- data.frame(
  distn = c("beta", "beta", "beta", "norm", "unif"),
  parama = c(6, 3, 5, 100, 0), paramb = c(8.6, 11.6, 9.6, 10, 1), n = NA,
  row.names = c("leafAllocation", "woodAllocation", "fineRootAllocation", "Amax", "SLA")
)
soil.mcmc <- list(soilRespQ10 = mk_chain(rnorm(n, 2, 0.1)))
soil.post <- data.frame(distn = "norm", parama = 2, paramb = 0.1, n = NA, row.names = "soilRespQ10")
save_tm <- function(x, f) { trait.mcmc <- x; save(trait.mcmc, file = f) }
save_pd <- function(x, f) { post.distns <- x; save(post.distns, file = f) }
mk <- function(layout, pft, files) {
  p <- file.path(root, layout, pft); dir.create(p, recursive = TRUE)
  for (f in files) {
    if (grepl("post.distns", f)) save_pd(if (pft == "soil") soil.post else post.distns, file.path(p, f))
    else if (f %in% c("README.txt", "old_mcmc.pda.corn.Rdata.bak")) writeLines("x", file.path(p, f))
    else save_tm(if (pft == "soil") soil.mcmc else trait.mcmc, file.path(p, f))
  }
}
# main: pda dir, case variant pda, post.distns only, trait.mcmc (soil)
mk("main", "corn", c("mcmc.pda.corn.Rdata", "post.distns.Rdata"))
mk("main", "rice", c("MCMC.PDA.rice.RData", "post.distns.Rdata"))
mk("main", "annual_crop", c("post.distns.Rdata"))
mk("main", "soil", c("trait.mcmc.Rdata", "post.distns.Rdata"))
# look-alikes that must NOT count as pda samples
mk("lookalike", "corn", c("old_mcmc.pda.corn.Rdata.bak", "post.distns.Rdata", "README.txt"))
# pre-change layout: trait.mcmc + post.distns, no pda (old v1.5 naming)
mk("old", "corn", c("trait.mcmc.Rdata", "post.distns.Rdata"))
mk("old", "soil", c("trait.mcmc.Rdata", "post.distns.Rdata"))
# renamed-to-pda inventory layout for the sampling check
mk("renamed", "corn", c("mcmc.pda.corn.Rdata", "post.distns.Rdata"))
mk("renamed", "soil", c("trait.mcmc.Rdata", "post.distns.Rdata"))
# guards
mk("copied", "corn", c("mcmc.pda.corn.Rdata", "trait.mcmc.Rdata", "post.distns.Rdata"))
mk("twopda", "corn", c("mcmc.pda.corn.Rdata", "mcmc.pda.corn_v2.Rdata", "post.distns.Rdata"))
mk("empty", "corn", c("README.txt"))
cat("leaf+wood+fineroot max (paired):", max(rowSums(d[, 1:3])), "\n")
