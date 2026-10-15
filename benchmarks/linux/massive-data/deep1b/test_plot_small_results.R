#!/usr/bin/env Rscript
script <- file.path(dirname(sub("^--file=", "",
    grep("^--file=", commandArgs(), value = TRUE)[[1L]])),
    "plot_small_results.R")
root <- tempfile()
case <- file.path(root, "deep1b", "campaign", "results", "cpu_umap")
dir.create(case, recursive = TRUE)
write.csv(data.frame(mode = "umap", backend_requested = "cpu",
    status = "ok", rows = 512, elapsed_seconds = 2,
    rss_peak_bytes = 1024^3, components = 3),
    file.path(case, "metrics.csv"),
    row.names = FALSE)
write.csv(data.frame(trustworthiness = 0.8,
    knn_preservation_30 = 0.4), file.path(case, "quality.csv"),
    row.names = FALSE)
stream <- gzfile(file.path(case, "plot_sample.csv.gz"), "wt")
write.csv(data.frame(row_id = seq_len(512L),
    dim1 = seq_len(512L) / 512, dim2 = sin(seq_len(512L)),
    dim3 = cos(seq_len(512L))),
    stream, row.names = FALSE)
close(stream)
five <- file.path(root, "deep1b", "campaign", "results",
                  "cpu_umap_5m")
dir.create(five)
write.csv(data.frame(mode = "umap", backend_requested = "cpu",
    status = "ok", rows = 5000000, elapsed_seconds = 12,
    rss_peak_bytes = 1024^3, components = 2),
    file.path(five, "metrics.csv"), row.names = FALSE)
stream <- gzfile(file.path(five, "plot_sample.csv.gz"), "wt")
write.csv(data.frame(row_id = seq_len(512L),
    dim1 = seq_len(512L) / 512, dim2 = sin(seq_len(512L))),
    stream, row.names = FALSE)
close(stream)
cluster <- file.path(root, "deep1b", "campaign", "results",
                     "cpu_leiden")
dir.create(cluster)
write.csv(data.frame(mode = "cluster", backend_requested = "cpu",
    status = "ok", rows = 512, elapsed_seconds = 3,
    rss_peak_bytes = 1024^3), file.path(cluster, "metrics.csv"),
    row.names = FALSE)
write.csv(data.frame(communities = 2, mean_confidence = 0.8),
    file.path(cluster, "quality.csv"), row.names = FALSE)
stream <- gzfile(file.path(cluster, "cluster_sample.csv.gz"), "wt")
write.csv(data.frame(row_id = seq_len(512L),
    membership = rep(1:2, length.out = 512L), confidence = 0.8),
    stream, row.names = FALSE)
close(stream)
output <- file.path(root, "plots")
status <- system2("Rscript", c(script, root, output),
                  stdout = TRUE, stderr = TRUE)
if (!is.null(attr(status, "status"))) cat(status, sep = "\n")
stopifnot(is.null(attr(status, "status")),
          file.exists(file.path(output, "summary.csv")),
          file.exists(file.path(output, "performance.pdf")),
          file.exists(file.path(output, "layout_samples.pdf")),
          file.exists(file.path(output, "fresh5m_comparison.pdf")),
          file.exists(file.path(output, "layout_samples_3d.pdf")),
          file.exists(file.path(output, "cluster_overlays.pdf")))
unlink(root, recursive = TRUE)
cat("plot_small_results: PASS\n")
