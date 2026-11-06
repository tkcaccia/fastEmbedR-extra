global_knn_rows <- function(n, count, seed = 105L) {
  if (n <= 1L || count < 1L) stop("Invalid global KNN sample size")
  set.seed(seed)
  sort(sample.int(n, min(n, count)))
}

global_knn_expected_input <- function(path) {
  expected_path <- Sys.getenv("FASTEMBEDR_MAC_EXPECTED_INPUT_PATH")
  expected_hash <- Sys.getenv("FASTEMBEDR_MAC_EXPECTED_INPUT_SHA256")
  if (!nzchar(expected_path) ||
      !grepl("^[0-9a-f]{64}$", expected_hash) ||
      is.na(path) ||
      !identical(normalizePath(path, mustWork = TRUE),
                 normalizePath(expected_path, mustWork = TRUE))) {
    stop("Worker input differs from verified Mac preflight input")
  }
  expected_hash
}

global_knn_validate <- function(indices, rows, n, k) {
  if (!is.matrix(indices) || !is.numeric(indices) ||
      nrow(indices) != length(rows) ||
      ncol(indices) != k || anyNA(indices) ||
      any(indices < 1L | indices > n) ||
      any(indices != floor(indices))) {
    stop("Invalid sampled global KNN indices")
  }
  for (i in seq_along(rows)) {
    if (rows[[i]] %in% indices[i, ] ||
        anyDuplicated(indices[i, ])) {
      stop("Global KNN sample contains self or duplicate neighbors")
    }
  }
  invisible(TRUE)
}

global_knn_exact_reference <- function(x, rows, k, threads, dataset,
                                       input_sha256) {
  n <- nrow(x)
  query <- x[rows, , drop = FALSE]
  result <- fastEmbedR:::native_exact_query_cpp(
    x, query, k + 1L, threads, "euclidean", 1.0
  )
  indices <- t(vapply(seq_along(rows), function(i) {
    found <- result$indices[i, ]
    found <- found[found != rows[[i]]]
    if (length(found) < k) stop("Exact query omitted neighbors")
    as.integer(found[seq_len(k)])
  }, integer(k)))
  global_knn_validate(indices, rows, n, k)
  list(dataset = dataset, n = n, p = ncol(x), k = k,
       rows = rows, indices = indices,
       input_sha256 = input_sha256,
       engine = "native_cpu_exact_query_global")
}

global_knn_capture <- function(knn, reference, method, threads, seed) {
  indices <- knn$indices
  if (!is.matrix(indices) || nrow(indices) != reference$n ||
      ncol(indices) < reference$k) {
    stop("Full-run KNN output is unavailable for recall audit")
  }
  sampled <- indices[reference$rows, seq_len(reference$k), drop = FALSE]
  global_knn_validate(sampled, reference$rows, reference$n, reference$k)
  list(dataset = reference$dataset, n = reference$n,
       p = reference$p, k = reference$k, rows = reference$rows,
       input_sha256 = reference$input_sha256, indices = sampled,
       method = method, threads = threads, seed = seed)
}

global_knn_score <- function(reference, candidate) {
  fields <- c("dataset", "n", "p", "k", "rows",
              "input_sha256")
  if (!all(vapply(fields, function(field) {
    identical(reference[[field]], candidate[[field]])
  }, logical(1L)))) stop("Global KNN reference identity changed")
  global_knn_validate(reference$indices, reference$rows,
                      reference$n, reference$k)
  global_knn_validate(candidate$indices, candidate$rows,
                      candidate$n, candidate$k)
  recall <- vapply(seq_along(reference$rows), function(i) {
    sum(candidate$indices[i, ] %in% reference$indices[i, ]) /
      reference$k
  }, numeric(1L))
  list(mean = mean(recall), minimum = min(recall),
       pass = mean(recall) >= 0.99 && min(recall) >= 0.90,
       rows = length(recall))
}
