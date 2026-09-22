#!/usr/bin/env python3

import argparse
import csv
import importlib.metadata
import json
import os
import time

import numpy as np
import scipy.sparse
from scipy.spatial.distance import pdist
from sklearn.manifold import trustworthiness
from sklearn.neighbors import NearestNeighbors

from openTSNE import TSNEEmbedding
from openTSNE.affinity import PrecomputedAffinities


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--seed", required=True, type=int)
    parser.add_argument("--normal-iterations", required=True, type=int)
    parser.add_argument("--threads", default=4, type=int)
    parser.add_argument("--timing-reps", default=1, type=int)
    parser.add_argument("--warmup", action="store_true")
    return parser.parse_args()


def read_single_row(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return next(csv.DictReader(handle))


def package_version(name):
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "unavailable"


def read_inputs(args):
    manifest = read_single_row(os.path.join(args.input_dir, "portable_manifest.csv"))
    n = int(manifest["n"])
    p = int(manifest["p"])
    data = np.fromfile(
        os.path.join(args.input_dir, "data_float32_rowmajor.bin"),
        dtype="<f4",
    ).reshape(n, p)
    init = np.loadtxt(
        os.path.join(args.input_dir, f"init_seed{args.seed}.csv"),
        delimiter=",",
        skiprows=1,
        dtype=np.float64,
    )
    edge = np.genfromtxt(
        os.path.join(args.input_dir, "compact_affinity_edges.csv"),
        delimiter=",",
        names=True,
        dtype=None,
        encoding="utf-8",
    )
    labels = np.genfromtxt(
        os.path.join(args.input_dir, "labels.csv"),
        delimiter=",",
        names=True,
        dtype=None,
        encoding="utf-8",
    )["label"]
    return manifest, data, init, edge, labels


def affinity_object(edge, n):
    row = np.asarray(edge["i"], dtype=np.int64) - 1
    col = np.asarray(edge["j"], dtype=np.int64) - 1
    weight = np.asarray(edge["weight"], dtype=np.float64) / 2.0
    matrix = scipy.sparse.coo_matrix(
        (np.concatenate([weight, weight]),
         (np.concatenate([row, col]), np.concatenate([col, row]))),
        shape=(n, n),
    ).tocsr()
    try:
        return PrecomputedAffinities(matrix, normalize=False)
    except TypeError:
        return PrecomputedAffinities(matrix)


def nearest_neighbors(values, k):
    model = NearestNeighbors(n_neighbors=min(k + 1, values.shape[0]))
    indices = model.fit(values).kneighbors(return_distance=False)
    rows = np.arange(values.shape[0])[:, None]
    without_self = np.empty((values.shape[0], min(k, values.shape[0] - 1)), int)
    for index in range(values.shape[0]):
        candidates = indices[index][indices[index] != rows[index, 0]]
        without_self[index] = candidates[:without_self.shape[1]]
    return without_self


def preservation(reference, candidate):
    return float(np.mean([
        len(set(a).intersection(b)) / reference.shape[1]
        for a, b in zip(reference, candidate)
    ]))


def label_accuracy(indices, labels):
    labels = np.asarray(labels).astype(str)
    if np.all(np.isin(labels, ["", "NA", "nan"])):
        return np.nan
    predicted = []
    for row in indices:
        values, counts = np.unique(labels[row], return_counts=True)
        predicted.append(values[np.argmax(counts)])
    return float(np.mean(np.asarray(predicted) == labels))


def common_affinity_kl(layout, edge):
    q = 1.0 / (1.0 + pdist(layout, metric="sqeuclidean"))
    q /= np.sum(q)
    n = layout.shape[0]
    i = np.asarray(edge["i"], dtype=np.int64) - 1
    j = np.asarray(edge["j"], dtype=np.int64) - 1
    offset = n * i - i * (i + 1) // 2 + j - i - 1
    p = np.maximum(np.asarray(edge["weight"], dtype=np.float64), np.finfo(float).tiny)
    q_edge = np.maximum(q[offset], np.finfo(float).tiny)
    return float(np.sum(p * np.log(p / q_edge)))


def write_csv(path, row):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row))
        writer.writeheader()
        writer.writerow(row)


def fit_once(init, affinity, manifest, args):
    embedding = TSNEEmbedding(
        init.copy(),
        affinity,
        negative_gradient_method="fft",
        n_jobs=args.threads,
        random_state=args.seed,
    )
    learning_rate = float(manifest["learning_rate"])
    started = time.perf_counter()
    embedding.optimize(
        n_iter=int(manifest["early_exaggeration_iter"]),
        exaggeration=float(manifest["early_exaggeration"]),
        learning_rate=learning_rate,
        momentum=float(manifest["initial_momentum"]),
        max_step_norm=float(manifest["max_step_norm"]),
        inplace=True,
    )
    embedding.optimize(
        n_iter=args.normal_iterations,
        exaggeration=1,
        learning_rate=learning_rate,
        momentum=float(manifest["final_momentum"]),
        max_step_norm=float(manifest["max_step_norm"]),
        inplace=True,
    )
    return embedding, time.perf_counter() - started


def write_timing_rows(path, elapsed_values, args):
    fieldnames = [
        "dataset", "backend", "timing_scope", "seed",
        "timing_replicate", "warmup_count", "warmup_excluded",
        "threads", "normal_iterations", "elapsed_sec",
    ]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for index, elapsed in enumerate(elapsed_values, start=1):
            writer.writerow({
                "dataset": args.dataset,
                "backend": "python_cpu",
                "timing_scope": "direct_python_fit_only",
                "seed": args.seed,
                "timing_replicate": index,
                "warmup_count": int(args.warmup),
                "warmup_excluded": bool(args.warmup),
                "threads": args.threads,
                "normal_iterations": args.normal_iterations,
                "elapsed_sec": elapsed,
            })


def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    manifest, data, init, edge, labels = read_inputs(args)
    affinity = affinity_object(edge, data.shape[0])
    learning_rate = float(manifest["learning_rate"])
    if args.warmup:
        fit_once(init, affinity, manifest, args)
    elapsed_values = []
    embedding = None
    for _ in range(args.timing_reps):
        embedding, elapsed = fit_once(init, affinity, manifest, args)
        elapsed_values.append(elapsed)
    fit_seconds = (
        float(np.median(elapsed_values))
        if args.timing_reps > 1 and args.warmup
        else elapsed_values[-1]
    )
    layout = np.asarray(embedding, dtype=np.float64)
    high_knn = nearest_neighbors(data, 30)
    low_knn = nearest_neighbors(layout, 30)
    row = {
        "dataset": args.dataset,
        "backend": "python_cpu",
        "implementation": "Python openTSNE",
        "timing_scope": "direct_python_fit_only",
        "timing_eligible": args.timing_reps > 1 and args.warmup,
        "timing_reps": args.timing_reps,
        "warmup_count": int(args.warmup),
        "seed": args.seed,
        "n": data.shape[0],
        "p": data.shape[1],
        "perplexity": float(manifest["perplexity"]),
        "support_k": int(manifest["k"]),
        "threads": args.threads,
        "early_iterations": int(manifest["early_exaggeration_iter"]),
        "normal_iterations": args.normal_iterations,
        "learning_rate": learning_rate,
        "elapsed_sec": fit_seconds,
        "elapsed_q1_sec": float(np.quantile(elapsed_values, 0.25)),
        "elapsed_q3_sec": float(np.quantile(elapsed_values, 0.75)),
        "reported_kl": float(embedding.kl_divergence),
        "common_affinity_kl": common_affinity_kl(layout, edge),
        "trustworthiness": float(trustworthiness(data, layout, n_neighbors=30)),
        "preserve_at_30": preservation(high_knn, low_knn),
        "label_knn_accuracy": label_accuracy(low_knn, labels),
        "finite": bool(np.isfinite(layout).all()),
        "openTSNE_version": package_version("openTSNE"),
        "numpy_version": package_version("numpy"),
        "scipy_version": package_version("scipy"),
        "scikit_learn_version": package_version("scikit-learn"),
    }
    np.save(os.path.join(args.output_dir, "layout.npy"), layout)
    np.savetxt(
        os.path.join(args.output_dir, "layout.csv"),
        layout,
        delimiter=",",
        header="V1,V2",
        comments="",
    )
    write_csv(os.path.join(args.output_dir, "result.csv"), row)
    write_timing_rows(
        os.path.join(args.output_dir, "timing_repetitions.csv"),
        elapsed_values,
        args,
    )
    experiment = (
        "tsne_longrun_timing_python"
        if args.timing_reps > 1 and args.warmup
        else "tsne_longrun_python"
    )
    write_csv(os.path.join(args.output_dir, "status.csv"), {
        "experiment": experiment,
        "dataset": args.dataset,
        "backend": "python_cpu",
        "status": "success",
        "error": "",
    })
    with open(
        os.path.join(args.output_dir, "python_environment.json"),
        "w",
        encoding="utf-8",
    ) as handle:
        json.dump(row, handle, indent=2)


if __name__ == "__main__":
    main()
