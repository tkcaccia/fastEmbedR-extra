#!/usr/bin/env Rscript

root <- tempfile("leiden_score_")
dir.create(root)
on.exit(unlink(root, recursive = TRUE))
labels <- file.path(root, "labels.u32")
out <- file.path(root, "case")
dir.create(out)
figure <- file.path(root, "community.png")
writeBin(as.integer(rep(1:3, length.out = 2000)), labels,
    size = 4L, endian = "little")
score <- function(rows, destination = out) suppressWarnings(system2(
    "Rscript", c("score_fullgraph_leiden.R", labels, rows,
        destination, figure),
    stdout = FALSE, stderr = FALSE))
stopifnot(score(2000) == 0L,
    file.info(figure)$size > 0,
    sum(read.csv(file.path(out,
        "sample_community_counts.csv"))$sample_count) == 2000L,
    score(2001) != 0L)
lou <- file.path(root, "cuda_louvain_2000_fullgraph")
dir.create(lou)
stopifnot(score(2000, lou) == 0L,
    file.info(figure)$size > 0,
    sum(read.csv(file.path(lou,
        "sample_community_counts.csv"))$sample_count) == 2000L)
cat("Full-graph Leiden scorer: PASS\n")
