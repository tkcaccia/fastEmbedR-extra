#!/usr/bin/env Rscript

parse_args <- function(values) {
  out <- list()
  for (value in values) {
    if (!startsWith(value, "--")) next
    pair <- strsplit(sub("^--", "", value), "=", fixed = TRUE)[[1L]]
    out[[gsub("-", "_", pair[[1L]])]] <-
      if (length(pair) > 1L) paste(pair[-1L], collapse = "=") else "TRUE"
  }
  out
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

adjusted_rand_index <- function(left, right) {
  contingency <- table(left, right)
  choose2 <- function(x) x * (x - 1) / 2
  count <- sum(contingency)
  if (count < 2L) return(1)
  same <- sum(choose2(contingency))
  row_pairs <- sum(choose2(rowSums(contingency)))
  column_pairs <- sum(choose2(colSums(contingency)))
  expected <- row_pairs * column_pairs / choose2(count)
  maximum <- (row_pairs + column_pairs) / 2
  if (maximum == expected) 1 else (same - expected) / (maximum - expected)
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
graph_file <- args$graph %||% stop("--graph is required.", call. = FALSE)
labels_file <- args$labels
out_dir <- normalizePath(
  args$out_dir %||% file.path(
    getwd(), "results", paste0("cached_graph_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  ),
  mustWork = FALSE
)
machine <- args$machine %||% Sys.info()[["nodename"]]
seeds <- as.integer(strsplit(args$seeds %||% "4,17,42", ",", fixed = TRUE)[[1L]])
requested <- trimws(
  strsplit(args$backends %||% "cpu,metal,cuda", ",", fixed = TRUE)[[1L]]
)
requested <- intersect(requested, c("cpu", "metal", "cuda"))

if (!requireNamespace("fastEmbedR", quietly = TRUE)) {
  stop("fastEmbedR is not installed.", call. = FALSE)
}
if (!requireNamespace("igraph", quietly = TRUE)) {
  stop("igraph is required as the external oracle.", call. = FALSE)
}

graph <- readRDS(graph_file)
if (!inherits(graph, "fastEmbedR_graph")) {
  stop("--graph must contain a fastEmbedR_graph object.", call. = FALSE)
}
labels <- if (is.null(labels_file)) NULL else readRDS(labels_file)
if (!is.null(labels) && length(labels) != graph$n_vertices) {
  stop("The label vector length does not match graph$n_vertices.", call. = FALSE)
}

available <- c(
  cpu = TRUE,
  metal = isTRUE(tryCatch(
    fastEmbedR:::graph_clustering_metal_available_cpp(),
    error = function(error) FALSE
  )),
  cuda = isTRUE(tryCatch(
    fastEmbedR:::graph_clustering_cuda_available_cpp(),
    error = function(error) FALSE
  ))
)
backends <- requested[available[requested]]
if (!length(backends)) stop("No requested backend is available.", call. = FALSE)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
igraph_graph <- igraph::graph_from_data_frame(
  data.frame(from = graph$from, to = graph$to, weight = graph$weight),
  directed = FALSE,
  vertices = seq_len(graph$n_vertices)
)

warm_graph <- structure(
  list(
    from = c(1L, 2L, 4L, 5L),
    to = c(2L, 3L, 5L, 6L),
    weight = rep(1, 4L),
    n_vertices = 6L,
    n_edges = 4L
  ),
  class = c("fastEmbedR_graph", "list")
)
for (backend in setdiff(backends, "cpu")) {
  invisible(fastEmbedR::graph_cluster(
    warm_graph, "leiden", backend = backend, n_iterations = 2L, seed = 1L
  ))
}

rows <- list()
append_row <- function(...) {
  rows[[length(rows) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
}

for (method in c("louvain", "leiden")) {
  for (seed in seeds) {
    set.seed(seed)
    reference_elapsed <- system.time({
      reference <- if (identical(method, "louvain")) {
        igraph::cluster_louvain(
          igraph_graph,
          weights = igraph::E(igraph_graph)$weight,
          resolution = 1
        )
      } else {
        igraph::cluster_leiden(
          igraph_graph,
          objective_function = "modularity",
          weights = igraph::E(igraph_graph)$weight,
          resolution = 1,
          n_iterations = 10L
        )
      }
    })[["elapsed"]]
    reference_membership <- igraph::membership(reference)
    reference_modularity <- igraph::modularity(
      igraph_graph,
      reference_membership,
      weights = igraph::E(igraph_graph)$weight,
      resolution = 1
    )
    append_row(
      machine = machine,
      implementation = "igraph",
      method = method,
      backend = "cpu",
      seed = seed,
      n = graph$n_vertices,
      edges = graph$n_edges,
      elapsed_sec = unname(reference_elapsed),
      modularity = reference_modularity,
      ari_labels = if (is.null(labels)) NA_real_ else
        adjusted_rand_index(reference_membership, labels),
      ari_igraph = 1,
      communities = length(unique(reference_membership)),
      connected_communities = NA
    )

    for (backend in backends) {
      elapsed <- system.time({
        result <- fastEmbedR::graph_cluster(
          graph,
          method = method,
          backend = backend,
          resolution = 1,
          n_iterations = 10L,
          n_runs = 1L,
          seed = seed
        )
      })[["elapsed"]]
      append_row(
        machine = machine,
        implementation = "fastEmbedR",
        method = method,
        backend = backend,
        seed = seed,
        n = graph$n_vertices,
        edges = graph$n_edges,
        elapsed_sec = unname(elapsed),
        modularity = result$modularity,
        ari_labels = if (is.null(labels)) NA_real_ else
          adjusted_rand_index(result$membership, labels),
        ari_igraph = adjusted_rand_index(result$membership, reference_membership),
        communities = result$n_communities,
        connected_communities = result$connected_communities
      )
    }
  }
}

results <- do.call(rbind, rows)
write.csv(results, file.path(out_dir, "cached_graph_runs.csv"), row.names = FALSE)

keys <- interaction(
  results$implementation, results$method, results$backend, drop = TRUE
)
summary_rows <- lapply(split(results, keys), function(part) {
  data.frame(
    machine = part$machine[[1L]],
    implementation = part$implementation[[1L]],
    method = part$method[[1L]],
    backend = part$backend[[1L]],
    n = part$n[[1L]],
    edges = part$edges[[1L]],
    median_elapsed_sec = median(part$elapsed_sec),
    elapsed_iqr_sec = IQR(part$elapsed_sec),
    median_modularity = median(part$modularity),
    median_ari_labels = if (all(is.na(part$ari_labels))) {
      NA_real_
    } else {
      median(part$ari_labels, na.rm = TRUE)
    },
    minimum_ari_igraph = min(part$ari_igraph, na.rm = TRUE),
    median_communities = median(part$communities),
    all_connected = if (all(is.na(part$connected_communities))) {
      NA
    } else {
      all(part$connected_communities, na.rm = TRUE)
    }
  )
})
summary <- do.call(rbind, summary_rows)
row.names(summary) <- NULL
write.csv(summary, file.path(out_dir, "cached_graph_summary.csv"), row.names = FALSE)
print(summary)
cat("Results:", out_dir, "\n")
