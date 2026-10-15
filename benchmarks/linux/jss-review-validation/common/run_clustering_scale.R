#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || length(args) > 4L) {
    stop(paste(
        "Usage: run_clustering_scale.R BACKEND OUTPUT_CSV",
        "[EXPECTED_VERSION] [SIZES]"
    ))
}
backend <- match.arg(args[[1L]], c("cpu", "cuda", "metal"))
output <- args[[2L]]
expected <- if (length(args) >= 3L) args[[3L]] else "0.1"
sizes <- if (length(args) >= 4L) {
    as.integer(strsplit(args[[4L]], ",", fixed = TRUE)[[1L]])
} else {
    c(1500L, 3000L, 10000L, 50000L)
}
if (anyNA(sizes) || any(sizes < 100L | sizes %% 100L != 0L)) {
    stop("Sizes must be multiples of 100 and at least 100.")
}
if (as.character(packageVersion("fastEmbedR")) != expected) {
    stop("Installed fastEmbedR version does not match the requested version.")
}
suppressPackageStartupMessages(library(fastEmbedR))
script <- sub("^--file=", "", commandArgs(FALSE)[
    startsWith(commandArgs(FALSE), "--file=")
][[1L]])
script_dir <- dirname(normalizePath(script, mustWork = TRUE))
source(file.path(script_dir, "pca_clustering_validation.R"))
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)

make_planted_graph <- function(n) {
    groups <- as.integer((seq_len(n) - 1L) %/% 100L)
    from <- rep(seq_len(n), each = 8L)
    offset <- rep(seq_len(8L), times = n)
    to <- as.integer(groups[from] * 100L +
        ((from - 1L + offset) %% 100L) + 1L)
    bridges <- rep(seq.int(100L, n - 100L, by = 100L), each = 10L)
    bridge_from <- bridges - rep(0:9, length.out = length(bridges))
    bridge_to <- bridges + rep(1:10, length.out = length(bridges))
    from <- c(from, bridge_from)
    to <- c(to, bridge_to)
    weight <- c(rep(1, n * 8L), rep(0.2, length(bridges)))
    graph <- list(
        from = from, to = to, weight = weight,
        n_vertices = n, n_edges = length(from)
    )
    class(graph) <- c("fastEmbedR_graph", "list")
    list(graph = graph, labels = groups + 1L)
}

result_row <- function(n, method, implementation, run, elapsed, fit,
                       labels, reference) {
    data.frame(
        graph = "planted_ring", n_vertices = n,
        n_edges = length(labels) * 8L +
            (n %/% 100L - 1L) * 10L,
        groups = n %/% 100L, method = method,
        implementation = implementation, backend = backend,
        run = run, seed = 4L, elapsed_sec = elapsed,
        label_ari = adjusted_rand_index(fit$membership, labels),
        reference_membership_ari = adjusted_rand_index(
            fit$membership, reference
        ),
        modularity = fit$modularity,
        observed_backend = if (implementation == "fastEmbedR") {
            fit$backend
        } else {
            "cpu"
        },
        package_version = expected,
        stringsAsFactors = FALSE
    )
}

run_case <- function(n, method) {
    input <- make_planted_graph(n)
    graph <- input$graph
    oracle_graph <- if (backend == "cpu") {
        as_igraph_graph(graph)
    } else {
        NULL
    }
    run_fastembedr_cluster(graph, method, backend, 4L)
    if (backend == "cpu") {
        run_igraph_cluster_timed(oracle_graph, method, 4L)
    }
    reference <- if (backend == "cpu") {
        NULL
    } else {
        run_fastembedr_cluster(graph, method, "cpu", 4L)$fit$membership
    }
    rows <- list()
    for (run in seq_len(3L)) {
        native <- run_fastembedr_cluster(graph, method, backend, 4L)
        oracle <- if (backend == "cpu") {
            run_igraph_cluster_timed(oracle_graph, method, 4L)
        } else {
            NULL
        }
        paired <- if (backend == "cpu") {
            oracle$fit$membership
        } else {
            reference
        }
        rows[[length(rows) + 1L]] <- result_row(
            n, method, "fastEmbedR", run, native$elapsed,
            native$fit, input$labels, paired
        )
        if (backend == "cpu") {
            rows[[length(rows) + 1L]] <- result_row(
                n, method, "igraph", run, oracle$elapsed,
                oracle$fit, input$labels, native$fit$membership
            )
        }
    }
    do.call(rbind, rows)
}

results <- list()
for (n in sizes) {
    methods <- c("louvain", "leiden")
    if (backend == "cpu" && n <= 3000L) {
        methods <- c(methods, "walktrap")
    }
    for (method in methods) {
        result <- run_case(n, method)
        results[[length(results) + 1L]] <- result
        write.csv(do.call(rbind, results), output, row.names = FALSE)
        cat(backend, method, n, "completed\n")
        flush.console()
    }
}
