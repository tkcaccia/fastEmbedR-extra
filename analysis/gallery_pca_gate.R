count_gallery_rows <- function(path) {
  connection <- if (grepl("\\.gz$", path)) {
    gzfile(path, "r")
  } else {
    file(path, "r")
  }
  on.exit(close(connection), add = TRUE)
  header_line <- readLines(connection, n = 1L, warn = FALSE)
  header <- names(read.csv(text = header_line, nrows = 0L,
                           check.names = FALSE))
  required <- c("benchmark_row", "source_row", "label",
                "dimension_1", "dimension_2")
  if (!all(required %in% header) || header[[1L]] != "benchmark_row") {
    stop("Invalid embedding CSV header: ", path)
  }
  fields <- count.fields(connection, sep = ",", quote = '"')
  complete <- fields[!is.na(fields)]
  if (length(fields) && is.na(tail(fields, 1L))) {
    stop("Unterminated embedding CSV row: ", path)
  }
  if (any(complete != length(header))) {
    stop("Invalid embedding CSV row width: ", path)
  }
  length(complete)
}

check_gallery_pca <- function(results_root, input_rows) {
  routes <- c(sklearn_pca = "python_cpu", cuml_pca = "python_cuda")
  failures <- character()
  for (dataset in input_rows$dataset) {
    expected <- input_rows$benchmark_n[input_rows$dataset == dataset]
    for (method in names(routes)) {
      directory <- file.path(results_root, "workflow_comparators",
                             routes[[method]], dataset, method)
      status_path <- file.path(directory, "status.csv")
      result_path <- file.path(directory, "result.csv")
      embedding <- embedding_csv_path(directory)
      if (!file.exists(status_path) || !file.exists(result_path) ||
          !file.exists(embedding) || file.info(embedding)$size == 0) {
        failures <- c(failures, paste(dataset, method, "missing output"))
        next
      }
      status <- tryCatch(read.csv(status_path), error = function(e) NULL)
      result <- tryCatch(read.csv(result_path), error = function(e) NULL)
      valid <- !is.null(status) && nrow(status) == 1L &&
        "status" %in% names(status) && status$status[[1L]] == "success" &&
        !is.null(result) && nrow(result) == 1L &&
        "n" %in% names(result) && isTRUE(result$n[[1L]] == expected)
      if (!valid) {
        failures <- c(failures, paste(dataset, method,
                                      "failed or incomplete fit"))
        next
      }
      rows <- tryCatch(count_gallery_rows(embedding),
                       error = function(e) NA_real_)
      if (!isTRUE(rows == expected)) {
        failures <- c(failures, paste(dataset, method,
                                      "incomplete coordinate rows"))
      }
    }
  }
  if (length(failures)) {
    stop("PCA gallery requires complete scikit-learn and cuML outputs: ",
         paste(failures, collapse = "; "), call. = FALSE)
  }
  invisible(TRUE)
}
