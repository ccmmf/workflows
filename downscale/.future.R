# This file will load any time the future package is loaded.
# see ?future::plan for more details

# Auto-detect cores and leave one free
no_cores <- max(future::availableCores( ) - 1, 1)
future::plan(future::multicore, workers = no_cores)

PEcAn.logger::logger.info(paste("Using", no_cores, "cores for parallel processing"))

PEcAn.logger::logger.warn(paste("Using", no_cores, "cores for parallel processing"))