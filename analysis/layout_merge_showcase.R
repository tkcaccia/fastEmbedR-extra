#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(fastEmbedR))

output <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1L]] else
    "manuscript/jss/figures/layout_merge_synthetic"
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)

groups <- split(seq_len(18L), rep(seq_len(3L), each = 6L))
edges <- lapply(groups, function(group) utils::combn(group, 2L))
from <- c(unlist(lapply(edges, function(edge) edge[1L, ])),
    4:6, 10:12)
to <- c(unlist(lapply(edges, function(edge) edge[2L, ])),
    7:9, 13:15)
graph <- list(from = from, to = to,
    weight = c(rep(1, length(from) - 6L), rep(0.15, 6L)),
    n_vertices = 18L)
layout <- cbind(c(seq(0, 0.25, length.out = 6L),
    seq(0.3, 0.55, length.out = 6L),
    seq(5, 5.25, length.out = 6L)),
    rep(c(-0.09, 0.06, 0.12, -0.04, 0.02, -0.07), 3L))
base <- graph_cluster(graph, method = "leiden", backend = "cpu", seed = 3L)
merged <- graph_cluster(graph, method = "leiden", backend = "cpu",
    seed = 3L, layout_merge = list(layout = layout))
stopifnot(base$n_communities == 3L, merged$n_communities == 2L,
    identical(base$membership, merged$membership_original))
utils::write.csv(merged$layout_merge_pairs,
    paste0(output, "_pairs.csv"), row.names = FALSE)

draw <- function() {
    old <- par(mfrow = c(1, 2), mar = c(3, 3, 3, 1))
    on.exit(par(old))
    palette <- c("#2274A5", "#D55E00", "#5B8C5A")
    for (item in list(base, merged)) {
        title <- if (item$n_communities == 3L) {
            "Original Leiden communities"
        } else {
            "Graph-supported layout merge"
        }
        plot(layout, col = palette[item$membership], pch = 19,
            cex = 1.5, xlab = "Layout 1", ylab = "Layout 2",
            xlim = c(-0.2, 5.5), ylim = c(-0.3, 0.3),
            main = title)
    }
}
grDevices::pdf(paste0(output, ".pdf"), width = 9, height = 3.7)
draw()
grDevices::dev.off()
grDevices::png(paste0(output, ".png"), width = 1800,
    height = 740, res = 200)
draw()
grDevices::dev.off()
