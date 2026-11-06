#!/usr/bin/env Rscript

root <- tempfile("pca-gallery-")
dir.create(root)
source("analysis/gallery_pca_gate.R")
embedding_csv_path <- function(directory) {
  file.path(directory, "embedding.csv.gz")
}
inputs <- data.frame(dataset = c("COIL20", "USPS"),
                     benchmark_n = c(3L, 4L))
routes <- c(sklearn_pca = "python_cpu", cuml_pca = "python_cuda")
for (dataset in inputs$dataset) {
  count <- inputs$benchmark_n[inputs$dataset == dataset]
  for (method in names(routes)) {
    directory <- file.path(root, "workflow_comparators",
                           routes[[method]], dataset, method)
    dir.create(directory, recursive = TRUE)
    write.csv(data.frame(status = "success"),
              file.path(directory, "status.csv"), row.names = FALSE)
    write.csv(data.frame(n = count), file.path(directory, "result.csv"),
              row.names = FALSE)
    con <- gzfile(file.path(directory, "embedding.csv.gz"), "w")
    writeLines(c("benchmark_row,source_row,label,dimension_1,dimension_2",
                 sprintf("%d,%d,x,0,0", seq_len(count),
                         seq_len(count))), con)
    close(con)
  }
}
stopifnot(isTRUE(check_gallery_pca(root, inputs)))

cpu <- file.path(root, "workflow_comparators", "python_cpu",
                 "USPS", "sklearn_pca")
unlink(file.path(cpu, "embedding.csv.gz"))
stopifnot(inherits(try(check_gallery_pca(root, inputs), silent = TRUE),
                   "try-error"))
invisible(file.create(file.path(cpu, "embedding.csv.gz")))
stopifnot(inherits(try(check_gallery_pca(root, inputs), silent = TRUE),
                   "try-error"))
con <- gzfile(file.path(cpu, "embedding.csv.gz"), "w")
writeLines(c("benchmark_row,source_row,label,dimension_1,dimension_2",
             sprintf("%d,%d,x,0,0", 1:4, 1:4)), con)
close(con)

gpu <- file.path(root, "workflow_comparators", "python_cuda",
                 "COIL20", "cuml_pca")
write.csv(data.frame(status = "failed"), file.path(gpu, "status.csv"),
          row.names = FALSE)
stopifnot(inherits(try(check_gallery_pca(root, inputs), silent = TRUE),
                   "try-error"))
write.csv(data.frame(status = "success"), file.path(gpu, "status.csv"),
          row.names = FALSE)
con <- gzfile(file.path(gpu, "embedding.csv.gz"), "w")
writeLines(c("benchmark_row,source_row,label,dimension_1,dimension_2",
             sprintf("%d,%d,x,0,0", 1:2, 1:2)), con)
close(con)
stopifnot(inherits(try(check_gallery_pca(root, inputs), silent = TRUE),
                   "try-error"))
con <- gzfile(file.path(gpu, "embedding.csv.gz"), "w")
writeLines(c("benchmark_row,source_row,label,dimension_1,dimension_2",
             "1,1,\"two-line\nlabel\",0,0", "2,2,x,0,0",
             "3,3,x,0,0"), con)
close(con)
stopifnot(isTRUE(check_gallery_pca(root, inputs)))
write.csv(data.frame(n = 2L), file.path(gpu, "result.csv"),
          row.names = FALSE)
stopifnot(inherits(try(check_gallery_pca(root, inputs), silent = TRUE),
                   "try-error"))
unlink(root, recursive = TRUE)
cat("PCA gallery gate: PASS\n")
