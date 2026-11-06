root <- "/scratch/firenze/NN/benchmarks/fastembedr_8gpu_cpucheck_20261106"
library(fastEmbedR, lib.loc = file.path(root, "library"))
library(testthat)
loaded <- getNamespaceInfo("fastEmbedR", "path")
cat("loaded_package=", loaded, "\n", sep = "")
if (!identical(normalizePath(loaded),
        normalizePath(file.path(root, "library/fastEmbedR"))))
    stop("Wrong fastEmbedR library loaded.")
source <- paste(deparse(body(fastEmbedR:::graph_cluster_resident)),
    collapse = " ")
if (!grepl("at least two devices", source, fixed = TRUE) ||
        grepl("two to four devices", source, fixed = TRUE))
    stop("Loaded package does not contain the candidate device validation.")
testthat::test_file(file.path(root, "source/tests/testthat/",
    "test-cuda-resident-multigpu-cluster.R"),
    reporter = testthat::StopReporter$new())
cat("focused_tests_passed\n")
