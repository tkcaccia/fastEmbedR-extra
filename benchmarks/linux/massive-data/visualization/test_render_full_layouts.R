#!/usr/bin/env Rscript
script <- file.path(dirname(sub("^--file=", "",
    grep("^--file=", commandArgs(), value = TRUE)[[1L]])),
    "render_full_layouts.R")
root <- tempfile()
dir.create(root)
set.seed(4L)
rows <- 120001L
features <- matrix(rnorm(rows * 2L), rows, 2L)
campaign <- file.path(root, "fastEmbedR-results/massive-data",
                      "deep1b", "20261010T000000Z_test")
case_dir <- file.path(campaign, "results/cpu_pca_5m")
dir.create(case_dir, recursive = TRUE)
writeLines(paste0('{"status": "FAIL", "failures": [',
    '"cpu_knn_1m: sampled KNN recall 0.95 < 0.99"]}'),
    file.path(campaign, "audit.json"))
write.csv(data.frame(status = "ok", rows = rows,
                     components = 2L, first_row = 1L),
          file.path(case_dir, "metrics.csv"), row.names = FALSE)
stream <- file(file.path(case_dir, "output.f32"), "wb")
writeBin(as.numeric(t(features[, 1:2])), stream,
         size = 4L, endian = "little")
close(stream)
three_dir <- file.path(campaign, "results/cpu_umap_5m_3d")
dir.create(three_dir)
write.csv(data.frame(status = "ok", rows = rows,
                     components = 3L, first_row = 1L),
          file.path(three_dir, "metrics.csv"), row.names = FALSE)
stream <- file(file.path(three_dir, "output.f32"), "wb")
writeBin(as.numeric(t(cbind(features, features[, 1L] +
                            features[, 2L]))), stream,
         size = 4L, endian = "little")
close(stream)
output <- file.path(root, "visuals")
result <- system2(file.path(R.home("bin"), "Rscript"),
                  c(script, root, "deep", as.character(rows), output,
                    campaign),
                  stdout = TRUE, stderr = TRUE)
if (!is.null(attr(result, "status"))) cat(result, sep = "\n")
stopifnot(is.null(attr(result, "status")))
manifest <- read.csv(file.path(output, "visual_manifest.csv"))
stopifnot(nrow(manifest) == 4L,
          all(manifest$plotted_rows == rows),
          all(manifest$campaign_audit_status == "FAIL"),
          all(manifest$color_semantics == "none"),
          setequal(manifest$view, c("xy", "xz", "yz")),
          !file.exists(file.path(output, "group_counts.csv")),
          file.exists(file.path(output, "cpu_pca_5m.png")),
          file.exists(file.path(output, "cpu_umap_5m_3d_yz.png")))
writeLines('{"status": "PASS", "failures": []}',
           file.path(campaign, "audit.json"))
tsne_dir <- file.path(campaign, "results/cpu_tsne_5m")
dir.create(tsne_dir)
write.csv(data.frame(status = "ok", rows = rows,
                     components = 2L, first_row = 1L),
          file.path(tsne_dir, "metrics.csv"), row.names = FALSE)
stream <- file(file.path(tsne_dir, "output.f32"), "wb")
writeBin(as.numeric(t(features[, 1:2])), stream,
         size = 4L, endian = "little")
close(stream)
publication <- file.path(root, "publication")
result <- system2(file.path(R.home("bin"), "Rscript"),
                  c(script, root, "deep", as.character(rows),
                    publication, campaign),
                  stdout = TRUE, stderr = TRUE)
if (!is.null(attr(result, "status"))) cat(result, sep = "\n")
stopifnot(is.null(attr(result, "status")))
figure <- read.csv(file.path(publication, "figure_manifest.csv"))
stopifnot(nrow(figure) == 1L,
          figure$pca == "cpu_pca_5m",
          figure$tsne == "cpu_tsne_5m",
          figure$umap == "cpu_umap_5m_3d",
          figure$rows == rows,
          file.info(file.path(publication, figure$image))$size > 0)
unlink(root, recursive = TRUE)
cat("render_full_layouts: PASS\n")
