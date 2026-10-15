#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
source(file.path(dirname(script), "reclaim_fullgraph_storage.R"))
root <- tempfile("fullgraph_reclaim_")
dir.create(root)
dir.create(file.path(root, "work"))
on.exit(unlink(root, recursive = TRUE))
work <- file.path(root, "work")
files <- c("affinity.offsets.u64", "affinity.indices.u32",
    "affinity.weights.f32", "affinity.affinity.rds",
    "tsne_init.f32", "knn.distances.f32", "knn.indices.u32",
    "knn.weights.f32", "fuzzy.offsets.u64")
for (name in files) writeBin(as.raw(1:8), file.path(work, name))
writeBin(as.raw(1:8), file.path(root, "final.f32"))

stopifnot(identical(deep1b_reclaim_files(root, "tsne"), 40))
stopifnot(identical(deep1b_reclaim_files(root, "memberships"), 8))
stopifnot(identical(deep1b_reclaim_files(root, "fuzzy"), 16))
ledger <- read.csv(file.path(root, "reclaimed_payloads.csv"))
stopifnot(nrow(ledger) == 8L, sum(ledger$bytes) == 64,
    identical(as.character(ledger$stage), c(rep("tsne", 5L),
        "memberships", rep("fuzzy", 2L))),
    file.exists(file.path(work, "fuzzy.offsets.u64")),
    file.exists(file.path(root, "final.f32")),
    !file.exists(file.path(work, "knn.distances.f32")))

writeBin(as.raw(1:8), file.path(work, "knn.indices.u32"))
error <- tryCatch(deep1b_reclaim_files(root, "fuzzy"),
    error = conditionMessage)
stopifnot(grepl("missing", error, fixed = TRUE),
    file.exists(file.path(work, "knn.indices.u32")))
writeBin(as.raw(1:8), file.path(work, "knn.distances.f32"))
stopifnot(identical(deep1b_reclaim_files(root, "fuzzy_bucketed"), 16))
stopifnot(!file.exists(file.path(work, "knn.indices.u32")),
    !file.exists(file.path(work, "knn.distances.f32")),
    file.exists(file.path(work, "fuzzy.offsets.u64")))
for (name in c("knn.indices.u32", "knn.distances.f32")) {
    writeBin(as.raw(1:8), file.path(work, name))
}
stopifnot(identical(deep1b_reclaim_files(root, "tsne_only_knn"), 16))
stopifnot(!file.exists(file.path(work, "knn.indices.u32")),
    !file.exists(file.path(work, "knn.distances.f32")),
    file.exists(file.path(root, "final.f32")))
stopifnot(identical(deep1b_record_consumed_knn(root,
    "fuzzy_bucketed", list(consumed_knn_bytes = 16)), 16))
ledger <- read.csv(file.path(root, "reclaimed_payloads.csv"))
stopifnot(identical(tail(as.character(ledger$stage), 2L),
    rep("fuzzy_bucketed", 2L)),
    all(tail(ledger$bytes, 2L) == 8))
for (name in c("fuzzy.indices.u32", "fuzzy.weights.f32",
    "fuzzy.fuzzy.rds")) {
    writeBin(as.raw(1:8), file.path(work, name))
}
stopifnot(identical(deep1b_reclaim_files(root, "fuzzy_graph"), 32))
ledger <- read.csv(file.path(root, "reclaimed_payloads.csv"))
stopifnot(identical(tail(as.character(ledger$stage), 4L),
    rep("fuzzy_graph", 4L)),
    all(tail(ledger$bytes, 4L) == 8),
    !any(file.exists(file.path(work, c("fuzzy.offsets.u64",
        "fuzzy.indices.u32", "fuzzy.weights.f32", "fuzzy.fuzzy.rds")))),
    file.exists(file.path(root, "final.f32")))
writeBin(as.raw(1:8), file.path(work, "fuzzy.offsets.u64"))
error <- tryCatch(deep1b_reclaim_files(root, "fuzzy_graph"),
    error = conditionMessage)
stopifnot(grepl("missing", error, fixed = TRUE),
    file.exists(file.path(work, "fuzzy.offsets.u64")))
labels <- file.path(work, "leiden_labels.u32")
writeBin(as.raw(1:8), labels)
levels <- c("leiden_labels.u32.level0.coarse.edges.bin",
    "leiden_labels.u32.level0.csr.indices.u32",
    "leiden_labels.u32.level0.refined.u32.parent.u32")
for (name in levels) writeBin(as.raw(1:8), file.path(work, name))
unknown <- file.path(work, "leiden_labels.u32.level0.unknown")
writeBin(as.raw(1:8), unknown)
error <- tryCatch(deep1b_reclaim_files(root, "leiden_work"),
    error = conditionMessage)
stopifnot(grepl("Unknown Leiden", error, fixed = TRUE),
    all(file.exists(file.path(work, levels))))
unlink(unknown)
stopifnot(identical(deep1b_reclaim_files(root, "leiden_work"), 24),
    file.exists(labels),
    !any(file.exists(file.path(work, levels))),
    identical(deep1b_reclaim_files(root, "leiden_work"), 0))
cat("Full-graph stage reclaim: PASS\n")
