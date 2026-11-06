deep1b_source_sha256 <-
    "1178bb266619c2d7882795861772b50cb0e2bf111a3b786a188aa3ea6137c7c4"
deep1b_row_rule <- "one-based source row i where i % 100 == 0"

deep1b_sha256 <- function(path) {
    command <- Sys.which("sha256sum")
    if (!nzchar(command)) stop("sha256sum is required for Deep1B.")
    result <- system2(command, shQuote(path), stdout = TRUE)
    if (!length(result) || !is.null(attr(result, "status"))) {
        stop("Deep1B checksum calculation failed.")
    }
    strsplit(result[[1L]], " ", fixed = TRUE)[[1L]][[1L]]
}

load_deep1b_resident <- function(root, case,
                                  expected_rows = 10000000L,
                                  expected_columns = 96L) {
    if (!requireNamespace("float", quietly = TRUE)) {
        stop("The resident Deep1B loader requires float.")
    }
    directory <- file.path(root, "BigANN", "deep", "mod100-10000000")
    path <- file.path(directory, "base.mod100.10000000.fbin")
    manifest_path <- file.path(directory, "manifest.json")
    if (!file.exists(path) || !file.exists(manifest_path)) {
        stop("The selected Deep1B 10M input is missing.")
    }
    manifest <- jsonlite::read_json(manifest_path,
        simplifyVector = TRUE)
    expected_bytes <- 8 + as.double(expected_rows) *
        expected_columns * 4
    if (!identical(case$row_rule, "source_row%100==0") ||
        !identical(manifest$selection, deep1b_row_rule) ||
        !identical(manifest$source_sha256, deep1b_source_sha256) ||
        !identical(case$source_sha256, deep1b_source_sha256) ||
        !identical(case$dataset_sha256, manifest$sha256) ||
        !identical(manifest$format, "little-endian float32 fbin") ||
        manifest$rows != expected_rows ||
        manifest$columns != expected_columns ||
        manifest$source_rows != 1000000000 ||
        manifest$bytes != expected_bytes ||
        file.info(path)$size != expected_bytes) {
        stop("Deep1B row selection, source, or dimensions changed.")
    }
    if (!identical(deep1b_sha256(path), manifest$sha256)) {
        stop("Deep1B 10M checksum changed.")
    }
    connection <- file(path, "rb")
    on.exit(close(connection))
    header <- readBin(connection, integer(), n = 2L,
        size = 4L, endian = "little")
    if (!identical(header, c(as.integer(expected_rows),
        as.integer(expected_columns)))) {
        stop("Deep1B fbin header changed.")
    }
    count <- as.integer(expected_rows * expected_columns)
    values <- readBin(connection, numeric(), n = count,
        size = 4L, endian = "little")
    if (length(values) != count) stop("Deep1B input is incomplete.")
    output <- float::fl(matrix(values, nrow = expected_rows,
        ncol = expected_columns, byrow = TRUE))
    rm(values)
    invisible(gc())
    output
}
