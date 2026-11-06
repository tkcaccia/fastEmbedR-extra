args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 5L)
root <- '/Users/silvanopiazza/Documents/Stefano'
work <- file.path(root, 'fastEmbedR-multicpu-threadpool-c288af6-20261106')
variant <- args[[1L]]
case_name <- args[[2L]]
method <- args[[3L]]
cores <- as.integer(args[[4L]])
repetition <- as.integer(args[[5L]])
stopifnot(variant %in% c('baseline', 'candidate'),
    case_name %in% c('low', 'high'),
    method %in% c('louvain', 'leiden'),
    cores %in% c(1L, 4L, 8L),
    repetition %in% 1:3)
lib <- file.path(work, variant, 'library')
.libPaths(c(lib, file.path(root, 'data/Rlib'), .libPaths()))
library(fastEmbedR)
stopifnot(startsWith(find.package('fastEmbedR'), lib))
cases <- list(
    low = list(prefix = file.path(root,
        'fastEmbedR-multicpu-batch262k-20261104',
        'benchmark-100k/fuzzy'), n = 100000L, passes = 4L),
    high = list(prefix = file.path(root,
        'fastEmbedR-multicpu-highdegree-20261104',
        'benchmark-50k-k200/fuzzy'), n = 50000L, passes = 2L))
case <- cases[[case_name]]
graph <- massive_fuzzy_graph(case$prefix, case$n)
name <- sprintf('%s-%s-%s-cpu%d-r%d', variant, case_name,
    method, cores, repetition)
output <- file.path(work, 'runs', paste0(name, '.clusters.u32'))
stopifnot(!file.exists(output))
started <- proc.time()[[3L]]
fit <- graph_cluster(graph, method = method, backend = 'cpu',
    n.cores = cores, parallel.mode = 'fit',
    n_iterations = case$passes, seed = 4L,
    output = output, chunk_rows = 4096L,
    memory_limit = if (method == 'leiden') '1GB' else '512MB')
seconds <- unname(proc.time()[[3L]] - started)
labels <- massive_read_rows(fit, 1L, case$n)
stopifnot(length(labels) == case$n,
    fit$cpu_workers_effective == cores,
    is.finite(fit$modularity_final),
    fit$n_communities > 0L)
metric <- list(variant = variant, case = case_name,
    method = method, cores = cores, repetition = repetition,
    package_library = find.package('fastEmbedR'),
    graph_prefix = case$prefix, rows = case$n,
    seconds = seconds, communities = fit$n_communities,
    modularity = fit$modularity_final,
    effective_workers = fit$cpu_workers_effective,
    labels_sha256 = digest::digest(labels,
        algo = 'sha256', serialize = TRUE),
    output = output)
jsonlite::write_json(metric, file.path(work, 'runs',
    paste0(name, '.json')), auto_unbox = TRUE, pretty = TRUE)
cat(jsonlite::toJSON(metric, auto_unbox = TRUE), '\n')
