#!/usr/bin/env Rscript

script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE),
    value = TRUE)[[1L]])
path <- file.path(dirname(normalizePath(script)), "run_case.R")
definitions <- parse(path)
environment <- new.env(parent = globalenv())
for (expression in definitions) {
    if (!is.call(expression) || !identical(expression[[1L]], as.name("<-"))) {
        next
    }
    if (as.character(expression[[2L]]) %in% c(
            "blocked", "validate_bigann_identity")) {
        eval(expression, envir = environment)
    }
}
stopifnot(exists("validate_bigann_identity", envir = environment))
path <- tempfile(fileext = ".json")
identity <- list(dataset = "deep", rows = 1000000000,
    columns = 96L, bytes = 384000000008,
    sha256 = paste(rep("a", 64L), collapse = ""))
write_identity <- function(value) {
    jsonlite::write_json(value, path, auto_unbox = TRUE)
}
rejects <- function(value) {
    write_identity(value)
    inherits(try(environment$validate_bigann_identity(path, "deep",
        384000000008, 96L), silent = TRUE), "try-error")
}
write_identity(identity)
stopifnot(identical(environment$validate_bigann_identity(path, "deep",
    384000000008, 96L), identity$sha256))
wrong <- identity
wrong$bytes <- NULL
stopifnot(rejects(wrong))
wrong <- identity
wrong$bytes <- identity$bytes - 4
stopifnot(rejects(wrong))
wrong <- identity
wrong$sha256 <- "bad"
stopifnot(rejects(wrong))
unlink(path)
cat("BigANN manifest bytes and SHA-256: PASS\n")
