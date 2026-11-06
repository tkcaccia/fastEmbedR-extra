args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) {
    stop("Usage: Rscript run_mnist70k.R KNN_RDS PCA_RDATA ",
         "OUTPUT_DIR LIB ORDER")
}
knn_path <- normalizePath(args[[1L]], mustWork = TRUE)
pca_path <- normalizePath(args[[2L]], mustWork = TRUE)
output <- normalizePath(args[[3L]], mustWork = TRUE)
library_path <- normalizePath(args[[4L]], mustWork = TRUE)
run_order <- match.arg(args[[5L]], c("forward", "reverse"))
if (length(list.files(output, all.files = TRUE, no.. = TRUE))) {
    stop("Output directory must be empty.")
}
.libPaths(c(library_path, .libPaths()))
library(fastEmbedR)
if (!startsWith(find.package("fastEmbedR"), library_path)) {
    stop("Candidate package did not load from the isolated library.")
}
stopifnot(identical(Sys.getenv("OPENBLAS_NUM_THREADS"), "1"))

knn_input <- readRDS(knn_path)$knn
env <- new.env(parent = emptyenv())
load(pca_path, envir = env)
layout <- env$pca_init$layout
stopifnot(identical(dim(knn_input$indices), c(70000L, 15L)),
          identical(dim(layout), c(70000L, 2L)),
          all(is.finite(knn_input$distances)),
          all(is.finite(layout)))
prefix <- file.path(output, "mnist70k_knn")
writeBin(as.integer(t(knn_input$indices)),
         paste0(prefix, ".indices.u32"), size = 4L,
         endian = "little")
writeBin(as.numeric(t(knn_input$distances)),
         paste0(prefix, ".distances.f32"), size = 4L,
         endian = "little")
init_path <- file.path(output, "mnist70k_init.f32")
writeBin(as.numeric(t(layout)), init_path, size = 4L,
         endian = "little")
init <- massive_matrix(init_path, 70000L, 2L)

graph_time <- system.time({
    knn <- massive_knn_graph(prefix, 70000L, 15L)
    graph <- massive_umap_fuzzy_graph(
        massive_umap_memberships(knn),
        file.path(output, "mnist70k_fuzzy"),
        memory_limit = "1GB")
})
stopifnot(graph$n_vertices == 70000L)
input_hashes <- system2("sha256sum", c(knn_path, pca_path),
                        stdout = TRUE)
writeLines(c(paste0("R_VERSION=", getRversion()),
             paste0("PACKAGE=", find.package("fastEmbedR")),
             paste0("ORDER=", run_order),
             paste0("GRAPH_SECONDS=", graph_time[["elapsed"]]),
             input_hashes), file.path(output, "manifest.txt"))

workers_grid <- c(1L, 2L, 4L, 8L)
if (run_order == "reverse") workers_grid <- rev(workers_grid)
results <- vector("list", length(workers_grid))
reference <- NULL
for (i in seq_along(workers_grid)) {
    workers <- workers_grid[[i]]
    path <- file.path(output, sprintf("umap_sync_cpu%d.f32", workers))
    elapsed <- system.time({
        fit <- umap(graph, init = init, output = path,
                    massive = "out_of_core_graph", backend = "cpu",
                    n.cores = workers, cpu_update = "synchronized",
                    memory_limit = "4GB")
    })[["elapsed"]]
    observed <- massive_read_rows(fit, 1L, 70000L)
    stopifnot(identical(fit$optimizer,
                        "synchronized_cpu_fixed_point"),
              identical(fit$parameters$cpu_update, "synchronized"),
              identical(fit$resources$effective_cpu_workers,
                        workers), all(is.finite(observed)))
    if (is.null(reference)) reference <- observed
    stopifnot(identical(reference, observed))
    results[[i]] <- data.frame(
        dataset = "MNIST70k", backend = fit$backend,
        optimizer = fit$optimizer, workers_requested = workers,
        workers_effective = fit$resources$effective_cpu_workers,
        graph_edges = graph$n_edges, epochs = fit$parameters$n_epochs,
        graph_elapsed_sec = unname(graph_time[["elapsed"]]),
        fit_elapsed_sec = unname(elapsed),
        output_sha256 = strsplit(system2("sha256sum", path,
            stdout = TRUE), " ")[[1L]][[1L]],
        stringsAsFactors = FALSE)
    write.csv(do.call(rbind, results[seq_len(i)]),
              file.path(output, "summary.csv"), row.names = FALSE)
    print(results[[i]])
}
