#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name) {
    prefix <- paste0("--", name, "=")
    value <- args[startsWith(args, prefix)]
    if (!length(value)) stop("Missing --", name, call. = FALSE)
    sub(prefix, "", tail(value, 1L), fixed = TRUE)
}

script_file <- sub("^--file=", "", commandArgs(FALSE)[
    startsWith(commandArgs(FALSE), "--file=")
][[1L]])
script_dir <- dirname(normalizePath(script_file, mustWork = TRUE))
source(file.path(script_dir, "common.R"))

input <- normalizePath(arg_value("input"), mustWork = TRUE)
output <- arg_value("output")
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
plot_embedding_csv(input, output)
