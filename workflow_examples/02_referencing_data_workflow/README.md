# Data Referencing Workflow Example

This example demonstrates how to **reference data from previous workflow runs** and **pull Apptainer containers** using the distributed workflows framework. This workflow builds upon the data preparation workflow and adds container management and PEcAn configuration preparation.

## Overview

This workflow showcases:
1. **External data referencing** using symbolic links to previous workflow runs
2. **Apptainer container management** with remote container pulling
3. **PEcAn configuration generation** using distributed execution
4. **Workflow dependency management** with proper sequencing

## Key Files

- `02_run_data_reference_workflow.R` - Main workflow script
- `02_pecan_workflow_config_example.xml` - Configuration file

## Workflow Script Breakdown

### Section 1: Workflow setup & settings parsing

```r
library(targets)
library(tarchetypes)
library(PEcAn.all)

get_workflow_args <- function() {
  option_list <- list(
    optparse::make_option(
      c("-s", "--settings"),
      default = NULL,
      type = "character",
      help = "Workflow & Pecan configuration XML",
    )
  )

  parser <- optparse::OptionParser(option_list = option_list)
  args <- optparse::parse_args(parser)

  return(args)
}

args = get_workflow_args()
settings <- PEcAn.settings::read.settings(args$settings)

#### run directory specification ####
# note: if this_run_directory exists already, and we specify the _targets script within it, targets will evaluate the pipeline already run
# if the pipeline has not changed, the pipeline will not run. This extends to the targeted functions, their arguments, and their arguments values. 
# thus, as long as the components of the pipeline run are kept in the functions, the data entities, and the arguments, we can have smart re-evaluation.

this_workflow_name = "workflow.reference.02"

#### Primary workflow settings parsing ####

## settings and params for this workflow
workflow_settings = settings$orchestration[[this_workflow_name]]
workflow_function_source = settings$orchestration$functions.source
source(workflow_function_source)

## overall run directory for common collection of workflow artifacts
workflow_run_directory = settings$orchestration$workflow.base.run.directory
dir_check = check_directory_exists(workflow_run_directory, stop_on_nonexistent=TRUE)
workflow_run_directory = normalizePath(workflow_run_directory)

run_identifier = workflow_settings$run.identifier
pecan_xml_path = workflow_settings$pecan.xml.path

data_source_run_identifier = workflow_settings$data.source.01.reference
```

**Purpose**: 

This set-up section brings in standard command line arguments, and extracts the orchestration settings for this workflow via the workflow name.

The content here binds into the XML configuration file. The workflow name is a particularly useful field, as it can be used to easily switch to a different configuration stanza, while keeping the remainder of the workflow set-up identical.

This section also identifies the base workflow run directory - this is a critical field, as subsequent data references look in this directory by default for data sourcing.

This workflow specifically extracts the `data.source.01.reference` field, which identifies the run ID of workflow 01 (data preparation). This reference allows this workflow to access the data artifacts produced by that prior workflow run.

The comment block early in this section documents the smart re-evaluation behavior of the targets framework, which will only re-run pipeline steps if inputs or code have changed.


---

### Section 2: Data Referencing Setup

```r
# TODO: input parameter validation and defense
#### Handle input parameters parsed from settings file ####
#### workflow prep ####
function_path = normalizePath(file.path(workflow_function_source))
pecan_xml_path = normalizePath(file.path(pecan_xml_path))

#### DATA REFERENCING ####
#### Workflow run base directory + data source ID = source of data ##
this_data_source_directory = file.path(workflow_run_directory, data_source_run_identifier)
dir_check = check_directory_exists(this_data_source_directory, stop_on_nonexistent=TRUE)
```

**Purpose**: Sets up the reference to external data from workflow 01.

The paths to the workflow functions and PEcAn XML are normalized to ensure absolute paths. Then, the data source directory is constructed by combining the base workflow run directory with the data source run identifier (from workflow 01).

The `check_directory_exists()` function validates that this directory exists, stopping execution if it does not. This ensures that the prerequisite workflow (01) has completed successfully before this workflow attempts to reference its data.

This is the key mechanism for referencing external data without copying - by constructing a path based on a run identifier, subsequent workflows can access data from prior workflow executions through symbolic links.


---

### Section 3: Pipeline Definition and Launch Setup

```r
#### THIS ANALYSIS RUN DIRECTORY SETUP ####
ret_obj <- workflow_run_directory_setup(run_identifier=run_identifier, workflow_run_directory=workflow_run_directory)
analysis_run_directory = ret_obj$run_dir
analysis_run_id = ret_obj$run_id

#### 
print(paste("Starting workflow run in directory:", analysis_run_directory))
setwd(analysis_run_directory)
tar_config_set(store = "./")
analysis_tar_script_path = file.path("./executed_pipeline.R")

#### Pipeline definition ####
tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)
  pecan_xml_path = "@PECANXML@"
  workflow_data_source = "@WORKFLOWDATASOURCE@"
  tar_source("@FUNCTIONPATH@")
  apptainer_url = "@APPTAINERURL"
  apptainer_name = "@APPTAINERNAME@"
  apptainer_tag = "@APPTAINERTAG@"
  apptainer_sif = "@APPTAINERSIF@"
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr")
  )
```

**Purpose**: Sets up the initial pipeline runtime environment.

Uses the `workflow_run_directory_setup()` helper function to create the analysis run directory and retrieve both the directory path and run ID. This provides a cleaner interface for directory management.

Changes working directory to the analysis run directory, configures the targets store, and defines the path for the generated pipeline script file.

The tar_script block sets up the pipeline definition with placeholder values (marked with `@...@`) that will be replaced with actual configuration values in a later step. These placeholders are necessary because tar_make executes the script in a separate process without access to the current R environment's variables.

The Apptainer container configuration parameters (URL, name, tag, and SIF filename) are all set as placeholders here. The required R packages for PEcAn workflows are specified, and necessary PEcAn modules are imported.


---

### Section 4: Pipeline Targets Definitions

```r
  list(
    # Config XML and source data handling
    # obviously, if at any time we need to alter the content of the reference data, we're going to need to do more than link to it.
    # doesn't copy anything; also doesn't check content - if the content of the source is changed, this is unaware.
    tar_target(reference_IC_directory, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="IC_files", localized_name="IC_files")),
    tar_target(reference_data_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="data", localized_name="data")),
    tar_target(reference_pft_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="pfts", localized_name="pfts")),
```

**Purpose**: Creates symbolic links to data from workflow 01 (data preparation).

These three targets create symbolic links to data from the data preparation workflow. The system looks in the workflow_data_source directory (which is generated as a combination of the base workflow directory and the run identifier of workflow 01).

From within that directory, each of the three objects are identified by their 'external_name' within that directory. They are then linked based on the 'localized_name' provided. The 'localized_name' is what the workflow targets, when run, would be able to access.

The comment block emphasizes an important limitation: these are symbolic links, not copies. If the content of the source data changes after the link is created, this workflow will not detect those changes. For scenarios where data integrity checking is required, a different approach (such as copying and checksumming) would be needed.

```r
    # pull down the apptainer from remote
    # we could do this in the prior step. 
    # doing it here in this example allows the next step to reference two different data sources    
    tar_target(apptainer_reference, pull_apptainer_container(apptainer_url_base=apptainer_url, apptainer_image_name=apptainer_name, apptainer_tag=apptainer_tag, apptainer_disk_sif=apptainer_sif)),
```

This target downloads the Apptainer container from a remote registry (e.g., Docker Hub) and saves it as a `.sif` file in the current workflow run directory. The comment notes that this could be done in the prior workflow step, but doing it here allows workflow 03 to reference both the data (from workflow 01) and the container (from workflow 02) separately.

Downloading containers as workflow artifacts enables reproducible execution environments and version control of container images. By making containers workflow artifacts, we can track which container version was used for each analysis run.

```r
    # Prep run directory & check for continue
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),

    # check for continue; then write configs
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)),
```

Prepares PEcAn settings by reading the XML configuration file and creating the PEcAn run directory. The continue directive check determines whether the workflow should attempt to continue from a previous run (currently set to FALSE).

```r
    # now we get into the abstract functions. 
    # create the abstraction of pecan write configs.
    tar_target(
        pecan_write_configs_function,
        targets_function_abstraction(function_name = "pecan_write_configs")
    ),
    # create the abstraction of the pecan write configs arguments
    tar_target(
      pecan_write_configs_arguments,
      targets_argument_abstraction(argument_object = list(pecan_settings=pecan_settings_prepared, xml_file=pecan_xml_file))
    ),
```

These two steps are critical to understand the process by which distributed computing is supported in this framework. 

In order to ease the process of executing arbitrary code, including calls of PEcAn functions, both the function and the arguments to that function are abstracted via the above steps. This causes the Targets framework to register the function, and the arguments as separate compressed R objects on-disk within the workflow run directory.

This allows the submission of a simple functional call via SBatch to Slurm. This call creates a new R process, using the workflow run directory as its working directory. It simply loads the function from the target store's compressed R object, loads the arguments as well, and calls the function on the arguments.

The two target steps above are the required preparation steps to enable this process. The sections below actually submit the function call to sbatch, and then monitor the process on the cluster.

```r
    # run the abstracted function on the abstracted arguments via slurm
    tar_target(
      pecan_settings_job_submission, 
      targets_abstract_sbatch_exec(
        pecan_settings=pecan_settings,
        function_artifact="pecan_write_configs_function", 
        args_artifact="pecan_write_configs_arguments", 
        task_id=uuid::UUIDgenerate(), 
        apptainer=apptainer_reference, 
        dependencies=c(pecan_continue, apptainer_reference)
      )
    ),
    # block and wait until dist. job is done
    tar_target(
      settings_job_outcome,
      pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_settings_job_submission)
    )
```

These two target steps submit the function call which is abstracted in the previous two steps. It is important to note that the function artifact and the argument artifact are passed as __string__ names, not variable names.

The apptainer reference provides the apptainer information that will encapsulate the R function call on the Slurm worker node. The 'task_id' variable provides the unique identifier for the job submission to ensure non-collision with existing files or directories.

The final tar_target monitors the job submission and blocks until it is complete. This should be used as-needed, as in some cases, it is important to finish a distributed compute process before moving on with the rest of an analysis pipeline.


---

### Section 5: Script Post-Processing and Execution

```r
  )
}, ask = FALSE, script = analysis_tar_script_path)

script_content <- readLines(analysis_tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", function_path, script_content)
script_content <- gsub("@PECANXML@", pecan_xml_path, script_content)
script_content <- gsub("@WORKFLOWDATASOURCE@", this_data_source_directory, script_content)
script_content <- gsub("@APPTAINERURL", workflow_settings$apptainer$remote.url, script_content)
script_content <- gsub("@APPTAINERNAME@", workflow_settings$apptainer$container.name, script_content)
script_content <- gsub("@APPTAINERTAG@", workflow_settings$apptainer$tag, script_content)
script_content <- gsub("@APPTAINERSIF@", workflow_settings$apptainer$sif, script_content)

writeLines(script_content, analysis_tar_script_path)

tar_make(script = analysis_tar_script_path)
```

**Purpose**: 
- Replaces all placeholder values with actual paths and values
- Writes the final pipeline script
- Executes the workflow using the targets framework

The comment block explains why the placeholder replacement approach is necessary: tar_make executes in a separate process without access to the current R environment's variables. By using string replacement on the generated script, we can inject the actual configuration values before execution.

Note that the Apptainer configuration values are accessed from `workflow_settings$apptainer` rather than individual variables, since they were not extracted into separate variables earlier in the script.

The final call to `tar_make()` triggers the execution of the complete workflow pipeline, which will reference data from workflow 01, download the Apptainer container, generate PEcAn configurations via distributed execution, and monitor the distributed job.


## Key Concepts Demonstrated

### 1. External Data Referencing
Workflows can reference data from previous runs without copying, using symbolic links that provide:
- Disk space efficiency
- Data consistency across workflows
- Clear dependency tracking

### 2. Container Management
Downloading containers as workflow artifacts enables:
- Reproducible execution environments
- Version control of container images
- Efficient reuse across multiple workflow runs

### 3. Distributed Execution Abstraction
The function abstraction pattern allows:
- Remote execution without code duplication
- Flexible job scheduling
- Proper dependency management in distributed environments

### 4. Workflow Composition
This workflow demonstrates how to compose multiple workflows:
- Data preparation (workflow 01)
- Container management and configuration (workflow 02)
- Actual analysis (workflow 03 - see next example)

### 5. Helper Function Integration
The use of `workflow_run_directory_setup()` demonstrates:
- Code reusability
- Cleaner interfaces
- Encapsulation of common patterns

## Workflow Sequence

This workflow sits in the middle of the sequence:

```
Workflow 01: Data Preparation
    ↓ (provides data artifacts)
Workflow 02: Container Setup & Configuration (This workflow)
    ↓ (uses data from 01)
Workflow 03: Model Execution & Analysis
```

## Usage

```bash
Rscript 02_run_data_reference_workflow.R --settings 02_pecan_workflow_config_example.xml
```

## Dependencies

- Workflow 01 (data preparation) must complete first
- Access to remote container registry (e.g., Docker Hub)
- SLURM cluster for distributed execution
- Apptainer installed and available

## Output

This workflow produces:
- Symbolic links to data from workflow 01
- Downloaded Apptainer container (.sif file)
- PEcAn configuration files generated via distributed execution
- Complete workflow execution history in targets store

## Next Steps

After running this workflow successfully:
1. Note the run identifier for use in workflow 03
2. Verify the symbolic links to workflow 01 data are functional
3. Confirm the Apptainer container download completed
4. Check PEcAn configuration files were generated
5. Use this workflow's output as input to workflow 03 (model execution)
