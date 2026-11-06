#!/usr/bin/env Rscript
source <- parse("convert_dataset.R")
function_expression <- Filter(function(item) is.call(item) &&
    identical(item[[1L]], as.name("<-")) &&
    identical(item[[2L]], as.name("write_f32")), source)
stopifnot(length(function_expression) == 1L)
eval(function_expression[[1L]])
path <- tempfile(fileext = ".f32")
x <- matrix(1:12, nrow = 4L)
write_f32(x, path, block_rows = 2L)
actual <- readBin(path, what = "numeric", n = 12L,
    size = 4L, endian = "little")
stopifnot(identical(actual, as.numeric(t(x))))
unlink(path)
