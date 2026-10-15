#!/usr/bin/env Rscript
# Summarize and plot only transferred small-evidence files.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(1L, 2L)) {
    stop("Usage: plot_small_results.R RESULT_ROOT [PLOT_DIR]")
}
root <- normalizePath(args[[1L]], mustWork = TRUE)
out <- if (length(args) == 2L) args[[2L]] else file.path(root, "plots")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

first_row <- function(path) {
    if (!file.exists(path)) return(NULL)
    tryCatch(utils::read.csv(path, nrows = 1L), error = function(e) NULL)
}
number <- function(row, key) {
    if (is.null(row) || !key %in% names(row)) return(NA_real_)
    suppressWarnings(as.numeric(row[[key]][[1L]]))
}
files <- list.files(root, "^metrics[.]csv$", recursive = TRUE,
                    full.names = TRUE)
records <- lapply(files, function(path) {
    metrics <- first_row(path)
    if (is.null(metrics)) return(NULL)
    case_dir <- dirname(path)
    quality <- first_row(file.path(case_dir, "quality.csv"))
    gpu <- first_row(file.path(case_dir, "gpu_memory.csv"))
    dataset <- if (grepl("/turing/", path, fixed = TRUE)) "Turing" else
        if (grepl("/deep1b/", path, fixed = TRUE)) "Deep1B" else NA_character_
    data.frame(dataset = dataset,
        campaign = basename(dirname(dirname(case_dir))),
        case = basename(case_dir),
        mode = as.character(metrics$mode[[1L]]),
        backend = as.character(metrics$backend_requested[[1L]]),
        status = as.character(metrics$status[[1L]]),
        rows = number(metrics, "rows"),
        components = number(metrics, "components"),
        elapsed_seconds = number(metrics, "elapsed_seconds"),
        peak_rss_gib = number(metrics, "rss_peak_bytes") / 1024^3,
        observed_gpu_gib = number(gpu, "peak_bytes") / 1024^3,
        observed_peak_device_gib = number(gpu, "peak_device_bytes") /
            1024^3,
        observed_gpu_count = number(gpu, "device_count"),
        knn_recall_mean = number(metrics, "knn_recall_mean"),
        trustworthiness = number(quality, "trustworthiness"),
        knn_preservation_30 = number(quality, "knn_preservation_30"),
        communities = number(quality, "communities"),
        mean_confidence = number(quality, "mean_confidence"),
        plot_path = if (file.exists(file.path(case_dir,
            "plot_sample_10000.csv.gz"))) {
            file.path(case_dir, "plot_sample_10000.csv.gz")
        } else file.path(case_dir, "plot_sample.csv.gz"),
        quality_plot_path = file.path(case_dir, "plot_sample.csv.gz"),
        cluster_path = file.path(case_dir, "cluster_sample.csv.gz"),
        stringsAsFactors = FALSE)
})
records <- Filter(Negate(is.null), records)
if (!length(records)) stop("No metrics.csv found under ", root)
summary <- do.call(rbind, records)
summary <- summary[order(summary$dataset, summary$rows,
                         summary$mode, summary$backend), ]
utils::write.csv(summary[, !names(summary) %in% c("plot_path",
    "quality_plot_path", "cluster_path")],
    file.path(out, "summary.csv"), row.names = FALSE, na = "")

ok <- summary$status == "ok" & is.finite(summary$rows) &
    is.finite(summary$elapsed_seconds) & summary$elapsed_seconds > 0
colors <- c(cpu = "#24795a", cuda = "#bc4b28")
shapes <- c(pca = 16L, umap = 17L, tsne = 15L,
            knn = 18L, cluster = 8L)
pdf(file.path(out, "performance.pdf"), width = 11, height = 5)
par(mfrow = c(1, 2), mar = c(4.4, 4.7, 2.2, 1.1))
for (measure in c("elapsed_seconds", "peak_rss_gib")) {
    selected <- ok & is.finite(summary[[measure]]) & summary[[measure]] > 0
    if (!any(selected)) {
        plot.new()
        title(main = paste("No", measure, "evidence"))
        next
    }
    dat <- summary[selected, ]
    plot(dat$rows, dat[[measure]], log = "xy", xlab = "Rows fitted",
         ylab = if (measure == "elapsed_seconds") "Seconds" else
             "Peak process RSS (GiB)",
         main = if (measure == "elapsed_seconds") "Elapsed time" else
             "Observed host memory",
         col = colors[dat$backend], pch = shapes[dat$mode], cex = 0.9)
    grid(col = "#e0e0e0")
    legend("topleft", legend = names(colors), col = colors,
           pch = 16L, bty = "n")
    legend("bottomright", legend = names(shapes), pch = shapes,
           bty = "n", cex = 0.8)
}
dev.off()

plots <- summary[ok & file.exists(summary$plot_path) &
                 summary$mode %in% c("pca", "umap", "tsne"), ]
if (nrow(plots)) {
    pdf(file.path(out, "layout_samples.pdf"), width = 10, height = 10)
    par(mfrow = c(2, 2), mar = c(3.3, 3.3, 2.5, 1))
    for (i in seq_len(nrow(plots))) {
        points <- utils::read.csv(plots$plot_path[[i]])
        if (ncol(points) < 3L || !all(is.finite(points[[2L]])) ||
            !all(is.finite(points[[3L]]))) {
            plot.new()
            title(main = paste(plots$case[[i]], "invalid sample"))
            next
        }
        plot(points[[2L]], points[[3L]], pch = 16L, cex = 0.45,
             col = "#176a74", asp = 1,
             xlab = "Dimension 1", ylab = "Dimension 2",
             main = paste(plots$dataset[[i]], plots$case[[i]],
                          format(plots$rows[[i]], scientific = TRUE)))
        box()
    }
    dev.off()
}
five_million <- plots[plots$rows == 5000000, ]
if (nrow(five_million)) {
    pdf(file.path(out, "fresh5m_comparison.pdf"),
        width = 11, height = 11)
    for (dataset in unique(five_million$dataset)) {
        par(mfrow = c(3, 3), mar = c(1.3, 1.3, 2.1, 0.5),
            oma = c(0, 0, 2, 0))
        for (mode in c("pca", "umap", "tsne")) {
            for (backend in c("cpu", "cuda", "cuda2")) {
                case <- paste(backend, mode, "5m", sep = "_")
                candidates <- five_million[
                    five_million$dataset == dataset &
                    five_million$case == case, ]
                if (!nrow(candidates)) {
                    plot.new()
                    title(main = paste(toupper(mode), backend,
                                       "not available"), cex.main = 0.9)
                    next
                }
                selected <- candidates[order(candidates$campaign,
                                             decreasing = TRUE)[1L], ]
                points <- utils::read.csv(selected$plot_path)
                label <- if (backend == "cuda2") "CUDA x2 requested" else
                    toupper(backend)
                plot(points$dim1, points$dim2, pch = 16L, cex = 0.55,
                     col = "#176a74", asp = 1, axes = FALSE,
                     xlab = "", ylab = "",
                     main = paste(toupper(mode), label,
                                  sprintf("%.1f s",
                                          selected$elapsed_seconds)),
                     cex.main = 0.9)
                box(col = "#bbbbbb")
            }
        }
        mtext(paste(dataset, "- 5 million fitted rows;",
                    "512 dispersed points shown"), outer = TRUE,
              side = 3L, line = 0.4, cex = 1.05)
    }
    dev.off()
}
three_d <- plots[is.finite(plots$components) & plots$components == 3, ]
if (nrow(three_d)) {
    pdf(file.path(out, "layout_samples_3d.pdf"), width = 10, height = 10)
    par(mfrow = c(2, 2), mar = c(1.5, 1.5, 2.5, 1))
    for (i in seq_len(nrow(three_d))) {
        points <- utils::read.csv(three_d$plot_path[[i]])
        coords <- as.matrix(points[, c("dim1", "dim2", "dim3")])
        coords <- scale(coords, center = TRUE, scale = FALSE)
        magnitude <- max(abs(coords))
        if (!is.finite(magnitude) || magnitude == 0) {
            plot.new()
            next
        }
        coords <- coords / magnitude
        transform <- persp(c(-1, 1), c(-1, 1),
            matrix(c(-1, 1, 1, -1), 2, 2),
            theta = 35, phi = 25, col = NA, border = NA,
            axes = FALSE, box = FALSE,
            main = paste(three_d$dataset[[i]], three_d$case[[i]]))
        projected <- trans3d(coords[, 1L], coords[, 2L], coords[, 3L],
                             pmat = transform)
        graphics::points(projected$x, projected$y, pch = 16L,
                         col = "#176a74", cex = 0.45)
    }
    dev.off()
}
clusters <- summary[ok & summary$mode == "cluster" &
                    file.exists(summary$cluster_path), ]
if (nrow(clusters) && nrow(plots)) {
    pdf(file.path(out, "cluster_overlays.pdf"), width = 10, height = 10)
    par(mfrow = c(2, 2), mar = c(3.3, 3.3, 2.5, 1))
    for (i in seq_len(nrow(clusters))) {
        embedding <- plots[plots$dataset == clusters$dataset[[i]] &
            plots$rows == clusters$rows[[i]] &
            plots$campaign == clusters$campaign[[i]], ]
        if (!nrow(embedding)) next
        embedding <- embedding[order(embedding$mode != "umap"), ][1L, ]
        coordinates <- utils::read.csv(embedding$quality_plot_path)
        membership <- utils::read.csv(clusters$cluster_path[[i]])
        joined <- merge(coordinates, membership, by = "row_id")
        if (!nrow(joined)) next
        palette <- grDevices::hcl.colors(
            min(length(unique(joined$membership)), 32L), "Dark 3")
        group <- match(joined$membership,
                       sort(unique(joined$membership)))
        plot(joined[[2L]], joined[[3L]], col = palette[(group - 1L) %%
             length(palette) + 1L], pch = 16L, cex = 0.5, asp = 1,
             xlab = "Dimension 1", ylab = "Dimension 2",
             main = paste(clusters$dataset[[i]], clusters$case[[i]],
                          "on", embedding$mode[[1L]]))
    }
    dev.off()
}
cat("Wrote ", out, "/summary.csv and PDF plots\n", sep = "")
