args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 3L)
library(fastEmbedR)

mode <- args[[1L]]
work <- args[[2L]]
out <- args[[3L]]

prepare <- function() {
    n <- as.integer(Sys.getenv("FASTEMBEDR_ROWS", "1000000"))
    columns <- 64L
    stopifnot(is.finite(n), n >= 1000L)
    path <- file.path(work, "pca_input.f32")
    con <- file(path, "wb")
    on.exit(close(con))
    set.seed(417L)
    for (first in seq.int(1L, n, by = 10000L)) {
        rows <- min(10000L, n - first + 1L)
        block <- matrix(rnorm(rows * columns), ncol = columns)
        block[, 1L] <- block[, 1L] + block[, 2L] * 2
        writeBin(as.vector(t(block)), con, size = 4L,
            endian = "little")
    }
    flush(con)
    stopifnot(file.info(path)$size == n * columns * 4)
    saveRDS(list(n = n, columns = columns),
        file.path(work, "pca_shape.rds"))
}

fit <- function() {
    stopifnot(length(args) == 6L)
    shape <- readRDS(file.path(work, "pca_shape.rds"))
    devices <- as.integer(strsplit(args[[5L]], ",",
        fixed = TRUE)[[1L]])
    label <- args[[6L]]
    input <- massive_matrix(file.path(work, "pca_input.f32"),
        shape$n, shape$columns)
    output <- file.path(work, paste0(label, ".f32"))
    started <- proc.time()[[3L]]
    result <- pca(input, ncomp = 3L, backend = "cuda",
        massive = "out_of_core", output = output,
        chunk_rows = 10000L, memory_limit = "2GB",
        devices = devices)
    seconds <- proc.time()[[3L]] - started
    fit_rows <- shape$n
    fit_ranges <- NA_character_
    fit_backend <- "single_cuda"
    fit_seconds <- fit_vram <- statistics_seconds <- NA_real_
    stopifnot(identical(result$gpu_devices, devices),
        identical(result$decomposition_backend, "cpu_eigen"),
        file.info(output)$size == shape$n * 3L * 4L)
    if (length(devices) > 1L) {
        fit_rows <- vapply(result$fit_per_device, `[[`,
            0, "rows")
        fit_seconds <- vapply(result$fit_per_device, `[[`,
            0, "seconds")
        fit_vram <- vapply(result$fit_per_device, `[[`,
            0, "estimated_vram_bytes")
        ranges <- vapply(result$fit_per_device, `[[`,
            numeric(2L), "row_range")
        bounds <- floor(seq(0, shape$n,
            length.out = length(devices) + 1L))
        expected <- rbind(head(bounds, -1L) + 1,
            tail(bounds, -1L))
        fit_ranges <- paste(apply(ranges, 2L, paste,
            collapse = "-"), collapse = ";")
        fit_backend <- result$fit_statistics_backend
        statistics_seconds <- result$fit_statistics_seconds
        stopifnot(identical(result$fit_devices, devices),
            identical(result$fit_statistics_backend,
                "distributed_cuda_covariance"),
            length(fit_rows) == length(devices),
            identical(unname(ranges), unname(expected)),
            all(fit_rows > 0), sum(fit_rows) == shape$n,
            all(is.finite(fit_seconds)),
            identical(vapply(result$resources$per_device,
                `[[`, 0L, "gpu_device"), devices))
    }
    samples <- unique(c(1L, as.integer(shape$n / 2),
        shape$n - 99L))
    sampled <- lapply(samples, function(first)
        massive_read_rows(result$scores, first, 100L))
    stopifnot(all(vapply(sampled, function(x)
        all(is.finite(x)), logical(1L))))
    saveRDS(list(samples = sampled,
        singular_values = result$singular_values),
        file.path(out, paste0(label, "_sample.rds")))
    write.csv(data.frame(method = result$method,
        devices = args[[5L]], seconds = seconds,
        rows = shape$n, output_bytes = file.info(output)$size,
        fit_backend = fit_backend,
        decomposition_backend = result$decomposition_backend,
        fit_statistics_seconds = statistics_seconds,
        fit_rows_per_device = paste(fit_rows,
            collapse = ";"),
        fit_ranges_per_device = fit_ranges,
        fit_seconds_per_device = paste(fit_seconds,
            collapse = ";"),
        fit_vram_estimate_per_device = paste(fit_vram,
            collapse = ";")),
        file.path(out, paste0(label, ".csv")), row.names = FALSE)
}

compare <- function() {
    baseline <- readRDS(file.path(out, "pca_gpu1_sample.rds"))
    for (count in c(2L, 4L)) {
        path <- file.path(out,
            sprintf("pca_gpu%d_sample.rds", count))
        if (!file.exists(path)) next
        observed <- readRDS(path)
        difference <- max(vapply(seq_along(baseline$samples),
            function(i) max(abs(baseline$samples[[i]] -
                observed$samples[[i]])), 0))
        spectrum <- max(abs(baseline$singular_values -
            observed$singular_values))
        stopifnot(is.finite(difference), difference < 1e-3,
            is.finite(spectrum), spectrum < 1e-3)
        write.csv(data.frame(devices = count,
            max_score_difference = difference,
            max_singular_value_difference = spectrum),
            file.path(out, sprintf("pca_gpu%d_comparison.csv",
                count)), row.names = FALSE)
    }
}

switch(mode, prepare = prepare(), fit = fit(),
    compare = compare(), stop("Unknown mode."))
