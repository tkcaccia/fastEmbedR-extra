#!/usr/bin/env Rscript

# Native clustering validation. cuGraph is intentionally not loaded: igraph is
# the external correctness/performance oracle and fastEmbedR supplies every
# CPU, CUDA, and Metal clustering implementation under test.

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
args <- parse_args(commandArgs(trailingOnly = TRUE))
out_dir <- normalizePath(
  args$out_dir %||% file.path(
    getwd(), "results", paste0("native_clustering_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  ),
  mustWork = FALSE
)
n <- as.integer(args$n %||% 50000L)
blocks <- as.integer(args$blocks %||% 10L)
seeds <- as.integer(strsplit(args$seeds %||% "4,17,42", ",", fixed = TRUE)[[1L]])
requested <- strsplit(args$backends %||% "cpu,metal,cuda", ",", fixed = TRUE)[[1L]]
requested <- intersect(trimws(requested), c("cpu", "metal", "cuda"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("fastEmbedR", quietly = TRUE)) {
  stop("fastEmbedR is not installed.", call. = FALSE)
}
if (!requireNamespace("igraph", quietly = TRUE)) {
  stop("igraph is required as the benchmark oracle.", call. = FALSE)
}

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

make_block_graph <- function(n, block_count, within_degree = 15L) {
  stopifnot(n >= block_count * (within_degree + 2L))
  block_size <- floor(n / block_count)
  n <- block_size * block_count
  truth <- rep(seq_len(block_count), each = block_size)
  vertices <- seq_len(n)
  from <- integer(n * (within_degree + 1L))
  to <- integer(length(from))
  weight <- numeric(length(from))
  cursor <- 1L
  for (block in seq_len(block_count)) {
    start <- (block - 1L) * block_size
    local <- seq_len(block_size)
    current <- start + local
    for (offset in seq_len(within_degree)) {
      positions <- cursor:(cursor + block_size - 1L)
      from[positions] <- current
      jump <- ((local * 7919 + offset * 104729) %% (block_size - 1L)) + 1L
      to[positions] <- start + ((local - 1L + jump) %% block_size) + 1L
      weight[positions] <- 0.75 + 0.5 * ((local + offset) %% 17L) / 16
      cursor <- cursor + block_size
    }
    positions <- cursor:(cursor + block_size - 1L)
    next_block <- block %% block_count
    from[positions] <- current
    to[positions] <- next_block * block_size + local
    weight[positions] <- 0.015 + 0.02 * (local %% 11L) / 10
    cursor <- cursor + block_size
  }
  lower <- pmin(from, to)
  upper <- pmax(from, to)
  key <- as.double(lower) * (n + 1) + upper
  order <- order(key, -weight)
  keep <- !duplicated(key[order])
  selected <- order[keep]
  from <- lower[selected]
  to <- upper[selected]
  weight <- weight[selected]

  structure(
    list(
      graph = structure(
        list(
          from = from,
          to = to,
          weight = weight,
          n_vertices = n,
          n_edges = length(from)
        ),
        class = c("fastEmbedR_graph", "list")
      ),
      truth = truth
    ),
    class = "native_clustering_case"
  )
}

available <- c(cpu = TRUE, metal = FALSE, cuda = FALSE)
available[["metal"]] <- isTRUE(
  tryCatch(
    fastEmbedR:::graph_clustering_metal_available_cpp(),
    error = function(error) FALSE
  )
)
available[["cuda"]] <- isTRUE(
  tryCatch(
    fastEmbedR:::graph_clustering_cuda_available_cpp(),
    error = function(error) FALSE
  )
)
backends <- requested[available[requested]]
if (!length(backends)) stop("No requested fastEmbedR backend is available.", call. = FALSE)

case <- make_block_graph(n, blocks)
graph <- case$graph
truth <- case$truth
igraph_graph <- igraph::graph_from_data_frame(
  data.frame(from = graph$from, to = graph$to, weight = graph$weight),
  directed = FALSE,
  vertices = seq_len(graph$n_vertices)
)

# Exclude one-time CUDA context and Metal pipeline compilation from repeated
# algorithm timing, just as igraph shared-library loading is excluded.
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
      implementation = "igraph",
      method = method,
      backend = "cpu",
      seed = seed,
      n = graph$n_vertices,
      edges = graph$n_edges,
      elapsed_sec = unname(reference_elapsed),
      modularity = reference_modularity,
      modularity_gap_vs_igraph = 0,
      ari_vs_truth = adjusted_rand_index(reference_membership, truth),
      ari_vs_igraph = 1,
      n_communities = length(unique(reference_membership)),
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
        implementation = "fastEmbedR",
        method = method,
        backend = backend,
        seed = seed,
        n = graph$n_vertices,
        edges = graph$n_edges,
        elapsed_sec = unname(elapsed),
        modularity = result$modularity,
        modularity_gap_vs_igraph = result$modularity - reference_modularity,
        ari_vs_truth = adjusted_rand_index(result$membership, truth),
        ari_vs_igraph = adjusted_rand_index(
          result$membership, reference_membership
        ),
        n_communities = result$n_communities,
        connected_communities = result$connected_communities
      )
    }
  }
}

results <- do.call(rbind, rows)
write.csv(results, file.path(out_dir, "native_clustering_runs.csv"), row.names = FALSE)

key <- interaction(
  results$implementation, results$method, results$backend, drop = TRUE
)
summary_rows <- lapply(split(results, key), function(part) {
  data.frame(
    implementation = part$implementation[[1L]],
    method = part$method[[1L]],
    backend = part$backend[[1L]],
    n = part$n[[1L]],
    edges = part$edges[[1L]],
    median_elapsed_sec = median(part$elapsed_sec),
    elapsed_iqr_sec = IQR(part$elapsed_sec),
    median_modularity = median(part$modularity),
    minimum_ari_vs_truth = min(part$ari_vs_truth),
    minimum_ari_vs_igraph = min(part$ari_vs_igraph),
    all_connected = if (all(is.na(part$connected_communities))) {
      NA
    } else {
      all(part$connected_communities, na.rm = TRUE)
    }
  )
})
summary <- do.call(rbind, summary_rows)
row.names(summary) <- NULL
write.csv(
  summary,
  file.path(out_dir, "native_clustering_summary.csv"),
  row.names = FALSE
)
print(summary)
cat("Results:", out_dir, "\n")
