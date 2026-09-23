#!/usr/bin/env Rscript

# Write a reproducibility bundle for manuscript and benchmark runs.
# The script is intentionally small and dependency-light. If jsonlite is
# installed, it also writes a JSON manifest; otherwise it writes text files.

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x)) y else x

parse_args <- function(args) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    kv <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[gsub("-", "_", kv[[1L]])]] <- if (length(kv) > 1L) paste(kv[-1L], collapse = "=") else TRUE
  }
  out
}

run_cmd <- function(command, args = character()) {
  path <- Sys.which(command)
  if (!nzchar(path)) return(NA_character_)
  out <- tryCatch(
    system2(path, args, stdout = TRUE, stderr = TRUE),
    warning = function(w) conditionMessage(w),
    error = function(e) conditionMessage(e)
  )
  paste(out, collapse = "\n")
}

git_value <- function(args) {
  out <- run_cmd("git", args)
  if (length(out) != 1L || is.na(out)) NA_character_ else trimws(out)
}

pkg_version <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) return(NA_character_)
  as.character(utils::packageVersion(pkg))
}

backend_capture <- function() {
  if (!requireNamespace("fastEmbedR", quietly = TRUE)) {
    return("fastEmbedR not installed")
  }
  paste(
    capture.output(print(try(
      fastEmbedR::fastEmbedR_capabilities(), silent = TRUE
    ))),
    collapse = "\n"
  )
}

python_versions <- function(python) {
  packages <- c("openTSNE", "umap-learn", "cuml")
  if (!nzchar(python)) return(setNames(rep(NA_character_, 3L), packages))
  code <- paste(
    "import importlib, importlib.metadata as m",
    "items=[('openTSNE','openTSNE',['openTSNE']),",
    "       ('umap-learn','umap',['umap-learn']),",
    "       ('cuml','cuml',['cuml','cuml-cu12','cuml-cu13'])]",
    "for label,module,dists in items:",
    "  v='NA'",
    "  for d in dists:",
    "    try: v=m.version(d); break",
    "    except m.PackageNotFoundError: pass",
    "  if v=='NA':",
    "    try: v=str(getattr(importlib.import_module(module),'__version__','NA'))",
    "    except Exception: pass",
    "  print(label+'='+v)", sep = "\n"
  )
  output <- tryCatch(
    system2(python, c("-c", shQuote(code)), stdout = TRUE, stderr = FALSE),
    error = function(...) character()
  )
  values <- setNames(rep(NA_character_, length(packages)), packages)
  for (line in output) {
    fields <- strsplit(line, "=", fixed = TRUE)[[1L]]
    if (length(fields) >= 2L && fields[[1L]] %in% packages) {
      values[[fields[[1L]]]] <- paste(fields[-1L], collapse = "=")
    }
  }
  values
}

sha256_file <- function(path) {
  if (!nzchar(path) || !file.exists(path)) return(NA_character_)
  command <- Sys.which("sha256sum")
  arguments <- path
  if (!nzchar(command)) {
    command <- Sys.which("shasum")
    arguments <- c("-a", "256", path)
  }
  if (!nzchar(command)) return(NA_character_)
  output <- system2(command, arguments, stdout = TRUE, stderr = FALSE)
  status <- attr(output, "status")
  if ((!is.null(status) && status != 0L) || !length(output)) {
    return(NA_character_)
  }
  strsplit(trimws(output[[1L]]), "[[:space:]]+")[[1L]][[1L]]
}

fitsne_identity <- function() {
  executable_candidates <- c(
    Sys.getenv("FAST_TSNE_BIN", unset = ""),
    "/opt/fit-sne/bin/fast_tsne",
    "/mnt/sata_ssd/FIt-SNE/bin/fast_tsne"
  )
  executable <- executable_candidates[
    nzchar(executable_candidates) & file.exists(executable_candidates)
  ]
  executable <- if (length(executable)) executable[[1L]] else ""
  source_dirs <- c(
    "/opt/fit-sne-src", "/opt/fit-sne", "/opt/FIt-SNE",
    "/mnt/sata_ssd/FIt-SNE"
  )
  commit <- NA_character_
  for (source_dir in source_dirs) {
    if (!dir.exists(file.path(source_dir, ".git"))) next
    value <- tryCatch(
      suppressWarnings(system2(
        "git", c("-C", source_dir, "rev-parse", "HEAD"),
        stdout = TRUE, stderr = FALSE
      )),
      error = function(...) character()
    )
    if (length(value) && grepl("^[0-9a-f]{40}$", value[[1L]])) {
      commit <- value[[1L]]
      break
    }
  }
  checksum <- sha256_file(executable)
  list(
    value = if (!is.na(commit)) commit else if (!is.na(checksum)) {
      paste0("sha256:", checksum)
    } else NA_character_,
    type = if (!is.na(commit)) "Git commit" else "Executable SHA-256",
    executable = executable,
    sha256 = checksum
  )
}

repr <- function(x) {
  paste0("[", paste(sprintf("'%s'", x), collapse = ","), "]")
}

r_config <- function(key) {
  run_cmd(file.path(R.home("bin"), "R"), c("CMD", "config", key))
}

read_text_file <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

compiler_probe <- function() {
  list(
    r_cc = r_config("CC"),
    r_cflags = r_config("CFLAGS"),
    r_cxx17 = r_config("CXX17"),
    r_cxx17flags = r_config("CXX17FLAGS"),
    r_cppflags = r_config("CPPFLAGS"),
    r_ldflags = r_config("LDFLAGS"),
    r_shlib_cxx17ld = r_config("SHLIB_CXX17LD"),
    cc_version = run_cmd("cc", "--version"),
    cxx_version = run_cmd("c++", "--version"),
    clang_version = run_cmd("clang++", "--version"),
    gcc_version = run_cmd("g++", "--version"),
    xcode_version = run_cmd("xcodebuild", "-version"),
    macos_sdk_path = run_cmd("xcrun", c("--sdk", "macosx", "--show-sdk-path")),
    macos_sdk_version = run_cmd("xcrun", c("--sdk", "macosx", "--show-sdk-version")),
    metal_compiler = run_cmd("xcrun", c("--find", "metal")),
    metal_version = run_cmd("xcrun", c("metal", "--version")),
    generated_makevars = read_text_file(file.path("src", "Makevars")),
    environment = as.list(Sys.getenv(
      c(
        "CC", "CXX", "CXX17", "CFLAGS", "CXXFLAGS", "CXX17FLAGS",
        "CPPFLAGS", "LDFLAGS", "MAKEFLAGS", "SDKROOT", "DEVELOPER_DIR",
        "CUDA_HOME", "NVCC",
        "CUDAHOSTCXX", "FASTEMBEDR_USE_CUDA", "FASTEMBEDR_USE_FAISS_GPU",
        "FASTEMBEDR_USE_CUVS", "FASTEMBEDR_USE_RAFT",
        "FASTEMBEDR_CUDA_ARCH", "FASTEMBEDR_CUDA_FLAGS"
      ),
      unset = NA_character_
    ))
  )
}

cuda_probe <- function() {
  list(
    nvidia_smi = run_cmd(
      "nvidia-smi",
      c("--query-gpu=name,driver_version,memory.total,compute_cap", "--format=csv,noheader")
    ),
    nvidia_smi_full = run_cmd("nvidia-smi"),
    nvcc_version = run_cmd("nvcc", "--version"),
    cuda_home = Sys.getenv("CUDA_HOME", unset = NA_character_),
    ld_library_path = Sys.getenv("LD_LIBRARY_PATH", unset = NA_character_),
    fastEmbedR_cuda_knn_available = if (requireNamespace("fastEmbedR", quietly = TRUE)) {
      paste(
        capture.output(print(try(
          fastEmbedR:::native_cuda_knn_available_cpp(),
          silent = TRUE
        ))),
        collapse = "\n"
      )
    } else {
      "fastEmbedR not installed"
    },
    fastEmbedR_cuda_embedding_available = if (requireNamespace("fastEmbedR", quietly = TRUE)) {
      paste(
        capture.output(print(try(
          fastEmbedR:::embedding_cuda_available_cpp(),
          silent = TRUE
        ))),
        collapse = "\n"
      )
    } else {
      "fastEmbedR not installed"
    }
  )
}

benchmark_commands <- function(seed, k, perplexity, threads_cpu, timeout) {
  list(
    github_mnist70k_example = paste(
      "Rscript tools/benchmark_github_mnist70k.R",
      "--n=70000",
      paste0("--k=", k),
      paste0("--perplexity=", perplexity),
      paste0("--threads=", threads_cpu),
      "--run-metal=true",
      "--run-cuda=false",
      "--run-references=true",
      paste0("--out-dir=results/mnist70k_github_benchmark_seed", seed)
    ),
    reference_validation = paste(
      "Rscript tools/validate_reference_implementations.R",
      "--out-dir=results/reference_validation_current",
      "--threads=2",
      "--seed=4",
      "--perplexity=10",
      "--k=31"
    ),
    hpc_cpu12 = paste(
      "DATASETS=MNIST,FashionMNIST,flow18,mass41,imagenet,FlowRepository_FR-FCM-ZYRM_files,MetRef",
      paste0("K=", k),
      paste0("PERPLEXITY=", perplexity),
      paste0("TIMEOUT=", timeout),
      "sbatch /scratch/firenze/NN/benchmark_embeddings_float32_cpu12.sh"
    ),
    hpc_cuda = paste(
      "DATASETS=MNIST,FashionMNIST,flow18,mass41,imagenet,FlowRepository_FR-FCM-ZYRM_files,MetRef",
      paste0("K=", k),
      paste0("PERPLEXITY=", perplexity),
      paste0("TIMEOUT=", timeout),
      "sbatch /scratch/firenze/NN/benchmark_embeddings_float32_cuda.sh"
    )
  )
}

write_text_list <- function(x, path, indent = "") {
  con <- file(path, open = "wt")
  on.exit(close(con), add = TRUE)
  recurse <- function(obj, prefix = "") {
    if (is.list(obj)) {
      for (nm in names(obj)) {
        cat(prefix, nm, ":\n", sep = "", file = con)
        recurse(obj[[nm]], paste0(prefix, "  "))
      }
    } else {
      val <- paste(as.character(obj), collapse = "\n")
      if (!nzchar(val) || is.na(val)) val <- "NA"
      lines <- strsplit(val, "\n", fixed = TRUE)[[1L]]
      for (line in lines) cat(prefix, line, "\n", sep = "", file = con)
    }
  }
  recurse(x, indent)
  invisible(path)
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
out_dir <- normalizePath(
  args$out_dir %||% file.path("results", paste0("manuscript_reproducibility_", format(Sys.time(), "%Y%m%d_%H%M%S"))),
  mustWork = FALSE
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

seed <- as.integer(args$seed %||% 4L)
k <- as.integer(args$k %||% 30L)
perplexity <- as.numeric(args$perplexity %||% 15)
threads_cpu <- as.integer(args$threads %||% 12L)
timeout <- as.integer(args$timeout %||% 10800L)
python <- Sys.getenv("RETICULATE_PYTHON", unset = Sys.which("python"))
python_packages <- python_versions(python)
fitsne <- fitsne_identity()
release_identity <- list(
  package_tag = Sys.getenv("FASTEMBEDR_RELEASE_TAG", unset = NA_character_),
  package_commit = Sys.getenv(
    "FASTEMBEDR_RELEASE_COMMIT", unset = NA_character_
  ),
  source_archive_sha256 = Sys.getenv(
    "FASTEMBEDR_SOURCE_ARCHIVE_SHA256", unset = NA_character_
  ),
  benchmark_commit = Sys.getenv(
    "FASTEMBEDR_BENCHMARK_COMMIT", unset = git_value(c("rev-parse", "HEAD"))
  ),
  container_sha256 = Sys.getenv(
    "FASTEMBEDR_IMAGE_SHA256", unset = NA_character_
  ),
  result_archive_doi = Sys.getenv(
    "FASTEMBEDR_RESULT_DOI", unset = NA_character_
  )
)

manifest <- list(
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  repository = "https://github.com/tkcaccia/fastEmbedR",
  git_commit = release_identity$benchmark_commit,
  git_describe = git_value(c("describe", "--tags", "--always", "--dirty")),
  git_status_short = git_value(c("status", "--short")),
  release_identity = release_identity,
  random_seed = seed,
  benchmark_parameters = list(k = k, perplexity = perplexity, cpu_threads = threads_cpu, timeout_seconds = timeout),
  benchmark_commands = benchmark_commands(seed, k, perplexity, threads_cpu, timeout),
  hardware = list(
    system = Sys.info(),
    cpu = run_cmd("sysctl", c("-n", "machdep.cpu.brand_string")),
    linux_cpu = run_cmd("lscpu"),
    memory = run_cmd("free", "-h")
  ),
  r = list(
    version = R.version.string,
    platform = R.version$platform,
    home = R.home(),
    library_paths = .libPaths(),
    session_info = paste(capture.output(utils::sessionInfo()), collapse = "\n")
  ),
  compiler = compiler_probe(),
  packages = list(
    fastEmbedR = pkg_version("fastEmbedR"),
    faissR = pkg_version("faissR"),
    Rcpp = pkg_version("Rcpp"),
    float = pkg_version("float"),
    Rtsne = pkg_version("Rtsne"),
    uwot = pkg_version("uwot"),
    umap = pkg_version("umap"),
    jsonlite = pkg_version("jsonlite")
  ),
  comparators = list(
    fitsne_identity = fitsne$value,
    fitsne_identity_type = fitsne$type,
    fitsne_executable = fitsne$executable,
    fitsne_executable_sha256 = fitsne$sha256,
    python_executable = python,
    python_packages = as.list(python_packages)
  ),
  backends = list(
    fastEmbedR_backend_info = backend_capture(),
    cuda = cuda_probe()
  ),
  environment_files = list(
    r_package_installation = "docs/installation.md",
    backend_capabilities = "docs/backend-capabilities.md",
    lightweight_r_environment = "tools/reproducibility/benchmark_environment.yml",
    hpc_cpu_wrapper = "tools/hpc_embeddings/benchmark_embeddings_float32_cpu12.sh",
    hpc_cuda_wrapper = "tools/hpc_embeddings/benchmark_embeddings_float32_cuda.sh",
    hpc_r_driver = "tools/hpc_embeddings/benchmark_embeddings_float32_publication.R"
  )
)

comparator_identity <- data.frame(
  comparator = c(
    "fastEmbedR", "Rtsne", "FIt-SNE", "uwot", "R umap",
    "Python openTSNE", "Python umap-learn", "RAPIDS cuML"
  ),
  version_or_commit = c(
    pkg_version("fastEmbedR"), pkg_version("Rtsne"), fitsne$value,
    pkg_version("uwot"), pkg_version("umap"),
    python_packages[["openTSNE"]], python_packages[["umap-learn"]],
    python_packages[["cuml"]]
  ),
  identity_type = c(
    "R package version", "R package version", fitsne$type,
    "R package version", "R package version", "Python package version",
    "Python package version", "Python package version"
  ),
  artifact_path = c(
    rep(NA_character_, 2L), fitsne$executable,
    rep(NA_character_, 2L), rep(python, 3L)
  ),
  artifact_sha256 = c(
    rep(NA_character_, 2L), fitsne$sha256,
    rep(NA_character_, 5L)
  ),
  stringsAsFactors = FALSE
)

writeLines(manifest$r$session_info, file.path(out_dir, "sessionInfo.txt"))
write_text_list(manifest, file.path(out_dir, "reproducibility_manifest.txt"))
utils::write.csv(
  comparator_identity, file.path(out_dir, "comparator_identity.csv"),
  row.names = FALSE, na = "not_available"
)
if (requireNamespace("jsonlite", quietly = TRUE)) {
  jsonlite::write_json(manifest, file.path(out_dir, "reproducibility_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
}

cat("Wrote reproducibility bundle to:", normalizePath(out_dir), "\n")
