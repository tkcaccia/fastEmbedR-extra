.libPaths(c(
    "/Users/silvanopiazza/Documents/Stefano/fastEmbedR-candidate-20261104b/library",
    "/Users/silvanopiazza/Documents/Stefano/data/Rlib", .libPaths()))
library(fastEmbedR)
path <- paste0("/Users/silvanopiazza/Documents/Stefano/",
    "fastEmbedR-mac-20261031/data/FashionMNIST_n5000/",
    "FashionMNIST_n5000_float32.RData")
input <- new.env(parent = emptyenv())
load(path, envir = input)
x <- float::dbl(input$dataset$data)
labels <- as.integer(input$dataset$labels)
set.seed(733L)
ids <- sort(unlist(lapply(sort(unique(labels)), function(value)
    sample(which(labels == value), 30L))))
x <- x[ids, , drop = FALSE]
labels <- labels[ids]
score <- function(fit) {
    layout <- as.matrix(fit$layout)
    quality <- evaluate_embedding(x, layout, k = 15L)
    distance <- as.matrix(dist(layout))
    diag(distance) <- Inf
    accuracy <- mean(labels[apply(distance, 1L, which.min)] == labels)
    c(trust = quality$trustworthiness, accuracy = accuracy)
}
run <- function(scope, epochs = NULL, backend = "metal") {
    args <- list(data = x, n_neighbors = 30L, n_components = 3L,
        backend = backend, seed = 733L)
    if (scope == "landmark") {
        args$landmarks <- 0.5
        args$refinement_epochs <- epochs
    }
    started <- proc.time()[[3L]]
    fit <- do.call(umap, args)
    elapsed <- proc.time()[[3L]] - started
    quality <- score(fit)
    refine <- fit$parameters$landmark_refinement_backend
    if (is.null(refine)) refine <- NA_character_
    cat(scope, backend, if (is.null(epochs)) NA else epochs,
        quality[["trust"]], quality[["accuracy"]], elapsed,
        refine, "\n")
}
cat("scope backend epochs trust label_accuracy seconds refine_backend\n")
run("full", backend = "cpu")
run("full")
for (epochs in c(0L, 20L, 50L, 100L)) run("landmark", epochs)
