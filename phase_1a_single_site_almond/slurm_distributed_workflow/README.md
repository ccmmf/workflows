# Running PEcAn workflows on CARB with Slurm and Apptainer

## Table of contents
1. [Introduction](#introduction)
2. [Obtaining PEcAn resources](#obtain-resources)
2. [Head-node installation](#Head-node-installation)
2. [Distributed PEcAn Workflows](#distributed-pecan)
3. [Dependencies](#dependencies)

## Introduction <a name="introduction"></a>
This document is intended to help with the initial set-up and configuration needed to support execution of PEcAn workflows on a Slurm-backed HPC cluster.
The system described below is intended to minimize the amount of software which must be installed on the ‘login’ or ‘head’ nodes of the CARB cluster. 

This approach is intended to:
- Run PEcAn workflows at-scale via Slurm & Apptainer
- Depend directly on the containers in the PEcAn Dockerhub
- Minimize maintenance required on installed software on the CARB cluster

## Obtaining PEcAn Resources <a name="obtain-resources"></a>
The needed elements for this process are as follows:
1. The environment tarball for head-node installation
2. The git repository of workflows created for CARB
3. Data artifacts for workflows

These resources are obtained via git and the s3 protocol as follows.

The workflows are obtained by cloning the repository from github via:
```sh
git clone https://github.com/ccmmf/workflows.git
```

The environment tarball and data artifacts have been hosted by NCSA, and can be obtained via the S3 protocol from:
```s3.garage.ccmmf.ncsa.cloud```
(TODO: determine how we want to hand creds over to CARB folks)



## Head-Node installation: Conda & Conda Environment <a name="Head-node-installation"></a>
If you do not already have Conda installed, a good alternative for a local user install is miniconda. Install miniconda following [these instructions](https://www.anaconda.com/docs/getting-started/miniconda/install#linux)

The below commands assume you keep your conda environments in the standard location: ```{USER}/.conda/envs```

The pre-packaged headnode environment can be obtained from the S3 data host with this command:
```sh
rclone copy ccmmf:carb/data/env/PEcAn-head.tar.gz ./
```

If you have not used conda before, it is suggested you unpack this environment into the standard location:
```sh
mkdir ~/.conda
```
```sh
mkdir ~/.conda/envs
```
```sh
mkdir ~/.conda/envs/PEcAn-head
```
```sh
tar -xzf PEcAn-head.tar.gz -C ~/.conda/envs/PEcAn-head
```
```sh
source ~/.conda/envs/PEcAn-head/bin/activate
```
```sh
conda-unpack
```
At this point, the conda environment is unpacked, and the 'conda-unpack' command has adjusted the paths within the environment to match your local filesystem. You should be able to interrogate the conda environment's installation of R to confirm this:

```sh
Rscript -e '.libPaths()'
```
This should yield output that points to the R-library location within the unpacked conda environment.
```sh
[1] "/home/hdpriest/.conda/envs/PEcAn-head/lib/R/library"
# the above path will reflect local file system home and user specifics
```

In addition, you should be able to access the portions of the PEcAn software stack that are needed on the headnode of the cluster:
```sh
Rscript -e 'library("PEcAn.workflow")'
```
or
```sh
Rscript -e 'library("PEcAn.remote")'
```
You __will__ need to have this environment activated when executing work in a Slurm-scheduled manner, as the job submissions to the Slurm schedule are enabled via PEcAn methods.

Typically, this environment can be activated via:
```sh
conda activate PEcAn-head
```

## Distributed PEcAn Workflows <a name="distributed-pecan"></a>

Note that the below walkthrough assumes the needed environment configuration in [Head-node installation](#Head-node-installation) has been completed.

If you have not already, obtain the workflow git repository from ```https://github.com/ccmmf/workflows.git```

This walkthrough leverages the 'phase_1a' workflow from this git repository.

```sh
git clone https://github.com/ccmmf/workflows.git
```
```sh
Cloning into 'workflows'...
remote: Enumerating objects: 503, done.
remote: Counting objects: 100% (287/287), done.
remote: Compressing objects: 100% (166/166), done.
remote: Total 503 (delta 179), reused 194 (delta 120), pack-reused 216 (from 1)
Receiving objects: 100% (503/503), 249.92 KiB | 5.32 MiB/s, done.
Resolving deltas: 100% (272/272), done.
```
Ensure that the PEcAn head node environment is activated, typically via:
```sh
conda activate PEcAn-head
```

Then, change directory into the slurm-distributed workflow version of the phase 1a workflow:
```sh
# TODO
# this needs to be incorporated into git:
cd ./workflows/phase_1a_single_site_almond/slurm_distributed_workflow/
```

The input data for this workflow can be obtained from the NCSA S3 Garage location:
```sh
rclone copy ccmmf:carb/data/workflows/phase_1a/00_cccmmf_phase_1a_input_artifacts.tgz ./
```
validate that the download was successful:
```sh
md5sum 00_cccmmf_phase_1a_input_artifacts.tgz
```
```sh
a3822874c7dd78cbb2de1be2aca76be3  00_cccmmf_phase_1a_input_artifacts.tgz
```

Following download, unpack the data into the local directory:
```sh
tar -xf 00_cccmmf_phase_1a_input_artifacts.tgz
```
This unpacks into three directories with contents, pre-arranged for use with this workflow:
```sh
ls -lhart ./
```
```sh
total 1.3G
-rw-r-----.  1 hdpriest hdpriest  42M May 30 17:11 00_cccmmf_phase_1a_input_artifacts.tgz
-rwxr-x---.  1 hdpriest hdpriest 2.5K Jun 23 15:15 04a_run_model.R
-rwxr-x---.  1 hdpriest hdpriest 4.0K Jun 23 15:15 04b_run_model.R
-rw-r-----.  1 hdpriest hdpriest 8.8K Jun 23 15:15 slurm_distributed_single_site_almond.xml
lrwxrwxrwx.  1 hdpriest hdpriest   20 Jun 30 17:41 05_validation.Rmd -> ../05_validation.Rmd
drwxr-x---.  3 hdpriest hdpriest   23 Jun 30 17:41 pfts
drwxr-x---.  3 hdpriest hdpriest   38 Jun 30 17:41 data
drwxr-x---.  3 hdpriest hdpriest   23 Jun 30 17:42 IC_files
```

pfts directory:
```sh
ls -lhart pfts/temperate/
```
```sh
total 17M
-rw-r-----. 1 hdpriest hdpriest 17M May 31  2023 trait.mcmc.Rdata
-rw-r-----. 1 hdpriest hdpriest 854 May 31  2023 post.distns.Rdata
```

ERA5-precipitation:
```sh
ls -lhart data/ERA5_losthills_dailyrain/
```
```sh
total 62M
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.1.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.10.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.2.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.3.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.4.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.6.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.5.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.7.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.8.1999-01-01.2012-12-31.clim
-rw-r-----. 1 hdpriest hdpriest 6.2M Jan 23 13:17 ERA5.9.1999-01-01.2012-12-31.clim
```

IC Files:
```sh
ls -lhart IC_files/losthills/
```
```sh
-rw-r-----. 1 hdpriest hdpriest  884 Feb  4 00:11 IC_site_losthills_9.nc
-rw-r-----. 1 hdpriest hdpriest  884 Feb  4 00:11 IC_site_losthills_99.nc
-rw-r-----. 1 hdpriest hdpriest  884 Feb  4 00:11 IC_site_losthills_98.nc
-rw-r-----. 1 hdpriest hdpriest  884 Feb  4 00:11 IC_site_losthills_97.nc
-rw-r-----. 1 hdpriest hdpriest  884 Feb  4 00:11 IC_site_losthills_96.nc
-rw-r-----. 1 hdpriest hdpriest  884 Feb  4 00:11 IC_site_losthills_95.nc
#... 100 total .nc files
```

Load the needed software modules:
```sh
module load apptainer
```

Apptainers will be leveraged to execute code on each of the slurm-managed nodes. This enables the user to not need to download any of the model-specific PEcAn code. It also enables the execution of different versions of PEcAn models without the need to reinstall the PEcAn stack. By simply identifying and leveraging a different version of the PEcAn model docker container, an analysis can be run with a different version of the code.

Obtain the needed dockers for this workflow, via:
```sh
apptainer pull docker://pecan/model-sipnet-git:latest
```
With data in place, the config and scripts in place, the apptainer pulled, we are now ready to run the workflow.
This has two steps. The first is a direct run of a method to generate the needed runtime configurations based on sipnet:
```sh
sbatch -n1 --mem-per-cpu=1G --time=01:00:00 --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%j.log" apptainer run model-sipnet-git_latest.sif ./04a_run_model.R --settings=slurm_distributed_single_site_almond.xml
```
This is a pre-step to running the distributed workflow. This command runs the script ('04a_run_model.R') within the indicated apptainer. This is a required step, as each PEcAn model is responsible for creating its own run-steps. 

This command therefore generates the output directory, with various run directories contained therein. 

This command will need to be run as part of each new compute run of the workflow.

With the above first step complete, we can now run the main compute job of the workflow:
```sh
sbatch -n1 --mem-per-cpu=1G --time=01:00:00 --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%j.log" ./04b_run_model.R --settings=slurm_distributed_single_site_almond.xml
```

This submits a number of jobs to slurm, one job for each of the directories within the output/run directory.

## Dependencies
### CARB-HPC Head-node

#### Environment Modules
This guide and related files expect that the [Environment Modules](https://modules.sourceforge.net/) system is available on the CARB HPC cluster.

#### rclone
As written, this guide uses 'rclone' to move files between the remote NCSA S3 data host and the local CARB head-node. 

#### Conda
This guide and the files provided with it leverage Conda for environment management. [Miniconda](https://www.anaconda.com/docs/getting-started/miniconda/main) is an excellent alternative to a full Conda installation.

#### Slurm
This guide and provided files have been constructed with the intention of running distributed workflows via the Slurm job scheduling system. It is assumed that the user leveraging this workflow will have a working knowledge of Slurm, but no elevated permissions will be required for interacting with Slurm resources and commands.

#### Apptainer
This guide and related files are based on the [PEcAn Docker container stacks](https://hub.docker.com/u/pecan), and are instantiated in an HPC environment via [Apptainer](https://apptainer.org/). This enables changes made to the Docker images by the PEcan community to be directly available to CARB, while also ensuring that the containers generated are compatible with the HPC environment.


