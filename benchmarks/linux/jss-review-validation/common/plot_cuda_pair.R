#!/usr/bin/env Rscript
script_arg <- commandArgs(FALSE)
script_file <- sub("^--file=", "", script_arg[
    startsWith(script_arg, "--file=")
][[1L]])
source(file.path(dirname(script_file), "common.R"))
args <- parse_cli()
dataset <- args$dataset
family <- args$family
input_root <- args[["input-root"]]
output_root <- args[["output-root"]]
plot_root <- args[["plot-root"]]
if (is.null(plot_root)) plot_root <- output_root
stopifnot(family %in% c("tsne", "umap"))
stopifnot(nzchar(dataset), nzchar(input_root), nzchar(output_root))

methods <- c(
    paste0("fastembedr_", family), paste0("cuml_", family)
)
modes <- c("r_cuda", "python_cuda")
if (family == "tsne" && Sys.getenv("INCLUDE_NOMAD") == "TRUE") {
    methods <- c(methods, "nomad")
    modes <- c(modes, "python_cuda")
}
pair_dir <- file.path(plot_root, "cuda_comparison_live", dataset, family)
dir.create(pair_dir, recursive = TRUE, showWarnings = FALSE)

read_method <- function(index) {
    path <- file.path(output_root, "workflow_comparators",
        modes[[index]], dataset, methods[[index]])
    status_file <- file.path(path, "status.csv")
    result_file <- file.path(path, "result.csv")
    scored_file <- file.path(path, "result_with_quality.csv")
    if (file.exists(scored_file)) result_file <- scored_file
    status <- if (file.exists(status_file)) {
        utils::read.csv(status_file)$status[[1L]]
    } else {
        "missing"
    }
    result <- if (identical(status, "success") &&
            file.exists(result_file)) {
        utils::read.csv(result_file, check.names = FALSE)
    } else {
        NULL
    }
    if (identical(status, "success") && is.null(result)) {
        status <- "missing_result"
    }
    list(path = path, status = status, result = result)
}

metric <- function(method, name) {
    value <- if (is.null(method$result)) NULL else method$result[[name]]
    if (length(value) == 1L) return(value)
    if (name %in% c("timing_scope", "timing_boundary")) {
        NA_character_
    } else {
        NA_real_
    }
}

read_layout <- function(method, benchmark_rows) {
    path <- file.path(method$path, "embedding.csv")
    if (!identical(method$status, "success") || !file.exists(path)) {
        return(NULL)
    }
    layout <- utils::read.csv(path)
    selected <- match(benchmark_rows$row, layout$benchmark_row)
    if (anyNA(selected) || anyDuplicated(layout$benchmark_row) ||
            nrow(layout) != nrow(benchmark_rows)) {
        stop("CUDA pair embeddings use different row sets.")
    }
    values <- as.matrix(layout[selected,
        c("dimension_1", "dimension_2")])
    if (any(!is.finite(values))) stop("Non-finite CUDA layout.")
    values
}

format_metric <- function(value, digits = 3L) {
    if (length(value) != 1L || is.na(value) || !is.finite(value)) {
        return("NA")
    }
    format(round(value, digits), trim = TRUE, nsmall = digits)
}

draw_panel <- function(method, layout, labels, heading, quality_n,
                       show_kl = TRUE) {
    graphics::par(mar = c(2.5, 0.5, 3.4, 0.5))
    if (is.null(layout)) {
        graphics::plot.new()
        graphics::title(main = heading, cex.main = 0.9)
        graphics::text(0.5, 0.5, method$status)
        return(invisible(NULL))
    }
    graphics::plot(layout[, 1L], layout[, 2L], pch = 16,
        cex = point_size(nrow(layout)), col = label_colors(labels),
        axes = FALSE, ann = FALSE, frame.plot = FALSE)
    graphics::title(main = heading, cex.main = 0.9)
    elapsed <- format_metric(metric(method, "elapsed_median_sec"), 2L)
    trust <- format_metric(metric(method, "trustworthiness"))
    preserve <- format_metric(metric(method, "preserve_at_30"))
    quality <- paste0("T=", trust, "  Preserve@30=", preserve)
    if (family == "tsne" && show_kl) {
        quality <- paste0(quality, "  compact-KL=",
            format_metric(metric(method, "sampled_kl")))
    }
    details <- paste0("n=", nrow(layout), "; quality n=", quality_n)
    graphics::mtext(paste0(elapsed, " s  |  ", quality,
        "  |  ", details), side = 1L, line = 0.5, cex = 0.75)
}

main <- function() {
    sample_file <- file.path(input_root, dataset,
        "workflow_comparators", "rows_labels.csv")
    sample <- utils::read.csv(sample_file)
    if (!nrow(sample) || !any(sample$quality_sample)) {
        stop("The benchmark rows or fixed quality sample are empty.")
    }
    results <- lapply(seq_along(methods), read_method)
    summary <- data.frame(
        dataset = dataset, family = family, method = methods,
        method_family = ifelse(methods == "nomad", "nomad", family),
        status = vapply(results, `[[`, character(1L), "status"),
        timing_scope = vapply(results, function(x) {
            as.character(metric(x, "timing_scope"))
        }, character(1L)),
        timing_boundary = vapply(results, function(x) {
            as.character(metric(x, "timing_boundary"))
        }, character(1L)),
        elapsed_median_sec = vapply(results, metric, numeric(1L),
            name = "elapsed_median_sec"),
        trustworthiness = vapply(results, metric, numeric(1L),
            name = "trustworthiness"),
        preserve_at_30 = vapply(results, metric, numeric(1L),
            name = "preserve_at_30"),
        sampled_kl = vapply(results, metric, numeric(1L),
            name = "sampled_kl"),
        quality_sample_n = sum(sample$quality_sample),
        plotted_n = nrow(sample)
    )
    summary$sampled_kl[methods == "nomad"] <- NA_real_
    write_csv_atomic(summary, file.path(pair_dir, "comparison.csv"))
    layouts <- lapply(results, read_layout, benchmark_rows = sample)
    image <- file.path(pair_dir, "comparison.png")
    grDevices::png(image, width = 1100L * length(methods),
        height = 1100L, res = 180L)
    on.exit(grDevices::dev.off(), add = TRUE)
    graphics::par(mfrow = c(1L, length(methods)))
    draw_panel(results[[1L]], layouts[[1L]], sample$label,
        "fastEmbedR CUDA (R public call)", sum(sample$quality_sample))
    draw_panel(results[[2L]], layouts[[2L]], sample$label,
        "cuML CUDA (direct Python fit)", sum(sample$quality_sample))
    if (length(methods) == 3L) {
        draw_panel(results[[3L]], layouts[[3L]], sample$label,
            "NOMAD CUDA (distinct objective)",
            sum(sample$quality_sample), show_kl = FALSE)
    }
    state <- if (all(summary$status == "success") &&
            all(vapply(layouts, Negate(is.null), logical(1L)))) {
        "success"
    } else {
        "incomplete"
    }
    write_csv_atomic(data.frame(
        dataset = dataset, family = family, status = state,
        image = image
    ), file.path(pair_dir, "status.csv"))
    if (state != "success") stop("CUDA comparison is incomplete.")
    message("CUDA comparison ready: ", image)
}

main()
