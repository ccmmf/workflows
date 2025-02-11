#!/bin/bash

set -e

module load r/4.4.0
module load udunits
module load gdal
module load jags
module load netcdf

# Create user library, at the path R expects, if it doesn't exist yet
Rscript -e 'dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE)'

# Install PEcAn and a _lot_ of dependencies (more than 300 of them)
# Expect at least an hour of compilation
# NB `ropensci` in repos list may be removable after pecan PR 3433 is merged
srun --cpus-per-task=4 --mem-per-cpu=1G --time="12:00:00" Rscript -e \
	'install.packages(
		c("PEcAn.all", "PEcAn.SIPNET"),
		repos = c(
			CRAN = "cloud.r-project.org",
			pecan = "pecanproject.r-universe.dev",
			ropensci = "ropensci.r-universe.dev"
		)
	)'
