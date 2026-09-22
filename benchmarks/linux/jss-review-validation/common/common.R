`%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0L) y else x
}

parse_cli <- function(args = commandArgs(trailingOnly = TRUE)) {
    out <- list()
    for (arg in args) {
        if (!startsWith(arg, "--") || !grepl("=", arg, fixed = TRUE)) next
        item <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
        out[[item[[1L]]]] <- paste(item[-1L], collapse = "=")
    }
    out
}

as_int <- function(x, default) {
    value <- suppressWarnings(as.integer(x %||% default))
    if (length(value) != 1L || is.na(value)) as.integer(default) else value
}

as_num <- function(x, default) {
    value <- suppressWarnings(as.numeric(x %||% default))
    if (length(value) != 1L || is.na(value)) as.numeric(default) else value
}

as_flag <- function(x, default = FALSE) {
    value <- tolower(as.character(x %||% default))
    value %in% c("1", "true", "yes", "y")
}

csv_values <- function(x, mode = c("character", "integer", "numeric")) {
    mode <- match.arg(mode)
    value <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
    switch(mode, integer = as.integer(value), numeric = as.numeric(value), value)
}

dataset_registry <- function(data_root) {
    data.frame(
        dataset = c(
            "COIL20", "USPS", "FashionMNIST",
            "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST",
            "imagenet", "MetRef", "mass41", "TabulaMuris",
            "Macosko2015_retina"
        ),
        file = file.path(data_root, c(
            "COIL20/COIL20_float32.RData",
            "USPS/USPS_float32.RData",
            "FashionMNIST/FashionMNIST_float32.RData",
            paste0(
                "FlowRepository_FR-FCM-ZYRM_files/",
                "van_unen_FR-FCM-ZYRM_float32.RData"
            ),
            "flow18/flow18_float32.RData",
            "MNIST/MNIST_float32.RData",
            "imagenet/imagenet_float32.RData",
            "MetRef/MetRef_float32.RData",
            "mass41/mass41_float32.RData",
            "TabulaMuris/TabulaMuris_float32.RData",
            "Macosko2015_retina/Macosko2015_retina_float32.RData"
        )),
        stringsAsFactors = FALSE
    )
}

dataset_row <- function(data_root, dataset) {
    registry <- dataset_registry(data_root)
    hit <- registry[registry$dataset == dataset, , drop = FALSE]
    if (nrow(hit) != 1L) stop("Unknown dataset: ", dataset, call. = FALSE)
    hit
}

find_dataset_object <- function(path) {
    if (!file.exists(path)) stop("Missing dataset: ", path, call. = FALSE)
    env <- new.env(parent = emptyenv())
    loaded <- load(path, envir = env)
    values <- mget(loaded, envir = env, inherits = FALSE)
    for (name in names(values)) {
        value <- values[[name]]
        if (is.list(value) && !is.null(value$data)) {
            return(list(
                data = value$data,
                labels = value$labels %||% value$tissue %||% NULL,
                object_name = name
            ))
        }
    }
    for (name in names(values)) {
        value <- values[[name]]
        valid <- is.matrix(value) || is.data.frame(value) ||
            inherits(value, "Matrix") || inherits(value, "float32")
        if (!valid) next
        labels <- NULL
        for (candidate in c("labels", "label", "tissue", "y", "Y")) {
            if (!exists(candidate, env, inherits = FALSE)) next
            observed <- get(candidate, env, inherits = FALSE)
            if (length(observed) == nrow(value)) labels <- observed
        }
        return(list(data = value, labels = labels, object_name = name))
    }
    stop("No matrix-like dataset object in ", path, call. = FALSE)
}

load_dataset <- function(data_root, dataset) {
    row <- dataset_row(data_root, dataset)
    value <- find_dataset_object(row$file[[1L]])
    if (!is.null(value$labels) && length(value$labels) != nrow(value$data)) {
        stop("Label length differs from nrow(data) for ", dataset,
            call. = FALSE
        )
    }
    value$path <- row$file[[1L]]
    value
}

as_double_matrix <- function(x) {
    if (inherits(x, "float32")) x <- float::dbl(x)
    if (inherits(x, "Matrix")) x <- as.matrix(x)
    if (is.data.frame(x)) x <- as.matrix(x)
    if (!is.matrix(x)) x <- as.matrix(x)
    storage.mode(x) <- "double"
    x
}

as_float_matrix <- function(x) {
    if (inherits(x, "float32")) return(x)
    if (!requireNamespace("float", quietly = TRUE)) {
        stop("The float package is required.", call. = FALSE)
    }
    float::fl(as_double_matrix(x))
}

layout_matrix <- function(x) {
    if (is.list(x) && !is.null(x$layout)) x <- x$layout
    if (inherits(x, "float32")) x <- float::dbl(x)
    x <- as.matrix(x)
    storage.mode(x) <- "double"
    x
}

label_colors <- function(labels, alpha = 0.75) {
    if (is.null(labels)) return(grDevices::adjustcolor("#2B6CB0", alpha))
    factor_labels <- as.factor(labels)
    palette <- grDevices::hcl.colors(nlevels(factor_labels), "Dark 3")
    grDevices::adjustcolor(palette[as.integer(factor_labels)], alpha)
}

point_size <- function(n) {
    if (n < 1000L) 0.8 else if (n < 10000L) 0.4 else 0.2
}

plot_layout_dots <- function(layout, labels, path) {
    layout <- layout_matrix(layout)
    grDevices::png(path, width = 1800, height = 1500, res = 200)
    on.exit(grDevices::dev.off(), add = TRUE)
    graphics::par(mar = rep(0.1, 4L))
    graphics::plot(
        layout[, 1L], layout[, 2L], pch = 16,
        cex = point_size(nrow(layout)), col = label_colors(labels),
        axes = FALSE, ann = FALSE, frame.plot = FALSE
    )
}

plot_transformed_queries <- function(reference, query, query_labels, path) {
    reference <- layout_matrix(reference)
    query <- layout_matrix(query)
    limits_x <- range(c(reference[, 1L], query[, 1L]), finite = TRUE)
    limits_y <- range(c(reference[, 2L], query[, 2L]), finite = TRUE)
    grDevices::png(path, width = 1800, height = 1500, res = 200)
    on.exit(grDevices::dev.off(), add = TRUE)
    graphics::par(mar = rep(0.1, 4L))
    graphics::plot(
        reference[, 1L], reference[, 2L], pch = 16,
        cex = point_size(nrow(reference)), col = "#D3D3D399",
        xlim = limits_x, ylim = limits_y,
        axes = FALSE, ann = FALSE, frame.plot = FALSE
    )
    graphics::points(
        query[, 1L], query[, 2L], pch = 16,
        cex = point_size(nrow(query)), col = label_colors(query_labels, 0.9)
    )
}

stratified_rows <- function(labels, n, size, seed) {
    size <- min(as.integer(size), as.integer(n))
    if (size >= n) return(seq_len(n))
    set.seed(as.integer(seed))
    if (is.null(labels) || length(labels) != n) {
        return(sort(sample.int(n, size)))
    }
    labels <- as.factor(labels)
    groups <- split(seq_len(n), labels, drop = TRUE)
    if (length(groups) > size) {
        chosen <- sample(
            seq_along(groups), size = size, replace = FALSE,
            prob = lengths(groups)
        )
        return(sort(vapply(groups[chosen], function(index) {
            sample(index, 1L)
        }, integer(1L))))
    }
    target <- pmax(1L, floor(size * lengths(groups) / n))
    while (sum(target) > size) {
        eligible <- which(target > 1L)
        target[eligible[[which.max(target[eligible])]]] <-
            target[eligible[[which.max(target[eligible])]]] - 1L
    }
    while (sum(target) < size) {
        capacity <- lengths(groups) - target
        eligible <- which(capacity > 0L)
        if (!length(eligible)) break
        pick <- eligible[[which.max(capacity[eligible])]]
        target[[pick]] <- target[[pick]] + 1L
    }
    rows <- unlist(Map(function(index, count) {
        sort(sample(index, min(count, length(index))))
    }, groups, target), use.names = FALSE)
    sort(rows)
}

subset_dataset <- function(dataset, rows) {
    list(
        data = dataset$data[rows, , drop = FALSE],
        labels = if (is.null(dataset$labels)) NULL else dataset$labels[rows],
        rows = as.integer(rows)
    )
}

exact_distance_matrix <- function(x) {
    x <- as_double_matrix(x)
    sq <- rowSums(x * x)
    d2 <- outer(sq, sq, "+") - 2 * tcrossprod(x)
    d2[d2 < 0] <- 0
    sqrt(d2)
}

exact_knn_from_distances <- function(distance, k) {
    n <- nrow(distance)
    k <- min(as.integer(k), n - 1L)
    diag(distance) <- Inf
    indices <- matrix(NA_integer_, n, k)
    distances <- matrix(NA_real_, n, k)
    for (i in seq_len(n)) {
        order_i <- order(distance[i, ], method = "radix")[seq_len(k)]
        indices[i, ] <- order_i
        distances[i, ] <- distance[i, order_i]
    }
    list(indices = indices, distances = distances)
}

exact_cross_knn <- function(reference, query, k, block_size = 128L) {
    reference <- as_double_matrix(reference)
    query <- as_double_matrix(query)
    k <- min(as.integer(k), nrow(reference))
    reference_sq <- rowSums(reference * reference)
    indices <- matrix(NA_integer_, nrow(query), k)
    distances <- matrix(NA_real_, nrow(query), k)
    starts <- seq.int(1L, nrow(query), by = as.integer(block_size))
    for (start in starts) {
        end <- min(nrow(query), start + block_size - 1L)
        block <- query[start:end, , drop = FALSE]
        d2 <- outer(rowSums(block * block), reference_sq, "+") -
            2 * tcrossprod(block, reference)
        d2[d2 < 0] <- 0
        for (local in seq_len(nrow(block))) {
            order_i <- order(d2[local, ], method = "radix")[seq_len(k)]
            row <- start + local - 1L
            indices[row, ] <- order_i
            distances[row, ] <- sqrt(d2[local, order_i])
        }
    }
    list(indices = indices, distances = distances)
}

exact_sampled_self_knn <- function(x, query_rows, k, block_size = 64L) {
    reference <- as_double_matrix(x)
    query_rows <- as.integer(query_rows)
    k <- min(as.integer(k), nrow(reference) - 1L)
    reference_sq <- rowSums(reference * reference)
    indices <- matrix(NA_integer_, length(query_rows), k)
    distances <- matrix(NA_real_, length(query_rows), k)
    starts <- seq.int(1L, length(query_rows), by = as.integer(block_size))
    for (start in starts) {
        end <- min(length(query_rows), start + block_size - 1L)
        selected <- query_rows[start:end]
        block <- reference[selected, , drop = FALSE]
        d2 <- outer(rowSums(block * block), reference_sq, "+") -
            2 * tcrossprod(block, reference)
        d2[d2 < 0] <- 0
        d2[cbind(seq_along(selected), selected)] <- Inf
        for (local in seq_along(selected)) {
            order_i <- order(d2[local, ], method = "radix")[seq_len(k)]
            output_row <- start + local - 1L
            indices[output_row, ] <- order_i
            distances[output_row, ] <- sqrt(d2[local, order_i])
        }
    }
    list(indices = indices, distances = distances)
}

conditional_probabilities <- function(distances, perplexity,
                                        tolerance = 1e-6,
                                        max_iter = 100L) {
    distances <- as.matrix(distances)
    n <- nrow(distances)
    k <- ncol(distances)
    target <- log(as.numeric(perplexity))
    probabilities <- matrix(0, n, k)
    beta <- numeric(n)
    iterations <- integer(n)
    for (i in seq_len(n)) {
        d2 <- pmax(as.numeric(distances[i, ]), 0)^2
        lower <- -Inf
        upper <- Inf
        current <- 1
        p <- rep.int(1 / k, k)
        for (iteration in seq_len(max_iter)) {
            p <- exp(-d2 * current)
            p[!is.finite(p)] <- 0
            total <- sum(p)
            if (!is.finite(total) || total <= .Machine$double.xmin) {
                p <- rep.int(1 / k, k)
            } else {
                p <- p / total
            }
            entropy <- -sum(p[p > 0] * log(p[p > 0]))
            delta <- entropy - target
            if (abs(delta) <= tolerance) break
            if (delta > 0) {
                lower <- current
                current <- if (is.finite(upper)) {
                    (current + upper) / 2
                } else {
                    current * 2
                }
            } else {
                upper <- current
                current <- if (is.finite(lower)) {
                    (current + lower) / 2
                } else {
                    current / 2
                }
            }
        }
        probabilities[i, ] <- p
        beta[[i]] <- current
        iterations[[i]] <- iteration
    }
    list(probabilities = probabilities, beta = beta,
        iterations = iterations)
}

affinity_summary <- function(knn, perplexity, support_multiplier) {
    width <- min(ncol(knn$indices), ceiling(perplexity * support_multiplier))
    distance <- knn$distances[, seq_len(width), drop = FALSE]
    fit <- conditional_probabilities(distance, perplexity)
    p <- fit$probabilities
    entropy <- -rowSums(ifelse(p > 0, p * log(p), 0))
    nearest_quarter <- max(1L, floor(width / 4L))
    data.frame(
        perplexity = perplexity,
        support_multiplier = support_multiplier,
        support_k = width,
        achieved_perplexity_mean = mean(exp(entropy)),
        normalized_entropy_mean = mean(entropy / log(width)),
        probability_cv_mean = mean(apply(p, 1L, function(z) {
            stats::sd(z) / mean(z)
        })),
        probability_iqr_mean = mean(apply(p, 1L, stats::IQR)),
        nearest_farthest_ratio_median = stats::median(
            p[, 1L] / p[, width]
        ),
        nearest_quarter_mass_mean = mean(rowSums(
            p[, seq_len(nearest_quarter), drop = FALSE]
        )),
        inverse_simpson_mean = mean(1 / rowSums(p * p)),
        beta_median = stats::median(fit$beta),
        search_iterations_median = stats::median(fit$iterations),
        stringsAsFactors = FALSE
    )
}

symmetrized_affinities <- function(knn, perplexity) {
    fit <- conditional_probabilities(knn$distances, perplexity)
    n <- nrow(knn$indices)
    i <- rep(seq_len(n), each = ncol(knn$indices))
    j <- as.vector(t(knn$indices))
    w <- as.vector(t(fit$probabilities))
    valid <- i != j & j >= 1L & j <= n & is.finite(w) & w > 0
    i <- i[valid]
    j <- j[valid]
    w <- w[valid]
    lo <- pmin(i, j)
    hi <- pmax(i, j)
    key <- paste0(lo, ":", hi)
    summed <- rowsum(w, key, reorder = FALSE)[, 1L]
    pieces <- strsplit(names(summed), ":", fixed = TRUE)
    edge <- data.frame(
        i = as.integer(vapply(pieces, `[[`, character(1L), 1L)),
        j = as.integer(vapply(pieces, `[[`, character(1L), 2L)),
        weight = as.numeric(summed) / (2 * n),
        stringsAsFactors = FALSE
    )
    edge$weight <- edge$weight / sum(edge$weight)
    edge
}

sampled_tsne_kl <- function(layout, knn, perplexity) {
    edge <- symmetrized_affinities(knn, perplexity)
    layout <- layout_matrix(layout)
    distance <- as.numeric(stats::dist(layout))
    q <- 1 / (1 + distance * distance)
    q <- q / sum(q)
    n <- nrow(layout)
    offset <- n * (edge$i - 1L) -
        (edge$i - 1L) * edge$i / 2L + (edge$j - edge$i)
    p <- pmax(edge$weight, .Machine$double.xmin)
    qe <- pmax(q[offset], .Machine$double.xmin)
    sum(p * log(p / qe))
}

trustworthiness_from_distances <- function(high, low, k) {
    n <- nrow(high)
    k <- min(as.integer(k), n - 1L)
    high_order <- t(apply(high, 1L, order))[, -1L, drop = FALSE]
    low_order <- t(apply(low, 1L, order))[, -1L, drop = FALSE]
    penalty <- 0
    for (i in seq_len(n)) {
        high_k <- high_order[i, seq_len(k)]
        low_k <- low_order[i, seq_len(k)]
        intrusions <- setdiff(low_k, high_k)
        if (length(intrusions)) {
            ranks <- match(intrusions, high_order[i, ])
            penalty <- penalty + sum(ranks - k)
        }
    }
    1 - 2 * penalty / (n * k * (2 * n - 3 * k - 1))
}

neighbor_preservation <- function(high_knn, low_knn, k) {
    k <- min(k, ncol(high_knn), ncol(low_knn))
    mean(vapply(seq_len(nrow(high_knn)), function(i) {
        length(intersect(high_knn[i, seq_len(k)],
            low_knn[i, seq_len(k)])) / k
    }, numeric(1L)))
}

majority_label_accuracy <- function(indices, labels, k) {
    if (is.null(labels)) return(NA_real_)
    labels <- as.character(labels)
    k <- min(k, ncol(indices))
    predicted <- vapply(seq_len(nrow(indices)), function(i) {
        vote <- table(labels[indices[i, seq_len(k)]])
        names(vote)[which.max(vote)]
    }, character(1L))
    mean(predicted == labels)
}

query_label_accuracy <- function(indices, reference_labels, query_labels, k) {
    if (is.null(reference_labels) || is.null(query_labels)) return(NA_real_)
    reference_labels <- as.character(reference_labels)
    query_labels <- as.character(query_labels)
    k <- min(k, ncol(indices))
    predicted <- vapply(seq_len(nrow(indices)), function(i) {
        vote <- table(reference_labels[indices[i, seq_len(k)]])
        names(vote)[which.max(vote)]
    }, character(1L))
    mean(predicted == query_labels)
}

quality_metrics <- function(x, layout, labels, perplexity, support_multiplier,
                            k = 30L) {
    x <- as_double_matrix(x)
    layout <- layout_matrix(layout)
    high_distance <- exact_distance_matrix(x)
    low_distance <- exact_distance_matrix(layout)
    max_support <- min(nrow(x) - 1L, ceiling(perplexity * support_multiplier))
    high_knn <- exact_knn_from_distances(high_distance, max(k, max_support))
    low_knn <- exact_knn_from_distances(low_distance, k)
    support_knn <- list(
        indices = high_knn$indices[, seq_len(max_support), drop = FALSE],
        distances = high_knn$distances[, seq_len(max_support), drop = FALSE]
    )
    data.frame(
        trustworthiness = trustworthiness_from_distances(
            high_distance, low_distance, k
        ),
        preserve_at_30 = neighbor_preservation(
            high_knn$indices, low_knn$indices, k
        ),
        label_knn_accuracy = majority_label_accuracy(
            low_knn$indices, labels, k
        ),
        sampled_kl = sampled_tsne_kl(layout, support_knn, perplexity),
        stringsAsFactors = FALSE
    )
}

procrustes_correlation <- function(reference, candidate) {
    x <- scale(layout_matrix(reference), center = TRUE, scale = FALSE)
    y <- scale(layout_matrix(candidate), center = TRUE, scale = FALSE)
    sv <- svd(crossprod(y, x))
    aligned <- y %*% (sv$u %*% t(sv$v))
    stats::cor(as.vector(x), as.vector(aligned))
}

layout_neighbor_agreement <- function(reference, candidate, k = 30L) {
    reference <- layout_matrix(reference)
    candidate <- layout_matrix(candidate)
    ref_knn <- exact_knn_from_distances(exact_distance_matrix(reference), k)
    can_knn <- exact_knn_from_distances(exact_distance_matrix(candidate), k)
    neighbor_preservation(ref_knn$indices, can_knn$indices, k)
}

principal_angle_summary <- function(reference, candidate) {
    reference <- as_double_matrix(reference)
    candidate <- as_double_matrix(candidate)
    rank <- min(ncol(reference), ncol(candidate))
    qr_ref <- qr.Q(qr(reference))[, seq_len(rank), drop = FALSE]
    qr_can <- qr.Q(qr(candidate))[, seq_len(rank), drop = FALSE]
    singular <- svd(crossprod(qr_ref, qr_can), nu = 0, nv = 0)$d
    angles <- acos(pmin(1, pmax(-1, singular)))
    data.frame(
        max_principal_angle_rad = max(angles),
        mean_principal_angle_rad = mean(angles),
        subspace_cosine_mean = mean(singular),
        stringsAsFactors = FALSE
    )
}

write_csv_atomic <- function(x, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    temporary <- paste0(path, ".tmp.", Sys.getpid())
    utils::write.csv(x, temporary, row.names = FALSE, na = "")
    if (!file.rename(temporary, path)) {
        file.copy(temporary, path, overwrite = TRUE)
        unlink(temporary)
    }
    invisible(path)
}

bind_rows_union <- function(rows) {
    rows <- Filter(function(x) !is.null(x) && nrow(x) > 0L, rows)
    if (!length(rows)) return(data.frame())
    columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
    normalized <- lapply(rows, function(x) {
        for (name in setdiff(columns, names(x))) x[[name]] <- NA
        x[columns]
    })
    do.call(rbind, normalized)
}

append_csv_locked <- function(x, path) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    lock <- paste0(path, ".lock")
    for (attempt in seq_len(600L)) {
        if (dir.create(lock, showWarnings = FALSE)) break
        Sys.sleep(0.1)
    }
    if (!dir.exists(lock)) stop("Could not acquire CSV lock: ", path)
    on.exit(unlink(lock, recursive = TRUE), add = TRUE)
    existing <- if (file.exists(path)) {
        utils::read.csv(path, stringsAsFactors = FALSE)
    } else {
        NULL
    }
    combined <- if (is.null(existing)) x else {
        columns <- union(names(existing), names(x))
        for (name in setdiff(columns, names(existing))) existing[[name]] <- NA
        for (name in setdiff(columns, names(x))) x[[name]] <- NA
        rbind(existing[columns], x[columns])
    }
    write_csv_atomic(combined, path)
}

package_identity <- function(image = NA_character_) {
    package_path <- find.package("fastEmbedR")
    dll <- getLoadedDLLs()[["fastEmbedR"]][["path"]]
    image_sha256 <- Sys.getenv("FASTEMBEDR_IMAGE_SHA256", "")
    if (!nzchar(image_sha256)) {
        image_sha256 <- if (!is.na(image) && file.exists(image)) {
            sha256_file(image)
        } else {
            NA_character_
        }
    }
    data.frame(
        timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
        package_version = as.character(utils::packageVersion("fastEmbedR")),
        package_path = package_path,
        dll_path = dll,
        dll_sha256 = sha256_file(dll),
        image = image,
        image_sha256 = image_sha256,
        R_version = R.version.string,
        R_executable = file.path(R.home("bin"), "R"),
        R_home = R.home(),
        R_library_paths = paste(.libPaths(), collapse = ";"),
        platform = R.version$platform,
        stringsAsFactors = FALSE
    )
}

sha256_file <- function(path) {
    if (!file.exists(path)) return(NA_character_)
    command <- if (nzchar(Sys.which("sha256sum"))) {
        c("sha256sum", shQuote(path))
    } else {
        c("shasum", "-a", "256", shQuote(path))
    }
    output <- tryCatch(
        system2(command[[1L]], command[-1L], stdout = TRUE, stderr = TRUE),
        error = function(error) character()
    )
    if (!length(output)) return(NA_character_)
    strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

assert_backend <- function(backend) {
    capabilities <- fastEmbedR::fastEmbedR_capabilities()
    row <- capabilities[capabilities$backend == backend, , drop = FALSE]
    usable <- nrow(row) == 1L && isTRUE(row$knn_available[[1L]]) &&
        isTRUE(row$embedding_available[[1L]])
    if (!usable) {
        stop(backend, " was requested but its KNN and embedding components ",
            "are not both available; no fallback is allowed.", call. = FALSE
        )
    }
    invisible(capabilities)
}

assert_layout_backend <- function(layout, backend) {
    raw <- if (is.list(layout) && !is.null(layout$layout)) {
        layout$layout
    } else {
        layout
    }
    config <- attr(raw, "fastEmbedR_config", exact = TRUE)
    parameter_backend <- if (is.list(layout)) {
        layout$parameters$backend
    } else {
        NULL
    }
    observed <- attr(raw, "backend", exact = TRUE) %||%
        parameter_backend %||% config$backend
    if (is.null(observed) || !nzchar(as.character(observed))) {
        stop(
            "The embedding did not report its executed backend; ",
            "backend validation cannot pass.",
            call. = FALSE
        )
    }
    if (!grepl(backend, observed, fixed = TRUE)) {
        stop("Requested backend ", backend, " but observed ", observed,
            call. = FALSE
        )
    }
    invisible(observed)
}

status_row <- function(experiment, dataset, backend, status,
                       error = NA_character_, ...) {
    data.frame(
        timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
        experiment = experiment,
        dataset = dataset,
        backend = backend,
        status = status,
        error = error,
        ...,
        stringsAsFactors = FALSE
    )
}
