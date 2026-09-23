source(file.path(dirname(script_file()), "common.R"))
args <- parse_cli(); out <- args$out %||% file.path(suite_dir(), "cells.csv")
reg <- load_registry(); seeds <- c(4L, 17L, 42L)
common <- c("full", "no_prediction_guidance", "fixed_proposal_budget", "no_transition_proposal",
            "greedy_acceptance", "raw_cv_score")
pls_extra <- c("no_pls_transition_coarsening", "no_pls_fragmentation_penalty")
rows <- list(); add <- function(dataset, representation, classifier, experiment, setting, value, seed) {
  rows[[length(rows) + 1L]] <<- data.frame(dataset, representation, classifier, experiment,
    setting, value = as.character(value), seed, stringsAsFactors = FALSE)
}
for (i in seq_len(nrow(reg))) for (seed in seeds) {
  d <- reg$dataset[[i]]; r <- reg$representation[[i]]
  for (v in common) add(d, r, "knn", "ablation", v, NA, seed)
  for (v in c(common, pls_extra)) add(d, r, "pls_lda", "ablation", v, NA, seed)
  for (k in c(10L, 30L, 50L, 100L)) add(d, r, "knn", "knn_sensitivity", "k", k, seed)
  for (ncomp in c(5L, 10L, 20L, 50L)) add(d, r, "pls_lda", "ncomp_sensitivity", "ncomp", ncomp, seed)
  for (method in c("umap", "opentsne")) add(d, r, "classic", "classic", method, NA, seed)
}
cells <- do.call(rbind, rows); cells$cell_id <- seq_len(nrow(cells))
cells <- cells[, c("cell_id", setdiff(names(cells), "cell_id"))]
atomic_write_csv(cells, out); cat("Wrote", nrow(cells), "cells to", out, "\n")
