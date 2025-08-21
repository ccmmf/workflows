library(targets)
library(targets)
library(tarchetypes)
library(uuid)
tar_source()
tar_option_set(packages = c("readr", "dplyr"))
list(tar_target(data_file_01, "./data.csv", format = "file"), 
    tar_target(data_file_02, "./data_2.csv", format = "file"), 
    tar_target(data_01, load_data(data_file_01)), tar_target(data_02, 
        load_data(data_file_02)), tar_target(data_03, c(data_01, 
        data_02)), tar_target(data_03_print, print_object(data_03)))
