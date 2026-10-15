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

methods <- if (family == "umap") {
    c("fastembedr_umap", "fastembedr_umap_binary", "cuml_umap")
} else c("fastembedr_tsne", "cuml_tsne")
modes <- if (family == "umap") {
    c("r_cuda", "r_cuda", "python_cuda")
} else c("r_cuda", "python_cuda")
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
    result <- if (status %in% c("success", "invalid_fitted_kl") &&
            file.exists(result_file)) {
        utils::read.csv(result_file, check.names = FALSE)
    } else {
        NULL
    }
    if (status %in% c("success", "invalid_fitted_kl") &&
            is.null(result)) {
        status <- "missing_result"
    }
    list(path = path, status = status, result = result)
}

metric <- function(method, name) {
    value <- if (is.null(method$result)) NULL else method$result[[name]]
    if (length(value) == 1L) return(value)
    if (name %in% c("timing_scope", "timing_boundary",
            "timing_policy")) {
        NA_character_
    } else {
        NA_real_
    }
}

read_layout <- function(method, benchmark_rows) {
    path <- embedding_csv_path(method$path)
    if (!method$status %in% c("success", "invalid_fitted_kl") ||
            !file.exists(path)) {
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
    timing_note <- if (isTRUE(metric(method, "timing_eligible"))) {
        ""
    } else {
        " (unreplicated)"
    }
    trust <- format_metric(metric(method, "trustworthiness"))
    preserve <- format_metric(metric(method, "preserve_at_30"))
    score <- format_metric(metric(method,
        "neighborhood_quality_score"))
    quality <- paste0("Q=", score, "  T=", trust,
        "  Preserve@30=", preserve)
    if (family == "tsne" && show_kl) {
        quality <- paste0(quality, "  compact-KL=",
            format_metric(metric(method, "sampled_kl")))
    }
    details <- paste0("n=", nrow(layout), "; quality n=", quality_n)
    if (method$status != "success") {
        details <- paste0(details, "; ", method$status)
    }
    reps <- metric(method, "timing_reps")
    if (is.finite(reps)) details <- paste0(details, "; reps=", reps)
    graphics::mtext(paste0(elapsed, " s", timing_note, "  |  ", quality,
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
        graph_mode = if (family == "umap") {
            ifelse(methods == "fastembedr_umap_binary", "binary", "fuzzy")
        } else NA_character_,
        status = vapply(results, `[[`, character(1L), "status"),
        timing_scope = vapply(results, function(x) {
            as.character(metric(x, "timing_scope"))
        }, character(1L)),
        timing_boundary = vapply(results, function(x) {
            as.character(metric(x, "timing_boundary"))
        }, character(1L)),
        timing_policy = vapply(results, function(x) {
            as.character(metric(x, "timing_policy"))
        }, character(1L)),
        timing_reps = vapply(results, metric, numeric(1L),
            name = "timing_reps"),
        timing_eligible = vapply(results, function(x) {
            isTRUE(metric(x, "timing_eligible"))
        }, logical(1L)),
        elapsed_median_sec = vapply(results, metric, numeric(1L),
            name = "elapsed_median_sec"),
        trustworthiness = vapply(results, metric, numeric(1L),
            name = "trustworthiness"),
        preserve_at_30 = vapply(results, metric, numeric(1L),
            name = "preserve_at_30"),
        neighborhood_quality_score = vapply(results, metric,
            numeric(1L), name = "neighborhood_quality_score"),
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
    headings <- if (family == "umap") {
        c("fastEmbedR fuzzy UMAP (R public call)",
          "fastEmbedR binary UMAP (R public call)",
          "cuML UMAP (direct Python fit)")
    } else c("fastEmbedR t-SNE (R public call)",
             "cuML t-SNE (direct Python fit)")
    if (length(methods) > length(headings)) {
        headings <- c(headings, "NOMAD (distinct objective)")
    }
    for (index in seq_along(methods)) {
        draw_panel(results[[index]], layouts[[index]], sample$label,
            headings[[index]], sum(sample$quality_sample),
            show_kl = methods[[index]] != "nomad")
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
