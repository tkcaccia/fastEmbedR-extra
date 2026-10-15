#!/usr/bin/env Rscript
script <- file.path(dirname(sub("^--file=", "",
    grep("^--file=", commandArgs(), value = TRUE)[[1L]])),
    "score_cluster.R")
root <- tempfile()
dir.create(root)
prefix <- file.path(root, "output")
labels <- rep(c(1L, 2L), length.out = 512L)
scores <- rep(c(0.25, 0.75), length.out = 512L)
connection <- file(paste0(prefix, ".clusters.u32"), "wb")
writeBin(labels, connection, size = 4L, endian = "little")
close(connection)
connection <- file(paste0(prefix, ".confidence.f32"), "wb")
writeBin(scores, connection, size = 4L, endian = "little")
close(connection)
stream <- gzfile(file.path(root, "landmark_labels.csv.gz"), "wt")
write.csv(data.frame(row_id = 1000000 + c(1, 2, 512),
    membership = labels[c(1, 2, 512)]), stream, row.names = FALSE)
close(stream)
status <- system2("Rscript", c(script, prefix, "512", root, "1000001"),
                  stdout = TRUE, stderr = TRUE)
stopifnot(is.null(attr(status, "status")))
quality <- read.csv(file.path(root, "quality.csv"))
sample <- read.csv(file.path(root, "cluster_sample.csv.gz"))
stopifnot(quality$scanned_rows == 512,
          quality$communities == 2,
          quality$landmarks_checked == 3,
          quality$landmark_label_mismatches == 0,
          quality$mean_confidence == 0.5,
          sample$row_id[[1L]] == 1000001,
          sample$row_id[[512L]] == 1000512)
unlink(root, recursive = TRUE)
cat("score_cluster: PASS\n")
