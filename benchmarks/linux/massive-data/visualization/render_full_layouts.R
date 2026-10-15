#!/usr/bin/env Rscript
# Rasterize every fitted row without inventing class labels.
args <- commandArgs(trailingOnly = TRUE)
if (!(length(args) %in% 4:6) ||
    !args[[2L]] %in% c("deep", "turing")) {
    stop("Usage: render_full_layouts.R BASE DATASET ROWS OUTPUT_DIR ",
         "[CAMPAIGN [CASE]]")
}
library(fastEmbedR)
base <- normalizePath(args[[1L]], mustWork = TRUE)
dataset <- args[[2L]]
rows <- as.numeric(args[[3L]])
out <- args[[4L]]
if (!is.finite(rows) || rows < 1000 || rows != floor(rows)) {
    stop("ROWS must be an integer of at least 1000.")
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
root <- file.path(base, "fastEmbedR-results/massive-data",
                  if (dataset == "deep") "deep1b" else "turing")
campaigns <- if (length(args) >= 5L) {
    candidate <- normalizePath(args[[5L]], mustWork = TRUE)
    if (dirname(candidate) != normalizePath(root, mustWork = TRUE)) {
        stop("The selected campaign is outside the dataset root.")
    }
    candidate
} else sort(list.dirs(root, recursive = FALSE, full.names = TRUE),
            decreasing = TRUE)
cases <- unique(unlist(lapply(campaigns, function(campaign) {
    results <- file.path(campaign, "results")
    if (!dir.exists(results)) return(character())
    names <- list.dirs(results, recursive = FALSE, full.names = FALSE)
    names[grepl("^(cpu|cuda|cuda2)_(pca|umap|tsne)_", names)]
})))
if (length(args) == 6L) {
    if (!grepl("^(cpu|cuda|cuda2)_(pca|umap|tsne)_", args[[6L]]) ||
        !args[[6L]] %in% cases) stop("Requested case is missing.")
    cases <- args[[6L]]
}
chosen <- lapply(cases, function(case) {
    for (campaign in campaigns) {
        audit_file <- file.path(campaign, "audit.json")
        if (length(args) == 6L) {
            audit_status <- "PENDING"
        } else {
            if (!file.exists(audit_file)) next
            audit <- jsonlite::fromJSON(audit_file)
            if (!(audit$status %in% c("PASS", "FAIL"))) next
            failures <- audit$failures
            if (length(failures) &&
                (any(!grepl("^[A-Za-z0-9_]+:", failures)) ||
                 any(startsWith(failures, paste0(case, ":"))))) next
            audit_status <- audit$status
        }
        path <- file.path(campaign, "results", case)
        metric_file <- file.path(path, "metrics.csv")
        layout_file <- file.path(path, "output.f32")
        if (!file.exists(metric_file) || !file.exists(layout_file)) next
        metrics <- utils::read.csv(metric_file, nrows = 1L)
        if (metrics$status[[1L]] != "ok" ||
            metrics$rows[[1L]] != rows ||
            !(metrics$components[[1L]] %in% c(2L, 3L)) ||
            file.info(layout_file)$size !=
                rows * metrics$components[[1L]] * 4) next
        return(data.frame(case = case, campaign = basename(campaign),
            first_row = metrics$first_row[[1L]],
            layout = layout_file,
            components = metrics$components[[1L]],
            devices = if ("devices" %in% names(metrics) &&
                !is.na(metrics$devices[[1L]]))
                as.character(metrics$devices[[1L]]) else "",
            campaign_audit_status = audit_status,
            stringsAsFactors = FALSE))
    }
    NULL
})
chosen <- Filter(Negate(is.null), chosen)
if (!length(chosen)) stop("No audited full layout found.")
chosen <- do.call(rbind, chosen)
width <- 1600L
height <- 1600L
pixels <- width * height
chunk <- 100000L
manifest <- list()
panels <- list()
row_label <- format(rows, big.mark = ",", scientific = FALSE,
                    trim = TRUE)
for (i in seq_len(nrow(chosen))) {
    components <- chosen$components[[i]]
    layout <- massive_matrix(chosen$layout[[i]],
                             nrow = rows, ncol = components)
    limits <- matrix(rep(c(Inf, -Inf), components),
                     nrow = components, byrow = TRUE)
    for (start in seq(1, rows, by = chunk)) {
        count <- min(chunk, rows - start + 1)
        block <- massive_read_rows(layout, first = start, n = count)
        if (!all(is.finite(block))) {
            stop("Nonfinite layout: ", chosen$case[[i]])
        }
        for (axis in seq_len(components)) {
            limits[axis, 1L] <- min(limits[axis, 1L], block[, axis])
            limits[axis, 2L] <- max(limits[axis, 2L], block[, axis])
        }
    }
    if (any(limits[, 2L] <= limits[, 1L])) {
        stop("Degenerate layout: ", chosen$case[[i]])
    }
    views <- list(xy = c(1L, 2L))
    if (components == 3L) {
        views$xz <- c(1L, 3L)
        views$yz <- c(2L, 3L)
    }
    for (view in names(views)) {
        axes <- views[[view]]
        total <- integer(pixels)
        for (start in seq(1, rows, by = chunk)) {
            count <- min(chunk, rows - start + 1)
            block <- massive_read_rows(layout, first = start, n = count)
            ix <- pmin(width, pmax(1L, as.integer(
                (block[, axes[1L]] - limits[axes[1L], 1L]) /
                diff(limits[axes[1L], ]) * (width - 1L)) + 1L))
            iy <- pmin(height, pmax(1L, as.integer(
                (block[, axes[2L]] - limits[axes[2L], 1L]) /
                diff(limits[axes[2L], ]) * (height - 1L)) + 1L))
            pixel <- (height - iy) * width + ix
            total <- total + tabulate(pixel, nbins = pixels)
        }
        if (sum(total) != rows) stop("Raster row count mismatch.")
        occupied <- total > 0L
        cap <- stats::quantile(total[occupied], 0.99, names = FALSE)
        shade <- rep(1, pixels)
        shade[occupied] <- 1 - 0.9 * pmin(1,
            log1p(total[occupied]) / log1p(max(2, cap)))
        raster <- matrix(grDevices::gray(shade), nrow = height,
                         ncol = width, byrow = TRUE)
        suffix <- if (components == 2L) "" else paste0("_", view)
        image_file <- file.path(out, paste0(chosen$case[[i]],
                                            suffix, ".png"))
        grDevices::png(image_file, width = 1800L,
                       height = 1900L, res = 150L)
        par(mar = c(1, 1, 3, 1))
        plot.new()
        plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
        graphics::rasterImage(as.raster(raster), 0, 0, 1, 1,
                              interpolate = FALSE)
        title(main = paste(dataset, chosen$case[[i]], view,
                           row_label, "points"),
              sub = paste("All rows; grayscale density;",
                  if (nzchar(chosen$devices[[i]]))
                      paste("CUDA-visible GPUs", chosen$devices[[i]])
                  else "CPU"))
        grDevices::dev.off()
        if (view == "xy" &&
            chosen$campaign_audit_status[[i]] == "PASS") {
            panels[[chosen$case[[i]]]] <- raster
        }
        manifest[[length(manifest) + 1L]] <- data.frame(
            case = chosen$case[[i]], view = view,
            campaign = chosen$campaign[[i]],
            first_row = chosen$first_row[[i]],
            devices = chosen$devices[[i]],
            campaign_audit_status = chosen$campaign_audit_status[[i]],
            rows = sprintf("%.0f", rows), plotted_rows = sum(total),
            occupied_pixels = sum(occupied),
            image = basename(image_file),
            color_semantics = "none", stringsAsFactors = FALSE)
        rm(total, shade, raster)
        gc(verbose = FALSE)
    }
}
utils::write.csv(do.call(rbind, manifest),
    file.path(out, "visual_manifest.csv"), row.names = FALSE)
figures <- list()
methods <- c(pca = "PCA", tsne = "t-SNE", umap = "UMAP")
for (backend in c("cpu", "cuda", "cuda2")) {
    cases <- vapply(names(methods), function(method) {
        hits <- grep(paste0("^", backend, "_", method, "_"),
                     names(panels), value = TRUE)
        if (length(hits) == 1L) hits else NA_character_
    }, character(1L))
    if (anyNA(cases)) next
    image <- paste0(dataset, "_", backend, "_",
                    sprintf("%.0f", rows), "_comparison.png")
    grDevices::png(file.path(out, image), width = 4800L,
                   height = 1900L, res = 300L)
    old <- par(mfrow = c(1L, 3L), mar = c(0.5, 0.5, 2.5, 0.5),
               oma = c(1, 0, 2, 0))
    for (j in seq_along(cases)) {
        plot.new()
        plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
        graphics::rasterImage(as.raster(panels[[cases[[j]]]]),
                              0, 0, 1, 1, interpolate = FALSE)
        title(main = methods[[j]], cex.main = 1.4)
    }
    mtext(paste(dataset, toupper(backend), row_label, "rows"),
          side = 3, outer = TRUE, line = 0)
    mtext("All output rows; grayscale indicates point density",
          side = 1, outer = TRUE, line = 0)
    par(old)
    grDevices::dev.off()
    figures[[length(figures) + 1L]] <- data.frame(
        dataset = dataset, backend = backend,
        rows = sprintf("%.0f", rows),
        pca = cases[["pca"]], tsne = cases[["tsne"]],
        umap = cases[["umap"]], image = image,
        color_semantics = "none", stringsAsFactors = FALSE)
}
if (length(figures)) {
    utils::write.csv(do.call(rbind, figures),
        file.path(out, "figure_manifest.csv"), row.names = FALSE)
}
cat("Rendered", length(manifest), "complete views for", dataset,
    "from", row_label, "rows.\n")
