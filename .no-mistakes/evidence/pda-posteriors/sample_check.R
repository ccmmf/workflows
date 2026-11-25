# Feed a generated settings.xml to PEcAn develop's design generator (what
# workflow/04_set_up_runs.R calls) and count corn draws with coarse root <= 0.
.libPaths(c(Sys.getenv("TMPLIB"), .libPaths()))
suppressMessages(library(PEcAn.uncertainty))
cat("PEcAn.uncertainty from:", find.package("PEcAn.uncertainty"), "\n")
PEcAn.logger::logger.setLevel("WARN")
f <- commandArgs(TRUE)[1]
s <- PEcAn.settings::read.settings(f)
s1 <- s[[1]]
set.seed(1)
d <- generate_joint_ensemble_design(settings = s1, ensemble_size = 200)
cs <- d$samples$ensemble.samples$corn
coarse <- 1 - (cs$leafAllocation + cs$woodAllocation + cs$fineRootAllocation)
cat(sprintf("%s: corn posterior.files = %s\n", basename(f), s1$pfts[[which(sapply(s1$pfts, `[[`, "name") == "corn")]]$posterior.files))
cat(sprintf("  corn draws: %d; coarse root <= 0 in %d of %d\n", nrow(cs), sum(coarse <= 0), nrow(cs)))
so <- d$samples$ensemble.samples$soil; cat(sprintf("  soil draws: %d, any NA: %s\n", NROW(so), anyNA(so)))
