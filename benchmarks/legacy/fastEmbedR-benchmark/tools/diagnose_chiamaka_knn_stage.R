args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    "Usage: Rscript diagnose_chiamaka_knn_stage.R <environment> <output.csv>",
    call. = FALSE
  )
}

environment_label <- args[[1L]]
output_file <- normalizePath(args[[2L]], mustWork = FALSE)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

suppressPackageStartupMessages({
  library(float)
  library(fastEmbedR)
})

env <- new.env(parent = emptyenv())
load(
  "/mnt/sata_ssd/fastEmbedR/Data/MNIST/MNIST_float32.RData",
  envir = env
)
x <- env$dataset$data

gc()
start <- proc.time()[["elapsed"]]
knn <- fastEmbedR::precompute_knn(
  x,
  k = 30L,
  metric = "euclidean",
  backend = "cpu",
  n_threads = 4L
)
elapsed <- proc.time()[["elapsed"]] - start

detail <- knn$timing
if (is.null(detail)) {
  detail <- attr(knn, "timing", exact = TRUE)
}
read_detail <- function(name) {
  if (is.null(detail) || is.null(detail[[name]])) {
    return(NA_real_)
  }
  as.numeric(detail[[name]])
}

result <- data.frame(
  environment = environment_label,
  elapsed_sec = elapsed,
  convert_sec = read_detail("convert"),
  build_sec = read_detail("build"),
  query_sec = read_detail("query"),
  engine = knn$engine %||% knn$method %||% attr(knn, "method") %||% NA_character_,
  package_version = as.character(packageVersion("fastEmbedR")),
  r_version = R.version.string,
  stringsAsFactors = FALSE
)

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
write.csv(result, output_file, row.names = FALSE)
print(result)
