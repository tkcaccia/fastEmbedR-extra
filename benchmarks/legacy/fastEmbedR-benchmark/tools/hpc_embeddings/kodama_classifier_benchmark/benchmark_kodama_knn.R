#!/usr/bin/env Rscript

script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- normalizePath(
  sub("^--file=", "", script_argument[[1L]]),
  mustWork = TRUE
)
source(file.path(dirname(script_path), "kodama_benchmark_common.R"))
run_kodama_benchmark("knn", script_path)
