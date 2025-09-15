# notes for targets support
You needed to install targets in the base images for the different environments

That new env needs to be provisioned to CARB

Rscript -e 'install.packages(c("targets", "tarchetypes", "uuid", "crew", "crew.cluster"), repos = c(CRAN = "cloud.r-project.org"))'


Rscript -e 'install.packages(c("crew.cluster"), repos = c(CRAN = "cloud.r-project.org"))'