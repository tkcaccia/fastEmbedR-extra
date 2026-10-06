#!/usr/bin/env Rscript

library(fastEmbedR)
check_view_checkpoint <- function() {
    input <- tempfile(fileext = ".fbin")
    on.exit(unlink(input))
    values <- matrix(seq_len(48L) / 11, nrow = 12L)
    connection <- file(input, "wb")
    writeBin(as.integer(dim(values)), connection, size = 4L,
        endian = "little")
    writeBin(as.vector(t(values)), connection, size = 4L,
        endian = "little")
    close(connection)
    source <- massive_matrix(input)
    view <- fastEmbedR:::massive_matrix_rows(source, 2L, 10L)
    fastEmbedR:::massive_full_knn_controls(view, 2L, "cpu",
        "hnsw_sharded", 0L, 100L, TRUE, FALSE, "original", 0L)
    cat("Checkpointed file-backed row view: PASS\n")
}
check_view_checkpoint()
