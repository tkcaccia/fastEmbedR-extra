#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: prepare_jss_docx_source.R INPUT_TEX OUTPUT_TEX")
}
input <- normalizePath(args[[1L]], mustWork = TRUE)
root <- dirname(input)
source <- paste(readLines(input, warn = FALSE), collapse = "\n")

command_body <- function(name) {
  marker <- paste0("\\", name, "{")
  start <- regexpr(marker, source, fixed = TRUE)[[1L]]
  if (start < 0L) stop("Missing LaTeX command: ", name)
  first <- start + nchar(marker)
  depth <- 1L
  for (position in seq.int(first, nchar(source))) {
    character <- substr(source, position, position)
    if (character == "{") depth <- depth + 1L
    if (character == "}") depth <- depth - 1L
    if (depth == 0L) {
      return(substr(source, first, position - 1L))
    }
  }
  stop("Unclosed LaTeX command: ", name)
}

normalize_text <- function(text) {
  text <- gsub("\\fastEmbedR", "fastEmbedR", text, fixed = TRUE)
  for (name in c("pkg", "proglang", "code", "email")) {
    text <- gsub(
      paste0("\\", name, "{"), "\\texttt{", text, fixed = TRUE
    )
  }
  gsub("\\xspace", "", text, fixed = TRUE)
}

begin <- regexpr("\\begin{document}", source, fixed = TRUE)[[1L]]
end <- regexpr("\\end{document}", source, fixed = TRUE)[[1L]]
if (begin < 0L || end < begin) stop("Document body not found.")
body <- substr(
  source, begin + nchar("\\begin{document}"), end - 1L
)
lines <- strsplit(body, "\n", fixed = TRUE)[[1L]]
expanded <- unlist(lapply(lines, function(line) {
  match <- regmatches(line, regexec(
    "^\\\\input\\{([^}]+)\\}$", trimws(line)
  ))[[1L]]
  if (!length(match)) return(line)
  path <- file.path(root, match[[2L]])
  readLines(path, warn = FALSE)
}), use.names = FALSE)
body <- paste(expanded, collapse = "\n")
body <- gsub(
  "\\\\resizebox\\{\\\\textwidth\\}\\{!\\}\\{%?[[:space:]]*",
  "", body, perl = TRUE
)
body <- gsub(
  "\\\\end\\{tabular\\}%[[:space:]]*\\}",
  "\\\\end{tabular}", body, perl = TRUE
)
body <- gsub("L\\{[0-9.]+\\\\textwidth\\}", "l", body, perl = TRUE)
for (family in c("pca", "tsne", "umap")) {
  stem <- paste0("figures/diagnostic_runtime_", family)
  body <- gsub(paste0(stem, ".pdf"), paste0(stem, ".png"),
               body, fixed = TRUE)
}
for (name in c("cpu_scaling_comparison", "landmark_comparison")) {
  stem <- paste0("generated/secondary/", name)
  body <- gsub(paste0(stem, ".pdf"), paste0(stem, ".png"),
               body, fixed = TRUE)
}

output <- c(
  "\\documentclass{article}",
  paste0("\\title{", normalize_text(command_body("title")), "}"),
  paste0("\\author{", normalize_text(command_body("author")), "}"),
  "\\begin{document}", "\\maketitle", "\\section*{Abstract}",
  normalize_text(command_body("Abstract")),
  "\\section*{Keywords}", normalize_text(command_body("Keywords")),
  normalize_text(body), "\\end{document}"
)
writeLines(output, args[[2L]], useBytes = TRUE)
