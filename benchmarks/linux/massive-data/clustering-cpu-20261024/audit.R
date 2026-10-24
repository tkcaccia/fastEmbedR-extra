args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: audit.R CAMPAIGN")
campaign <- normalizePath(args[[1L]], mustWork = TRUE)
jobs <- read.delim(file.path(campaign, "jobs.tsv"),
    stringsAsFactors = FALSE)
rows <- lapply(jobs$stage, function(stage) {
    suffix <- if (grepl("^vote", stage) ||
        stage %in% c("landmark1m", "landmark100m")) "_leiden" else ""
    out <- file.path(campaign, paste0(stage, suffix))
    metrics <- file.path(out, "metrics.csv")
    if (!file.exists(metrics)) return(data.frame(stage = stage,
        status = "INCOMPLETE", seconds = NA_real_,
        peak_rss_gib = NA_real_, workspace_peak_gib = NA_real_,
        modularity = NA_real_))
    result <- read.csv(metrics)
    stopifnot(nrow(result) == 1L,
        result$rows == if (stage == "landmark100m") 1e8 else 1e6)
    time <- file.path(out, "time.txt")
    rss <- if (file.exists(time)) {
        line <- grep("Maximum resident set size", readLines(time),
            value = TRUE)
        if (length(line) == 1L) as.numeric(sub(".*: ", "", line)) /
            1024^2 else NA_real_
    } else NA_real_
    disk <- file.path(out, "workspace_peak_bytes.txt")
    workspace <- if (file.exists(disk))
        as.numeric(readLines(disk, n = 1L)) / 1024^3 else NA_real_
    data.frame(stage = stage, status = "COMPLETE",
        seconds = result$seconds, peak_rss_gib = rss,
        workspace_peak_gib = workspace,
        modularity = result$modularity_on_matched_graph)
})
summary <- do.call(rbind, rows)
votes <- grep("^vote", summary$stage)
if (length(votes) == 4L &&
    all(summary$status[votes] == "COMPLETE")) {
    hashes <- lapply(summary$stage[votes], function(stage)
        readLines(file.path(campaign, paste0(stage, "_leiden"),
            "output.md5")))
    if (!all(vapply(hashes, identical, TRUE, hashes[[1L]])))
        stop("Worker-count vote outputs differ.")
}
write.csv(summary, file.path(campaign, "cpu_summary.csv"),
    row.names = FALSE)
print(summary, row.names = FALSE)
