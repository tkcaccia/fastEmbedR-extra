#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: plot_comparison.R ROOT DATASET")
directory <- file.path(args[[1L]], args[[2L]])
cases <- read.csv(file.path(directory, "all_cases.csv"),
                  stringsAsFactors = FALSE)
cases <- cases[cases$outcome == "ok" &
               cases$mode %in% c("pca", "tsne", "umap"), , drop = FALSE]
if (!nrow(cases)) stop("No successful embedding cases to plot.")
cases$label <- paste(cases$mode, cases$route,
    ifelse(cases$backend == "cpu",
           paste0("CPU ", cases$cores),
           ifelse(cases$devices == "0,1", "2 GPU", "1 GPU")),
    sep = " | ")
cases <- cases[order(cases$mode, cases$backend,
                     cases$route, cases$cores), , drop = FALSE]
draw <- function(column, scale, label, filename, logarithmic = FALSE) {
    values <- suppressWarnings(as.numeric(cases[[column]]) / scale)
    keep <- is.finite(values) & values > 0
    if (!any(keep)) return(invisible(NULL))
    data <- cases[keep, , drop = FALSE]
    values <- values[keep]
    n <- length(values)
    grDevices::png(file.path(directory, filename), width = 2200L,
                   height = max(950L, 75L * n), res = 170L)
    on.exit(grDevices::dev.off())
    par(mar = c(5, 19, 4, 2))
    plot(values, seq_len(n), type = "n", yaxt = "n", ylab = "",
         xlab = label, ylim = c(0.5, n + 0.5),
         log = if (logarithmic) "x" else "")
    abline(h = seq_len(n), col = "#eeeeee")
    points(values, seq_len(n), pch = ifelse(data$route == "classic", 16, 17),
           col = ifelse(data$route == "classic", "#2b3b4a", "#007c67"),
           cex = 1.2)
    axis(2, at = seq_len(n), labels = data$label,
         las = 2, cex.axis = 0.8, tick = FALSE)
    title(main = paste(args[[2L]], label))
    legend("topright", c("Resident", "File-backed"),
           col = c("#2b3b4a", "#007c67"), pch = c(16, 17), bty = "n")
}
draw("wall_seconds", 1, "Wall time (seconds)",
     "comparison_time.png", logarithmic = TRUE)
draw("rss_peak_bytes", 1024^3, "Peak process RSS (GiB)",
     "comparison_rss.png")
draw("vram_peak_bytes", 1024^3, "Peak process VRAM (GiB)",
     "comparison_vram.png")
draw("trustworthiness", 1, "Trustworthiness, matched sample",
     "comparison_quality.png")
