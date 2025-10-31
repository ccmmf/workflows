# Simple Data Workflow Example

This example demonstrates a **simple data preparation workflow** that downloads and extracts CCMMF data artifacts from S3 storage. This is the foundational workflow that subsequent workflows can reference.

## Overview

This workflow showcases:
1. **Configuration-driven workflows** using XML settings
2. **Data artifact management** with automatic download and extraction from S3
3. **Reproducible execution** with unique run identifiers
4. **Smart re-evaluation** using the targets framework

## Key Files

- `01_data_prep_workflow.R` - Main workflow script
- `01_pecan_workflow_config_example.xml` - Configuration file

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

# note: if this_run_directory exists already, and we specify the _targets script within it, targets will evaluate the pipeline already run
# if the pipeline has not changed, the pipeline will not run. This extends to the targeted functions, their arguments, and their arguments values. 
# thus, as long as the components of the pipeline run are kept in the functions, the data entities, and the arguments, we can have smart re-evaluation.

this_workflow_name = "workflow.data.prep.1"

#### Primary workflow settings parsing ####
## overall run directory for common collection of workflow artifacts
workflow_run_directory = settings$orchestration$workflow.base.run.directory

## settings and params for this workflow
workflow_settings = settings$orchestration[[this_workflow_name]]
workflow_function_source = settings$orchestration$functions.source
source(workflow_function_source)

pecan_xml_path = workflow_settings$pecan.xml.path
ccmmf_data_tarball_url = workflow_settings$ccmmf.data.s3.url
ccmmf_data_filename = workflow_settings$ccmmf.data.tarball.filename
run_identifier = workflow_settings$run.identifier
```

**Purpose**: 

This set-up section brings in standard command line arguments, and extracts the orchestration settings for this workflow via the workflow name.

The content here binds into the XML configuration file. The workflow name is a particularly useful field, as it can be used to easily switch to a different configuration stanza, while keeping the remainder of the workflow set-up identical.

This section also identifies the base workflow run directory - this is a critical field, as subsequent data references look in this directory by default for data sourcing.

This section also extracts the data source configuration parameters:
- The S3 URL where the CCMMF data tarball is hosted
- The specific filename to download
- A run identifier for this workflow execution

The workflow name (`workflow.data.prep.1`) identifies this as the foundational data preparation step that subsequent workflows will reference.

The comment block early in this section documents the smart re-evaluation behavior of the targets framework, which will only re-run pipeline steps if inputs or code have changed.


---

### Section 2: Path Normalization and Run Directory Setup

```r
# TODO: input parameter validation and defense

#### Handle input parameters parased from settings file ####
#### workflow prep ####
function_path = normalizePath(file.path(workflow_function_source))
pecan_xml_path = normalizePath(file.path(pecan_xml_path))

if (!dir.exists(workflow_run_directory)) {
    dir.create(workflow_run_directory, recursive = TRUE)
} 
workflow_run_directory = normalizePath(workflow_run_directory)

if (is.null(run_identifier)) {
    run_id = uuid::UUIDgenerate() 
} else {
    print(paste("Run id specified:", run_identifier))
    run_id = run_identifier
}

this_run_directory = file.path(workflow_run_directory, run_id)
if (!dir.exists(this_run_directory)) {
    dir.create(this_run_directory, recursive = TRUE)
}
```

**Purpose**: Sets up the workflow execution environment and run directory structure.

The paths to the workflow functions and PEcAn XML are normalized to ensure absolute paths, which is critical for reliability across different working directories.

The base workflow run directory is created if it doesn't exist. This directory serves as the root for all workflow runs and is where subsequent workflows will look for data artifacts.

A run identifier is either generated (using UUID) or used from the configuration. This identifier will be used by other workflows to reference the data produced by this workflow execution.

Finally, a specific run directory is created for this workflow instance. This directory will contain all artifacts produced by this execution, including the downloaded and extracted data.


---

### Section 3: Pipeline Definition and Setup

```r
print(paste("Starting workflow run in directory:", this_run_directory))
setwd(this_run_directory)
tar_config_set(store = "./")
tar_script_path = file.path("./executed_pipeline.R")

#### Pipeline definition ####
tar_script({
  library(targets)
  library(tarchetypes)
  library(uuid)

  ccmmf_data_tarball_url = "@CCMMFDATAURL@"
  ccmmf_data_filename = "@CCMMFDATAFILENAME@"
  tar_source("@FUNCTIONPATH@")
  tar_option_set(
    packages = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow", "readr", "dplyr"),
    imports = c("PEcAn.settings", "PEcAn.utils", "PEcAn.workflow")
  )
```

**Purpose**: Sets up the initial pipeline runtime environment.

- Changes working directory to the specific run directory
- Configures the targets store to be in the current directory
- Defines the path for the generated pipeline script file

The tar_script block sets up the pipeline definition with placeholder values (marked with `@...@`) that will be replaced with actual configuration values in a later step. These placeholders are necessary because tar_make executes the script in a separate process without access to the current R environment's variables.

The required R packages for PEcAn workflows are specified, and necessary PEcAn modules are imported.


---

### Section 4: Pipeline Targets Definitions

```r
  list(
    # source data handling
    tar_target(ccmmf_data_tarball, download_ccmmf_data(prefix_url=ccmmf_data_tarball_url, local_path=tar_path_store(), prefix_filename=ccmmf_data_filename)),
    tar_target(workflow_data_paths, untar(ccmmf_data_tarball, exdir = tar_path_store())),
    tar_target(obtained_resources_untar, untar(ccmmf_data_tarball, list = TRUE))
  )
}, ask = FALSE, script = tar_script_path)
```

**Purpose**: Defines the three targets that constitute this workflow's data preparation pipeline.

The first target, `ccmmf_data_tarball`, downloads the data tarball from S3 using the CCMMF data access function. This function uses AWS CLI to access the S3-compatible storage. The tarball is downloaded to the targets store directory.

The second target, `workflow_data_paths`, extracts the tarball contents to the targets store. This extraction happens automatically whenever the tarball is downloaded or updated.

The third target, `obtained_resources_untar`, lists the extracted files. This serves as verification that the extraction was successful and also provides a record of what files were extracted.

All data is stored in the targets store directory using the `tar_path_store()` function. This ensures that all workflow artifacts are managed by the targets framework, enabling smart re-evaluation and dependency tracking.


---

### Section 5: Script Post-Processing and Execution

```r
# because tar_make executes the script in a separate process based on the created workflow directory,
# in order to parametrize the workflow script, we have to first create placeholders, and then below, replace them with actual values.
# if we simply place the variables in the script definition above, they are evaluated as the time the script is executed by tar_make()
# that execution takes place in a different process + memory space, in which those variables are not accessible.
# so, we create the execution script, and then text-edit in the parameters.
# Read the generated script and replace placeholders with actual file paths
script_content <- readLines(tar_script_path)
script_content <- gsub("@FUNCTIONPATH@", function_path, script_content)
script_content <- gsub("@CCMMFDATAURL@", ccmmf_data_tarball_url, script_content)
script_content <- gsub("@CCMMFDATAFILENAME@", ccmmf_data_filename, script_content)
writeLines(script_content, tar_script_path)
```

**Purpose**: 
- Replaces all placeholder values with actual paths and values
- Writes the final pipeline script

```r
#### workflow execution ####
# this changes the cwd to the designated tar store
tar_make(script = tar_script_path)
```

This line actually executes the pipeline script, in the workflow run directory.

The comment block explains why the placeholder replacement approach is necessary: tar_make executes in a separate process without access to the current R environment's variables. By using string replacement on the generated script, we can inject the actual configuration values before execution.

The final call to `tar_make()` triggers the execution of the complete workflow pipeline, which will download and extract the data, or use cached results if the pipeline has been run previously with the same inputs.


## Key Concepts Demonstrated

### 1. Configuration-Driven Workflows
The XML configuration separates workflow orchestration from execution logic, enabling:
- Easy modification of data sources without code changes
- Reusable workflow templates
- Clear documentation of workflow parameters

### 2. Data Artifact Management
- Automatic download from remote S3 storage
- Organized storage in workflow run directories
- Complete provenance tracking through the targets framework

### 3. Reproducible Execution
- Unique run identifiers prevent conflicts
- Complete isolation of workflow runs
- Full audit trail of data origins

### 4. Smart Re-evaluation
The targets framework ensures:
- Only changed components are re-executed
- Efficient use of disk space (shared data references)
- Automatic dependency resolution

### 5. Foundation for Workflow Composition
This workflow provides data artifacts that can be referenced by subsequent workflows using run identifiers, enabling:
- Clear dependency chains between workflows
- Data reuse across multiple analyses
- Separation of data preparation from analysis

## Workflow Sequence

This workflow is the first in the sequence:

```
Workflow 01: Data Preparation (This workflow)
    ↓ (provides data artifacts)
Workflow 02: Container Setup & Configuration
    ↓ (uses data from 01)
Workflow 03: Model Execution & Analysis
```

## Usage

```bash
Rscript 01_data_prep_workflow.R --settings 01_pecan_workflow_config_example.xml
```

## Dependencies

- R packages: `targets`, `tarchetypes`, `PEcAn.all`, `optparse`, `uuid`
- AWS CLI configured for S3 access with CCMMF credentials
- Access to CCMMF S3 storage endpoint at `s3.garage.ccmmf.ncsa.cloud`

## Output

This workflow produces:
- Downloaded data tarball: `00_cccmmf_phase_1a_input_artifacts.tgz`
- Extracted data files in subdirectories:
  - `data/` - Meteorological data files
  - `IC_files/` - Initial condition files
  - `pfts/` - Plant functional type files
- Complete workflow execution history and metadata in targets store
- Executed pipeline script: `executed_pipeline.R`

## Next Steps

After running this workflow successfully:
1. Note the run identifier (e.g., `data_prep_run_01`) for use in subsequent workflows
2. Examine the extracted data artifacts in the run directory
3. Use this workflow's output as input to workflow 02 (container setup)
4. Build more complex workflows that depend on this data preparation step
5. Iterate with smart re-evaluation by modifying data sources or workflow parameters
