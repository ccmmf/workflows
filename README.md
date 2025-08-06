# Workflow files for CCMMF deliverables

This repo contains demonstrations of modeling functionality for MAGiC,
each built to showcase a unit of functionality added for each phase of the
project.

Each directory is conceptually freestanding and is intended not to care
about paths outside itself, but to avoid redundancy there are two exceptions:

* Each demo directory contains a symbolic link to the root `data_raw` folder,
	because it is for files that have only one canonical version and are often
	large enough it's undesirable to leave many copies of them on disk.
	Update these links if needed to match your on-disk project layout.
* Some interactive workflow steps call for scripts in the root `tools` folder,
	because these do the same job everywhere and updates needed in one demo
	will be needed in the others too.
