# Distributed Workflow Example

This example demonstrates **complete PEcAn model execution with distributed computing** using the distributed workflows framework. This is the most complex workflow, pulling together data referencing, container management, and distributed PEcAn ecosystem modeling.

## Overview

This workflow showcases:
1. **Complete PEcAn ecosystem model workflow** execution
2. **Distributed computing** via SLURM with Apptainer containers
3. **Multi-stage PEcAn analysis** including ensemble runs and sensitivity analysis
4. **Workflow composition** building upon data preparation and container setup
5. **Result aggregation** and workflow completion handling

## Key Files

- `03_run_distributed_workflow.R` - Main workflow script
- `03_pecan_workflow_config_example.xml` - Configuration file

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

this_workflow_name = "workflow.analysis.03"

## settings and params for this workflow
workflow_settings = settings$orchestration[[this_workflow_name]]
workflow_function_source = settings$orchestration$functions.source
source(workflow_function_source)
function_path = normalizePath(file.path(workflow_function_source))

#### Primary workflow settings parsing ####
## overall run directory for common collection of workflow artifacts
workflow_run_directory = settings$orchestration$workflow.base.run.directory
dir_check = check_directory_exists(workflow_run_directory, stop_on_nonexistent=TRUE)
workflow_run_directory = normalizePath(workflow_run_directory)

run_identifier = workflow_settings$run.identifier
pecan_xml_path = normalizePath(file.path(workflow_settings$pecan.xml.path))
```

**Purpose**: 

This set-up section brings in standard command line arguments, and extracts the orchestration settings for this workflow via the workflow name.

The content here binds into the XML configuration file. The workflow name is a particularly useful field, as it can be used to easily switch to a different configuration stanza, while keeping the remainder of the workflow set-up identical.

This section also identifies the base workflow run directory - this is a critical field, as subsequent data references look in this directory by default for data sourcing.

This section identifies the PEcAn XML file which will be used as part of any PEcAn invocations. This __can__ be the same as the orchestration XML, and in these examples, it is. However, these can be separate XMLs - this is intended to enable swapping between PEcAn XMLs for the purposes of comparison.


---

### Section 2: Data Referencing Setup

```r
#### Data Referencing ####
## Workflow run base directory + data source ID = source of data ##
data_source_run_identifier = workflow_settings$data.source.01.reference
this_data_source_directory = normalizePath(file.path(workflow_run_directory, data_source_run_identifier))
dir_check = check_directory_exists(this_data_source_directory, stop_on_nonexistent=TRUE)

## apptainer is referenced from a different workflow run id ##
apptainer_source_run_identifier = workflow_settings$apptainer.source.reference
apptainer_source_dir = normalizePath(file.path(workflow_run_directory, apptainer_source_run_identifier))
dir_check = check_directory_exists(apptainer_source_dir, stop_on_nonexistent=TRUE)
apptainer_sif = workflow_settings$apptainer$sif
```

**Purpose**: As an expansion of example #02, sets up references to external workflow artifacts

- Data source: References data from workflow 01 (data preparation)
- Apptainer source: References container from workflow 02 (container setup)

In particular note the way in which we are now referencing objects from two different prior workflow runs. We can extend this concept to an arbitrary number of such prior runs or external directories. It is important to pay careful attention to the disposition of data which is incorporated into workflows as references from prior runs, as this allows the effective separation of concerns between data handling and logistics, and data analysis and summary.


---

### Section 3: Pipeline Definition and Launch Setup

```r
#### Pipeline definition and launch ####
print(paste("Starting workflow run in directory:", analysis_run_directory))
setwd(analysis_run_directory)
tar_config_set(store = "./")
analysis_tar_script_path = file.path("./executed_pipeline.R")

tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)
  # prep parameter receivers
  pecan_xml_path = "@PECANXML@"
  workflow_data_source = "@WORKFLOWDATASOURCE@"
  tar_source("@FUNCTIONPATH@")
  apptainer_source_directory = "@APPTAINERSOURCE@"
  apptainer_sif = "@APPTAINERSIF@"

  # tar pipeline options and config
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr")
  )
```

**Purpose**: Sets up the initial pipeline runtime environment.

- Defines the pipeline execution directory, changes the working directory, and sets the path for the target store.
- Imports libraries needed
- sets up the placeholder variables which will be populated with variables. See below for the actual method of replacing these placeholders
 with actual values. 
- Sets up required R packages for PEcAn workflows - it is important to note that these libraries will **not be imported into methods called on slurm-managed nodes**. The user will have to import those packages within the function which is abstracted.

---

### Section 4: Pipeline Targets Definitions

#### External Data Referencing

```r
  list(
    # Config XML and source data handling
    # obviously, if at any time we need to alter the content of the reference data, we're going to need to do more than link to it.
    # doesn't copy anything; also doesn't check content - if the content of the source is changed, this is unaware.
    tar_target(reference_IC_directory, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="IC_files", localized_name="IC_files")),
    tar_target(reference_data_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="data", localized_name="data")),
    tar_target(reference_pft_entity, reference_external_data_entity(external_workflow_directory=workflow_data_source, external_name="pfts", localized_name="pfts")),
```

Each of these three targets creates a symbolic link to data from the data preparation workflow (workflow 01). 

Data referencing within this framework begins by identifying the source directory (```workflow_data_source```), and then the specific on-disk name of the resource being referenced (e.g., ```IC_files```). In this case, these are directories containing input data for PEcAn. In order to facilitate referencing objects which share a name (e.g., the generic external name of ```data```), each object may be labeled with a different localized name for the resource. 

From within that directory, each of the three objects are identified by their 'external name', within that directory. They are then linked to, based on the 'localized_name' provided. The 'localized_name' is what the workflow targets, when run, would be able to access.

#### Apptainer Image Referencing

```r
    # In this case, we're not pulling the apptainer - we are referencing it from a prior run
    # this means you can use the data-prep runs to iterate the apptainer version (when needed)
    # and use analysis runs to leverage the apptainer (but not update it)
    tar_target(
      apptainer_reference, 
      reference_external_data_entity(
        external_workflow_directory=apptainer_source_directory, 
        external_name=apptainer_sif, 
        localized_name=apptainer_sif
      )
    ),
```

This target uses a similar approach to locate the apptainer which was downloaded in step 02. The apptainer sif exists in the workflow directory from step 02, and this exposes it to the subsequent target steps which depend on the presence of an apptainer.

It is also important to note that the apptainer sif name is referenced within the PEcAn XML, and it is important that the localized name here matches that value in the PEcAn XML. In the future, this reference will be parameterized to match this apptainer SIF.

Referencing the apptainer in this way has two major benefits. First, it does not re-download the apptainer for each subsequent run of this workflow step. Apptainer sifs are typically fairly large on-disk, and over time this represents major savings of storage foot print.

Second, keeping the apptainer image in a seperate workflow directory means that it will not be re-pulled every time this analysis is run. It would is ideal to run multiple analyses under identical code-states such that their outcomes can be directly compared. When it is necessary, the apptainer workflow can be run under a new run identifier, and then the differences between apptainer version can also be directly compared.

#### PEcAn Configuration Loading

```r
    # Prep run directory & check for continue
    tar_target(pecan_xml_file, pecan_xml_path, format = "file"),
    tar_target(pecan_settings, PEcAn.settings::read.settings(pecan_xml_file)),
    tar_target(pecan_settings_prepared, prepare_pecan_run_directory(pecan_settings=pecan_settings)),

    # check for continue; then write configs
    tar_target(pecan_continue, check_pecan_continue_directive(pecan_settings=pecan_settings_prepared, continue=FALSE)),
```

Identifies and prepares the PEcAn settings and run directory for subsequent steps.

#### Function Abstraction in preparation for Slurm submission

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

In order to ease the process of executing arbitrary code, including calls of PEcAn functions, both the function and the arguments to that function are both abstracted via the above steps. This causes the Targets framework to register the function, and the arguments as separate compressed R objects on-disk within the workflow run directory. 

This allows the submission of a simple functional call via SBatch to Slurm. This call creates a new R process, using the workflow run directory as its working directory. It simply loads the function from the target store's compressed R object, loads the arguments as well, and calls the function on the arguments. 

The two target steps above are the required preparation steps to enable this process. The sections below actually submit the function call to sbatch, and then monitor the process on the cluster.

#### Slurm job submission of workflow methods

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
        dependencies=c(pecan_continue)
      )
    ),
    # block and wait until dist. job is done
    tar_target(
      settings_job_outcome,
      pecan_monitor_cluster_job(pecan_settings=pecan_settings, job_id_list=pecan_settings_job_submission)
    ), ## blocks until component jobs are done
```

These two target steps submit the function call which is abstracted in the previous two steps. It is important to note that the function artifact and the argument artifact are passed as __string__ names, not variable names. 

The apptainer reference provides the apptainer information that will encapsulate the R function call on the Slurm worker node. The 'task_id' variable provides the unique identifier for the job submission to ensure non-collision with existing files or directories.

The final tar_target here monitors the job submission and blocks until it is complete. This should be used as-needed, as in some cases, it is important to finish a distributed compute process before moving on with the rest of an analysis pipeline. In other cases, large amounts of compute of multiple steps can be executed simultaneously, and so it may not be necessary to block until all those computations are complete.


---

### Section 5: Ecosystem Model Runs

```r
    tar_target(
      ecosystem_settings,
      pecan_start_ecosystem_model_runs(pecan_settings=pecan_settings, dependencies=c(settings_job_outcome))
    ),
    tar_target(
      model_results_settings,
      pecan_get_model_results(pecan_settings=ecosystem_settings)
    ),
    tar_target(
      ensembled_results_settings, ## the sequential settings here serve to ensure these are run in sequence, rather than in parallel
      pecan_run_ensemble_analysis(pecan_settings=model_results_settings)
    ),
    tar_target(
      sensitivity_settings,
      pecan_run_sensitivity_analysis(pecan_settings=ensembled_results_settings)
    ),
    tar_target(
      complete_settings,
      pecan_workflow_complete(pecan_settings=sensitivity_settings)
    )
  )
}, ask = FALSE, script = analysis_tar_script_path)
```

These sections show sequential execution of PEcAn functions. Note that these functions submit work via slurm based on PEcAn internal functionality. Because these functions submit work to Slurm, they __cannot__ be executed within an apptainer themselves.

Also note that each step uses a __pecan_settings__ object, and returns a similar object. These do not mutate this object in any way, and so in fact all of these settings objects are in fact identical. However, by passing these objects from one call to the next, we create dependency of each step on the prior step, and enforce their sequential evaluation. If all of these different steps were passed the original __pecan_settings__ variable, each step would execute in parallel. 


---

### Section 6: Script Post-Processing and Execution

```r
script_content <- readLines(analysis_tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", function_path, script_content)
script_content <- gsub("@PECANXML@", pecan_xml_path, script_content)
script_content <- gsub("@WORKFLOWDATASOURCE@", this_data_source_directory, script_content)
script_content <- gsub("@APPTAINERSOURCE@", apptainer_source_dir, script_content)
script_content <- gsub("@APPTAINERSIF@", apptainer_sif, script_content)

writeLines(script_content, analysis_tar_script_path)
```

**Purpose**: 
- Replaces all placeholder values with actual paths and values
- Writes the final pipeline script

```r
tar_make(script = analysis_tar_script_path)
```
This line actually executes the pipeline script, in the workflow run directory.


## Key Concepts Demonstrated

### 1. Complete PEcAn Workflow Integration
This workflow executes the full PEcAn ecosystem modeling pipeline from configuration through ensemble and sensitivity analysis.

### 2. Multi-Workflow Composition
References artifacts from two different previous workflows, enabling:
- Workflow reuse
- Clear dependency management
- Modular development

### 3. Distributed Computing Pattern
The abstraction pattern enables:
- Remote execution of arbitrary R functions
- Proper job scheduling via SLURM
- Resource management on HPC clusters

### 4. Sequential Workflow Orchestration
Dependencies ensure proper execution order while allowing parallel execution where possible.

### 5. Helper Function Integration
The use of `workflow_run_directory_setup()` demonstrates:
- Code reusability
- Cleaner interfaces
- Encapsulation of common patterns

## Workflow Sequence

```
Workflow 01: Data Preparation
    ↓
Workflow 02: Container Setup & Configuration
    ↓
Workflow 03: Model Execution & Analysis (This workflow)
```

## Usage

```bash
Rscript 03_run_distributed_workflow.R --settings 03_pecan_workflow_config_example.xml
```

## Dependencies

- Workflow 01 (data preparation) must complete first
- Workflow 02 (container and configuration setup) must complete first
- SLURM cluster access
- Apptainer available on cluster nodes
- Sufficient cluster resources for model ensemble runs

## Output

This workflow produces:
- PEcAn model configurations
- Ecosystem model outputs (NetCDF files)
- Ensemble summary statistics
- Sensitivity analysis results
- Completed workflow status

## Next Steps

After running this workflow:
1. Examine model outputs in the run directory
2. Review ensemble and sensitivity analysis results
3. Use results as inputs for downstream analysis workflows
4. Modify PEcAn XML configuration to explore different scenarios
5. Iterate with smart re-evaluation by changing model parameters
