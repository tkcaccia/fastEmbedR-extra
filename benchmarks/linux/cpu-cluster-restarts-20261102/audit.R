old <- setwd("evidence")
on.exit(setwd(old), add = TRUE)
checks <- system2("sha256sum", c("-c", "SHA256SUMS"),
                  stdout = TRUE, stderr = TRUE)
if (!is.null(attr(checks, "status"))) stop(paste(checks, collapse = "\n"))
results <- read.csv("chiamaka-mnist70k-v1/summary.csv")
stopifnot(nrow(results) == 16L,
          identical(sort(unique(results$method)), c("leiden", "louvain")),
          all(results$n_runs == 8L),
          all(results$edges == 249804L),
          all(is.finite(results$elapsed_sec)),
          all(results$elapsed_sec > 0))
for (method in c("leiden", "louvain")) {
    rows <- results[results$method == method, ]
    stopifnot(identical(rows$n.cores, c(1L, 2L, 4L, 8L,
                                      8L, 4L, 2L, 1L)),
              identical(rows$order, rep(c("forward", "reverse"),
                                        each = 4L)),
              length(unique(rows$modularity)) == 1L,
              length(unique(rows$communities)) == 1L)
    labels <- readRDS(paste0("chiamaka-mnist70k-v1/", method,
                             "_membership.rds"))
    stopifnot(length(labels) == 70000L, !anyNA(labels),
              all(labels >= 1L),
              length(unique(labels)) == rows$communities[[1L]])
}
cat("Audit passed: 16 fits, eight worker settings per method, ",
    "complete finite labels, and verified SHA256 files.\n", sep = "")
