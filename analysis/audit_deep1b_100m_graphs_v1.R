args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: audit_graphs.R RUN_ROOT")
root <- normalizePath(args[[1L]], mustWork = TRUE)
if (!startsWith(root, "/Users/silvanopiazza/Documents/Stefano/")) {
    stop("The Deep1B audit must remain in Stefano")
}
if (trimws(readLines(file.path(root, "queue100m/queue.exit"))) != "0") {
    stop("The Deep1B queue has not completed successfully")
}
if (!file.exists(file.path(root, "postprocess-audit-v1/audit.json"))) {
    stop("The independent byte audit must pass first")
}
library(fastEmbedR, lib.loc = file.path(root, "Rlib"))
rows <- 100000000
stages <- c("smoke_fullgraph", "pca_cpu1", "pca_cpu8", "pca_cpu20",
    "pca_cpu28", "pca_metal", "knn_cpu20", "tsne_affinity",
    "tsne_cpu20", "umap_membership", "umap_fuzzy", "umap_metal",
    "umap_cpu20", "umap_cpu1", "leiden_cpu")
get_fit <- function(stage) {
    path <- file.path(root, "cases", stage, "result.rds")
    result <- readRDS(path)
    if (!identical(result$stage, stage) ||
        result$input_rows != rows || result$input_columns != 96L ||
        !is.finite(result$seconds) || result$seconds < 0) {
        stop("Stage descriptor metadata changed: ", stage)
    }
    result$fit
}
fits <- lapply(stages, get_fit)
names(fits) <- stages
for (stage in grep("^pca_", stages, value = TRUE)) {
    fit <- fits[[stage]]
    expected <- if (stage == "pca_metal") "metal" else "cpu"
    if (fit$backend != expected || fit$scores$nrow != rows ||
        fit$scores$ncol != 2L) stop("PCA descriptor changed: ", stage)
}
knn <- fits$knn_cpu20
if (knn$n_vertices != rows || knn$k != 30L ||
    knn$backend != "cpu" ||
    knn$method != "faissr_cpu_hnsw_sharded" ||
    !isTRUE(knn$recall_audited) ||
    length(knn$audit_sample_rows) != 32L) {
    stop("Full-graph neighbor descriptor changed")
}
if (!is.finite(knn$observed_recall) ||
    !is.finite(knn$minimum_row_recall) ||
    knn$observed_recall < 0 || knn$observed_recall > 1 ||
    knn$minimum_row_recall < 0 || knn$minimum_row_recall > 1 ||
    length(knn$audit_row_recall) != 32L ||
    any(!is.finite(knn$audit_row_recall)) ||
    any(knn$audit_row_recall < 0 | knn$audit_row_recall > 1) ||
    !isTRUE(all.equal(mean(knn$audit_row_recall),
        knn$observed_recall)) ||
    !isTRUE(all.equal(min(knn$audit_row_recall),
        knn$minimum_row_recall)) ||
    knn$sampled_rows_below_target !=
        sum(knn$audit_row_recall < 0.99) ||
    !identical(isTRUE(knn$sample_target_met),
        all(knn$audit_row_recall >= 0.99))) {
    stop("Neighbor recall audit is incomplete")
}
graph_prefix <- function(stage, prefix) {
    file.path(root, "cases", stage, prefix)
}
affinity <- massive_affinity_graph(
    graph_prefix("tsne_affinity", "affinity"), rows, "stream")
fuzzy <- massive_fuzzy_graph(
    graph_prefix("umap_fuzzy", "fuzzy"), rows, "stream")
if (affinity$source_k != 30L || fuzzy$source_k != 30L ||
    affinity$sort_method != "global" ||
    fuzzy$sort_method != "global" ||
    affinity$n_edges <= 0 || fuzzy$n_edges <= 0) {
    stop("Graph manifest metadata changed")
}
for (stage in c("tsne_cpu20", "umap_metal", "umap_cpu20",
                "umap_cpu1")) {
    fit <- fits[[stage]]
    if (fit$nrow != rows || fit$ncol != 2L) {
        stop("Layout descriptor changed: ", stage)
    }
}
leiden <- fits$leiden_cpu
if (leiden$n_vertices != rows || leiden$backend != "cpu" ||
    leiden$n_communities < 1 ||
    !is.finite(leiden$modularity_final)) {
    stop("Leiden descriptor changed")
}
out <- file.path(root, "postprocess-audit-v1")
summary <- data.frame(
    rows = rows, dimensions = 96L, neighbors = 30L,
    knn_backend = knn$backend, knn_method = knn$method,
    recall_target = 0.99,
    recall_sample_size = length(knn$audit_sample_rows),
    recall_mean = knn$observed_recall,
    recall_min = knn$minimum_row_recall,
    rows_below_target = knn$sampled_rows_below_target,
    recall_gate_pass = isTRUE(knn$sample_target_met),
    tsne_edges = affinity$n_edges, umap_edges = fuzzy$n_edges,
    leiden_communities = leiden$n_communities,
    leiden_modularity = leiden$modularity_final)
if (file.exists(file.path(out, "graph_audit.csv"))) {
    stop("Graph audit already exists")
}
write.csv(summary, file.path(out, "graph_audit.csv"),
    row.names = FALSE)
saveRDS(list(stages = stages, summary = summary,
    affinity = affinity, fuzzy = fuzzy),
    file.path(out, "graph_audit.rds"))
cat("Verified R descriptors and both graph manifests.\n")
