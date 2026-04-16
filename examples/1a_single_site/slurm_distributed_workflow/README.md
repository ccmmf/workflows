---
output:
  pdf_document: default
  html_document: default
---
# Running PEcAn workflows on CARB with Slurm and Apptainer

## Table of contents
1. [Introduction](#introduction)
2. [Obtaining PEcAn resources](#obtainingresources)
2. [Head-node installation](#headnodeinstallation)
2. [Distributed PEcAn Workflows](#distributedpecan)
3. [Dependencies](#dependencies)

## Introduction <a name="introduction"></a>
This document is intended to help with the initial set-up and configuration needed to support execution of PEcAn workflows on a Slurm-backed HPC cluster.
The system described below is intended to minimize the amount of software which must be installed on the ‘login’ or ‘head’ nodes of the CARB cluster. 

This approach is intended to:

- Run PEcAn workflows at-scale via Slurm & Apptainer
- Depend directly on the containers in the PEcAn Dockerhub
- Minimize maintenance required on installed software on the CARB cluster


## Obtaining PEcAn Resources {#obtainingresources}
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
```sh
s3.garage.ccmmf.ncsa.cloud
```

Typically, you will be able to leverage the AWS CLI toolset to access these resources.

Once you enter the needed Access key and Secret Access Key, e.g.:
```sh
AWS Access Key ID [None]: GK8bb0d9c6b355c9a25b0b67fa
AWS Secret Access Key [None]: <-- secret key to be passed via other method -->
Default region name [None]: garage
Default output format [None]: 
```

You can then identify the CARB resources by identifying the correct endpoint via the 'endpoint-url' parameter. 
For example this command will recursively list the contents of the carb bucket:
```sh
aws s3 ls --recursive --endpoint-url https://s3.garage.ccmmf.ncsa.cloud s3://carb
```


## Head-Node installation: Conda & Conda Environment {#headnodeinstallation}
If you do not already have Conda installed, a good alternative for a local user install is miniconda. Install miniconda following [these instructions](https://www.anaconda.com/docs/getting-started/miniconda/install#linux)

The below commands assume you keep your conda environments in the standard location: ```{USER}/.conda/envs```

The pre-packaged headnode environment can be obtained from the S3 data host with this command:
```sh
aws s3 cp --endpoint-url https://s3.garage.ccmmf.ncsa.cloud \
  s3://carb/environments/PEcAn-head.tar.gz ./

```

If you have not used conda before, it is suggested you unpack this environment into the standard location:
```sh
mkdir -p ~/.conda/envs/PEcAn-head
tar -xzf PEcAn-head.tar.gz -C ~/.conda/envs/PEcAn-head
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

## Distributed PEcAn Workflows {#distributedpecan}

Note that the below walkthrough assumes the needed environment configuration in [Head-node installation](#headnodeinstallation) has been completed.

If you have not already, obtain the workflow git repository from ```https://github.com/ccmmf/workflows.git```

This walkthrough leverages the 'phase_1a' workflow from this git repository.

### Differences between distributed and base workflows

While both the base Phase 1A workflow and its distributed version accomplish the same goal, there are key differences in how the compute work is undertaken between the workflows. The distributed workflow (described below) is intended to enable scalability across an HPC of arbitrary size, leveraging the advantages of workflow containerization to protect against compute node & environment heterogeneity.

To accomplish this, the base workflow was modified by dividing step 4 into two separate scripts for file setup and model execution, and by editing the settings XML file as follows:

* `model$binary` is set to match the path to Sipnet as seen from inside the model container
* `host$qsub` is  the `sbatch` invocation needed for Slurm to run everything. It includes both any system-specific Slurm job configurations and the path to the correct container for model execution.
* `host$qsub.jobid` is the pattern to match a Slurm job ID in the system-specific submission confirmation message.
* `host$qstat` is the `squeue` invocation to check status of a submitted job (probably not system-specific)

All other workflow scripts work the same as in the base workflow and do not use any distributed steps.


#### Note regarding Slurm and Containers
While executing this workflow, and in constructing custom or altered workflows, it is important to keep in mind that using apptainers to launch slurm jobs is __not__ a supported use-case of apptainers. OCI Containers are used herein to encapsulate execution environments (i.e., workers), but interactions with slurm for job launching and monitoring must be done from non-containerized processes on head or login nodes.

The single-step model run from the Phase 1A workflow (1a_single_site/04_run_model.R) is split into a two-step process for the purposes of distribution.

The first step is executed via the script '04a_set_up_runs.R'. This step constructs the run and output directories, and populates run configs for each individual computational job. This single slurm-submitted process is executed from within a container providing the PEcAn and Sipnet runtimes, to ensure easy & reproducible execution. Notably, because submission of new jobs from containerized processes is not supported, this process cannot actually launch the model workflow itself.

Perforce, The second step is the actual execution of the model workflows, mediated by slurm and containerized by apptainers. Each individual job is distributed to a compute worker node, and invoked therein within a container.

### Distributed workflow

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
cd ./workflows/phase_1a_single_site_almond/slurm_distributed_workflow/
```

The input data for this workflow can be obtained from the NCSA S3 Garage location:
```sh
aws s3 cp --endpoint-url https://s3.garage.ccmmf.ncsa.cloud \ 
  s3://carb/data/workflows/phase_1a/00_cccmmf_phase_1a_input_artifacts.tgz ./
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
This unpacks into three directories with contents, pre-arranged for use with this workflow.

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
sbatch -n1 --mem-per-cpu=1G --time=01:00:00 \ 
  --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%j.log" \
  apptainer run model-sipnet-git_latest.sif ./04a_set_up_runs.R \ 
  --settings=slurm_distributed_single_site_almond.xml
```
This is a pre-step to running the distributed workflow. This command runs the script ('04a_set_up_runs.R') within the indicated apptainer. This is a required step, as each PEcAn model is responsible for creating its own run-steps. 

This command therefore generates the output directory, with various run directories contained therein. 

This command will need to be run as part of each new compute run of the workflow.

With the above first step complete, we can now run the main compute job of the workflow:
```sh
sbatch -n1 --mem-per-cpu=1G --time=01:00:00 \
  --output=pecan_workflow_runlog_"$(date +%Y%m%d%H%M%S)_%j.log" \
  ./04b_run_sipnet.R \
  --settings=output/pecan.CONFIGS.xml
```

This submits a number of jobs to slurm, one job for each of the directories within the output/run directory.

## Dependencies {#dependencies}
### CARB-HPC Head-node

#### Environment Modules

This guide and related files expect that the [Environment Modules](https://modules.sourceforge.net/) system is available on the CARB HPC cluster.

#### AWS S3 CLI

As written, this guide uses the AWS S3 CLI tools to move files between the remote NCSA S3 data host and the local CARB head-node. 

#### Conda

This guide and the files provided with it leverage Conda for environment management. [Miniconda](https://www.anaconda.com/docs/getting-started/miniconda/main) is an excellent alternative to a full Conda installation.

#### Slurm

This guide and provided files have been constructed with the intention of running distributed workflows via the Slurm job scheduling system. It is assumed that the user leveraging this workflow will have a working knowledge of Slurm, but no elevated permissions will be required for interacting with Slurm resources and commands.

#### Apptainer

This guide and related files are based on the [PEcAn Docker container stacks](https://hub.docker.com/u/pecan), and are instantiated in an HPC environment via [Apptainer](https://apptainer.org/). This enables changes made to the Docker images by the PEcan community to be directly available to CARB, while also ensuring that the containers generated are compatible with the HPC environment.


