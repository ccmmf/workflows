#!/bin/bash

#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=1G
#SBATCH --time="12:00:00"

set -e

module load r/4.4.0
module load udunits
module load gdal
module load jags
module load netcdf

# Create user library, at the path R expects, if it doesn't exist yet
Rscript -e 'dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE)'

# Install PEcAn, compiling a _lot_ of dependencies (more than 300 of them)
# In my test this took about 2 hours using 4 cores.
# NB `tidyverse` not technically needed by PEcAn, but installing it here
#	for downstream analyses
Rscript -e \
	'install.packages(
		c("PEcAn.all", "PEcAn.SIPNET", "tidyverse"),
		repos = c(
			CRAN = "cloud.r-project.org",
			pecan = "pecanproject.r-universe.dev"
		)
	)'
