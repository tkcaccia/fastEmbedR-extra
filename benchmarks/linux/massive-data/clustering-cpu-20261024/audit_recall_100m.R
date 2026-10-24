args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: audit_recall_100m.R CAMPAIGN")
library(fastEmbedR)
campaign <- normalizePath(args[[1L]], mustWork = TRUE)
out <- file.path(campaign, "landmark100m_leiden")
fit <- readRDS(file.path(out, "fit.rds"))
stopifnot(fit$nrow == 1e8, fit$knn$nrow == 1e8,
    fit$knn$n_reference == 50000,
    file.info(fit$membership_path)$size == 4e8)
path <- paste0(out, "/labels.landmarks.f32")
reference <- massive_matrix(path, nrow = 50000, ncol = 96)
source <- massive_matrix(paste0(
    "/scratch/firenze/NN/Data/BigANN/deep/1000000000/",
    "base.1000000000.fbin"))
query <- fastEmbedR:::massive_matrix_rows(source, 1000001, 1e8)
audited <- massive_audit_landmark_knn(fit$knn, query, reference,
    sample_rows = 128L, memory_limit = "4GB")
settings <- audited$hnsw_settings
result <- data.frame(rows = fit$nrow, reference_rows = 50000,
    audit_rows = length(audited$audit_sample_rows),
    mean_id_recall = audited$observed_recall,
    minimum_row_id_recall = audited$minimum_row_recall,
    rows_below_target = audited$sampled_rows_below_target,
    target_recall = audited$target_recall,
    distance_equivalent_recall = audited$distance_equivalent_recall,
    audit_seconds = audited$audit_seconds, M = settings$M,
    efConstruction = settings$efConstruction,
    efSearch = settings$efSearch,
    build_threads = settings$build_threads)
write.csv(result, file.path(out, "exact_recall_audit.csv"),
    row.names = FALSE)
saveRDS(audited[c("audit_sample_rows", "observed_recall",
    "minimum_row_recall", "sampled_rows_below_target",
    "target_recall", "hnsw_settings")],
    file.path(out, "exact_recall_audit.rds"))
print(result)
