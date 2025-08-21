# _targets.R file
library(targets)
library(tarchetypes)
library(uuid)
tar_source()
tar_option_set(packages = c("readr", "dplyr"))
# tar_option_set(packages = c("readr", "dplyr", "PEcAn.all", "PEcAn.SIPNET"))



# ok, so here is where we left this off.
# this pipeline will create a run directory.
# then, it takes a data file from 'an external location' and puts it in the run directory, under a defined step name.
# it can then take another data file, and put it in another step name.
# then we can take the data from those two steps, and put it in a third. 
# this means we can put data in places. 
# next:
# we need to be sure we can then execute a method on a set of data inputs, and specify an output location for that output.
# we should be able to abstract away certain aspects of the data preparation such that the workflow will run on an arbitrary ID, based on the input data parameters. 
# we can then update the UUID section such that, if a person provides a runID, the run is ... reattempted, or re-run, or whatever. 
# if they do not provide a runID, one is created for them.
# this means that a section of code in the 'functions.R' script will invoke a slurm-submission, leveraging an apptainer, that will run pecan, and execute distributed work.
# this method will then gather up the output of that run, place it in a location, and save the metadata of all the steps and run I/O for that run.
# so the user specifies input parameters, and this thing takes care of all the chores.
# warnings:
# we need to be careful of slurm submissions that do not block. this will carry on right past those, and result in expectation of output when it isn't available.
# you need to be more clear with yourself: what problem is this solving?

# we need to be able to target code that is not contained in R/functions.R - we will need to be able to use a common resource across different directories and workflows.
# we need to identify how we can completely reset the run directory and the _targets directory, such that a user can start fresh.

# once everything is localized, we can run stuff in an apptainer

# list(
#   tar_target(workflow_run_01, prepare_run_directory(workflow_run=workflow_run, run_directory=this_run_directory)),
#   tar_target(workflow_run_02, localize_data_resources(workflow_run=workflow_run_01, data_resource_file_paths=data1, step_name="step1")),
#   tar_target(workflow_run_03, localize_data_resources(workflow_run=workflow_run_02, data_resource_file_paths=data2, step_name="step2")),
#   tar_target(workflow_run_04, localize_data_resources(workflow_run=workflow_run_03, data_resource_file_paths=c(workflow_run_03$data_resources$step2, workflow_run_02$data_resources$step1), step_name="step3")),
#   tar_target(workflow_run_04_print, print_object(workflow_run_04))
# )

list(
  tar_target(data_file_01, "./data.csv", format = "file"),
  tar_target(data_file_02, "./data_2.csv", format = "file"),
  tar_target(data_01, load_data(data_file_01)),
  tar_target(data_02, load_data(data_file_02)),
  tar_target(data_03, c(data_01, data_02)),
  tar_target(data_03_print, print_object(data_03))
)