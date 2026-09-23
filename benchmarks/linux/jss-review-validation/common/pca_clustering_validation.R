adjusted_rand_index <- function(left, right) {
    if (length(left) != length(right) || anyNA(left) || anyNA(right)) {
        return(NA_real_)
    }
    tab <- table(left, right)
    choose_two <- function(x) x * (x - 1) / 2
    n <- sum(tab)
    if (n < 2L) return(NA_real_)
    same <- sum(choose_two(tab))
    row_pairs <- sum(choose_two(rowSums(tab)))
    col_pairs <- sum(choose_two(colSums(tab)))
    expected <- row_pairs * col_pairs / choose_two(n)
    maximum <- (row_pairs + col_pairs) / 2
    if (maximum == expected) return(1)
    (same - expected) / (maximum - expected)
}

validate_public_api <- function() {
    exports <- getNamespaceExports("fastEmbedR")
    required <- c(
        "tsne", "tsne_knn", "umap", "umap_knn", "pca",
        "precompute_knn", "knn_graph", "graph_cluster",
        "select_landmarks", "project_landmark_model"
    )
    removed <- c(
        "embed_knn", "fastEmbedR_api", "fastEmbedR_capabilities",
        "fastEmbedR_embedding_methods", "fastEmbedR_graph_methods",
        "fastEmbedR_backend", "fit_landmark_model", "tsne_pca_init"
    )
    missing <- setdiff(required, exports)
    stale <- intersect(removed, exports)
    if (length(missing) || length(stale)) {
        stop(
            "Public API mismatch; missing: ", paste(missing, collapse = ", "),
            "; stale: ", paste(stale, collapse = ", "), call. = FALSE
        )
    }
    if (!"landmarks" %in% names(formals(fastEmbedR::tsne)) ||
            !"landmarks" %in% names(formals(fastEmbedR::umap)) ||
            !"tsne_init" %in% names(formals(fastEmbedR::pca))) {
        stop("The integrated landmark/PCA API is unavailable.", call. = FALSE)
    }
    invisible(exports)
}

canonical_cluster_graph <- function() {
    groups <- split(seq_len(18L), rep(seq_len(3L), each = 6L))
    edges <- lapply(groups, utils::combn, m = 2L)
    from <- unlist(lapply(edges, function(x) x[1L, ]), use.names = FALSE)
    to <- unlist(lapply(edges, function(x) x[2L, ]), use.names = FALSE)
    graph <- list(
        from = c(from, 6L, 12L),
        to = c(to, 7L, 13L),
        weight = c(rep(1, length(from)), 0.15, 0.15),
        n_vertices = 18L,
        n_edges = length(from) + 2L
    )
    class(graph) <- c("fastEmbedR_graph", "list")
    graph
}

pca_preflight_row <- function(x, backend, threads) {
    fit <- fastEmbedR::pca(
        x, ncomp = 2L, backend = backend,
        n.cores = threads, seed = 4L
    )
    scores <- layout_matrix(fit$scores)
    if (!grepl(backend, fit$backend, fixed = TRUE)) {
        stop("PCA backend mismatch in preflight: ", fit$backend)
    }
    if (!all(is.finite(scores))) {
        stop("PCA preflight produced non-finite scores.")
    }
    data.frame(
        component = "pca", requested_backend = backend,
        observed_backend = fit$backend, finite = TRUE,
        detail = paste(nrow(scores), ncol(scores), sep = "x"),
        stringsAsFactors = FALSE
    )
}

clustering_preflight_row <- function(backend) {
    graph <- canonical_cluster_graph()
    fit <- fastEmbedR::graph_cluster(
        graph, method = "leiden", backend = backend,
        n_iterations = 20L, n_runs = 2L, seed = 4L
    )
    truth <- rep(seq_len(3L), each = 6L)
    ari <- adjusted_rand_index(fit$membership, truth)
    if (!identical(fit$backend, backend) || ari < 0.99) {
        stop("Clustering preflight failed backend or ARI validation.")
    }
    data.frame(
        component = "leiden", requested_backend = backend,
        observed_backend = fit$backend, finite = is.finite(fit$modularity),
        detail = sprintf("communities=%d;ari=%.6f", fit$n_communities, ari),
        stringsAsFactors = FALSE
    )
}

clustering_input_path <- function(name) {
    file.path(dataset_input_dir(name), "clustering_inputs.rds")
}

prepare_clustering_dataset <- function(loaded, cap, seed) {
    rows <- stratified_rows(loaded$labels, nrow(loaded$data), cap, seed)
    selected <- subset_dataset(loaded, rows)
    list(
        x = as_float_matrix(selected$data),
        labels = selected$labels,
        rows = rows
    )
}

build_clustering_graph <- function(prepared, threads) {
    k <- min(30L, nrow(prepared$x) - 1L)
    knn_time <- system.time({
        knn <- fastEmbedR::precompute_knn(
            prepared$x, k = k, backend = "cpu", n.cores = threads
        )
    })[["elapsed"]]
    graph_time <- system.time({
        graph <- fastEmbedR::knn_graph(
            knn, k = k, backend = "cpu", weight = "snn",
            n.cores = threads
        )
    })[["elapsed"]]
    list(
        graph = graph, labels = prepared$labels, rows = prepared$rows,
        knn_sec = knn_time, graph_sec = graph_time, k = k
    )
}

clustering_manifest_row <- function(name, kind, value) {
    data.frame(
        dataset = name, graph = kind,
        n = value$graph$n_vertices, edges = value$graph$n_edges,
        k = value$k, knn_sec = value$knn_sec,
        graph_sec = value$graph_sec,
        stringsAsFactors = FALSE
    )
}

run_clustering_precompute <- function() {
    require_expected_version()
    loaded <- load_dataset(data_root, dataset)
    main <- prepare_clustering_dataset(
        loaded, min(10000L, nrow(loaded$data)), 1701L
    )
    walktrap <- prepare_clustering_dataset(
        loaded, min(1500L, nrow(loaded$data)), 1701L
    )
    inputs <- list(
        main = build_clustering_graph(main, threads),
        walktrap = build_clustering_graph(walktrap, threads)
    )
    path <- clustering_input_path(dataset)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(inputs, path, compress = FALSE)
    manifest <- rbind(
        clustering_manifest_row(dataset, "main", inputs$main),
        clustering_manifest_row(dataset, "walktrap", inputs$walktrap)
    )
    out <- dataset_output_dir("clustering_precompute", dataset, "cpu")
    write_csv_atomic(manifest, file.path(out, "clustering_precompute.csv"))
    write_status("clustering_precompute", dataset, "cpu", "success")
}

as_igraph_graph <- function(graph) {
    if (!requireNamespace("igraph", quietly = TRUE)) {
        stop("igraph is required for clustering reference validation.")
    }
    edges <- data.frame(
        from = graph$from, to = graph$to, weight = graph$weight
    )
    igraph::graph_from_data_frame(
        edges, directed = FALSE,
        vertices = data.frame(name = seq_len(graph$n_vertices))
    )
}

run_igraph_cluster <- function(graph, method, seed) {
    set.seed(seed)
    weights <- igraph::E(graph)$weight
    if (method == "louvain") {
        return(igraph::cluster_louvain(
            graph, weights = weights, resolution = 1
        ))
    }
    if (method == "walktrap") {
        return(igraph::cluster_walktrap(
            graph, weights = weights, steps = 4L
        ))
    }
    args <- list(
        graph = graph, objective_function = "modularity",
        weights = weights, n_iterations = 10L
    )
    parameters <- names(formals(igraph::cluster_leiden))
    resolution_name <- if ("resolution" %in% parameters) {
        "resolution"
    } else {
        "resolution_parameter"
    }
    args[[resolution_name]] <- 1
    do.call(igraph::cluster_leiden, args)
}

clustering_label_ari <- function(membership, labels) {
    if (is.null(labels) || length(labels) != length(membership)) {
        return(NA_real_)
    }
    if (anyNA(labels)) return(NA_real_)
    if (length(unique(labels)) < 2L) return(NA_real_)
    adjusted_rand_index(membership, labels)
}

clustering_result_row <- function(method, implementation, used_backend,
                                  seed, elapsed, result, labels,
                                  reference = NULL) {
    reference_ari <- if (is.null(reference)) {
        NA_real_
    } else {
        adjusted_rand_index(result$membership, reference)
    }
    data.frame(
        dataset = dataset, method = method,
        implementation = implementation, backend = used_backend,
        seed = seed, elapsed_sec = elapsed,
        n_vertices = length(result$membership),
        n_communities = length(unique(result$membership)),
        modularity = result$modularity,
        label_ari = clustering_label_ari(result$membership, labels),
        reference_membership_ari = reference_ari,
        connected_communities = result$connected_communities %||% NA,
        stringsAsFactors = FALSE
    )
}

run_fastembedr_cluster <- function(graph, method, used_backend, seed) {
    elapsed <- system.time({
        fit <- fastEmbedR::graph_cluster(
            graph, method = method, backend = used_backend,
            n_iterations = 20L, n_runs = 1L, steps = 4L, seed = seed
        )
    })[["elapsed"]]
    if (!identical(fit$backend, used_backend)) {
        stop("Clustering backend mismatch: requested ", used_backend,
            ", observed ", fit$backend, call. = FALSE
        )
    }
    if (length(fit$membership) != graph$n_vertices ||
            anyNA(fit$membership) || !is.finite(fit$modularity)) {
        stop("Clustering returned an invalid membership or modularity.")
    }
    if (method == "leiden" && !isTRUE(fit$connected_communities)) {
        stop("Leiden returned a disconnected community.", call. = FALSE)
    }
    list(fit = fit, elapsed = elapsed)
}

run_igraph_cluster_timed <- function(graph, method, seed) {
    elapsed <- system.time({
        fit <- run_igraph_cluster(graph, method, seed)
    })[["elapsed"]]
    membership <- as.integer(igraph::membership(fit))
    modularity <- igraph::modularity(
        graph, membership,
        weights = igraph::E(graph)$weight,
        resolution = 1
    )
    list(
        fit = list(
            membership = membership,
            modularity = as.numeric(modularity),
            connected_communities = NA
        ),
        elapsed = elapsed
    )
}

clustering_cpu_reference_path <- function(name) {
    file.path(
        dataset_output_dir("clustering", name, "cpu"),
        "memberships.rds"
    )
}

clustering_methods <- function(backend) {
    if (backend == "cpu") c("louvain", "leiden", "walktrap") else {
        c("louvain", "leiden")
    }
}

clustering_graph_for_method <- function(inputs, method) {
    if (method == "walktrap") inputs$walktrap else inputs$main
}

run_clustering_validation <- function() {
    require_expected_version()
    assert_clustering_backend(backend)
    input_path <- clustering_input_path(dataset)
    if (!file.exists(input_path)) {
        stop("Missing clustering graph: ", input_path, call. = FALSE)
    }
    inputs <- readRDS(input_path)
    out <- dataset_output_dir("clustering", dataset, backend)
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    cpu_reference <- if (backend == "cuda") {
        reference_path <- clustering_cpu_reference_path(dataset)
        if (!file.exists(reference_path)) {
            stop("Missing CPU clustering reference: ", reference_path,
                call. = FALSE
            )
        }
        readRDS(reference_path)
    } else {
        list()
    }
    rows <- list()
    memberships <- list()
    for (method in clustering_methods(backend)) {
        current <- clustering_graph_for_method(inputs, method)
        graph <- current$graph
        igraph_graph <- if (backend == "cpu") as_igraph_graph(graph) else NULL
        for (seed in seeds) {
            reference <- if (backend == "cuda") {
                cpu_reference[[paste(method, seed, sep = "_")]]
            } else {
                NULL
            }
            native <- run_fastembedr_cluster(graph, method, backend, seed)
            key <- paste(method, seed, sep = "_")
            memberships[[key]] <- native$fit$membership
            rows[[length(rows) + 1L]] <- clustering_result_row(
                method, "fastEmbedR", backend, seed,
                native$elapsed, native$fit, current$labels, reference
            )
            if (backend == "cpu") {
                oracle <- run_igraph_cluster_timed(
                    igraph_graph, method, seed
                )
                rows[[length(rows) + 1L]] <- clustering_result_row(
                    method, "igraph", "cpu", seed,
                    oracle$elapsed, oracle$fit, current$labels,
                    native$fit$membership
                )
            }
        }
    }
    write_csv_atomic(
        do.call(rbind, rows), file.path(out, "clustering.csv")
    )
    saveRDS(memberships, file.path(out, "memberships.rds"), compress = FALSE)
    write_status("clustering", dataset, backend, "success")
}
