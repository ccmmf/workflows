#!/bin/bash

#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=1G
#SBATCH --time="12:00:00"

# Installs the current development version of PEcAn,
# or updates a version already installed.

# Note: This installs PEcAn in the user's personal R library, which is
# desirable if your cluster has multiple PEcAn users who might each need
# to run a different version of PEcAn.
# If instead all users should share a common PEcAn version, install PEcAn
# to your site library instead; probably (not yet tested!) by running this
# script as admin with R_LIBS_USER unset and R_LIBS_SITE set appropriately.


set -e

module load r/4.4.0
module load udunits
module load gdal
module load jags
module load netcdf

# Create user R library, at the path R expects, if it doesn't exist yet
Rscript -e 'dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE)'

# Install PEcAn, compiling a _lot_ of dependencies (more than 300 of them)
# In my test this took about 2 hours for a first-time install using 4 cores.
Rscript -e \
	'if (requireNamespace("PEcAn.all", quietly=TRUE)) {
		# PEcAn is already installed; update all its installed packages
		pv <- PEcAn.all::pecan_version()
		pkgs <- pv$package[!is.na(pv$installed)]
		# ...and install PEcAn.SIPNET if not already present
		pkgs <- union(pkgs, "PEcAn.SIPNET")
	} else {
		# Install fresh; naming these two brings along the rest as deps
		pkgs <- c("PEcAn.all", "PEcAn.SIPNET")
	}
	install.packages(
		# NB tidyverse is not technically needed by PEcAn,
		# but used heavily for downstream analyses
		c(pkgs, "tidyverse"),
		repos = c(
			CRAN = "cloud.r-project.org",
			pecan = "pecanproject.r-universe.dev"
		),
		Ncpus = as.numeric(Sys.getenv("NSLOTS", 1)) - 1)
	)'
