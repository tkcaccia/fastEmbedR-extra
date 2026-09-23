source(file.path(dirname(script_file()), "common.R"))
args <- parse_cli(); out <- args$out_dir %||% stop("--out-dir required")
image <- args$image %||% stop("--image required"); data_root <- args$data_root %||% stop("--data-root required")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
api <- check_protocol_api(strict = FALSE)
atomic_write_csv(api$status, file.path(out, "api_capabilities.csv"))
rel <- release_info(image)
atomic_save_rds(rel, file.path(out, "release_manifest.rds"))
capture.output(sessionInfo(), file = file.path(out, "sessionInfo.txt"))
reg <- load_registry(); ds <- list()
for (i in seq_len(nrow(reg))) {
  z <- tryCatch(load_dataset(reg$dataset[[i]], reg$representation[[i]], data_root), error = identity)
  ds[[i]] <- data.frame(dataset = reg$dataset[[i]], representation = reg$representation[[i]],
    status = if (inherits(z, "error")) "failed" else "ready",
    n = if (inherits(z, "error")) NA else nrow(z$x), p = if (inherits(z, "error")) NA else ncol(z$x),
    classes = if (inherits(z, "error") || is.null(z$labels)) NA else nlevels(z$labels),
    file_sha256 = if (inherits(z, "error")) NA else z$file_sha256,
    label_sha256 = if (inherits(z, "error")) NA else z$label_sha256,
    error = if (inherits(z, "error")) conditionMessage(z) else NA_character_)
}
atomic_write_csv(do.call(rbind, ds), file.path(out, "dataset_manifest.csv"))
if (any(!api$status$available)) stop("Protocol API is incomplete. See api_capabilities.csv; full jobs were not started.")
cat("Preflight passed.\n")
