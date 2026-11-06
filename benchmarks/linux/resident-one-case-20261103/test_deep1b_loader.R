args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Pass the loader directory.")
source(file.path(args[[1L]], "deep1b_resident.R"))

root <- tempfile("deep1b-resident-fixture-")
directory <- file.path(root, "BigANN", "deep", "mod100-10000000")
dir.create(directory, recursive = TRUE)
path <- file.path(directory, "base.mod100.10000000.fbin")
values <- matrix(seq_len(12L) / 10, nrow = 4L, ncol = 3L)
connection <- file(path, "wb")
writeBin(c(4L, 3L), connection, size = 4L, endian = "little")
writeBin(as.vector(t(values)), connection,
    size = 4L, endian = "little")
close(connection)
sha <- deep1b_sha256(path)
manifest <- list(bytes = 56, columns = 3L,
    format = "little-endian float32 fbin", rows = 4L,
    selection = deep1b_row_rule, sha256 = sha,
    source_rows = 1000000000,
    source_sha256 = deep1b_source_sha256)
manifest_path <- file.path(directory, "manifest.json")
jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
case <- list(row_rule = "source_row%100==0",
    dataset_sha256 = sha, source_sha256 = deep1b_source_sha256)
observed <- load_deep1b_resident(root, case, 4L, 3L)
stopifnot(inherits(observed, "float32"),
    isTRUE(all.equal(float::dbl(observed), values,
        tolerance = 1e-6)))
bad_case <- case
bad_case$dataset_sha256 <- paste0("0", substring(sha, 2L))
stopifnot(inherits(try(load_deep1b_resident(root, bad_case, 4L, 3L),
    silent = TRUE), "try-error"))
manifest$selection <- "one-based source row i where i % 10 == 0"
jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE)
stopifnot(inherits(try(load_deep1b_resident(root, case, 4L, 3L),
    silent = TRUE), "try-error"))
unlink(root, recursive = TRUE)
cat("Deep1B resident loader fixture passed.\n")
