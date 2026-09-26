#!/usr/bin/env python3

import argparse
import csv
import importlib.metadata
import os
import sys
import time

import numpy as np
from scipy.spatial.distance import pdist
from sklearn.manifold import trustworthiness
from sklearn.neighbors import NearestNeighbors

TSNE_EARLY_ITERATIONS = 250
TSNE_TOTAL_ITERATIONS = 750
TSNE_NORMAL_ITERATIONS = TSNE_TOTAL_ITERATIONS - TSNE_EARLY_ITERATIONS


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--method", required=True)
    parser.add_argument("--backend", choices=("cpu", "cuda"), required=True)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--seed", type=int, default=4)
    parser.add_argument("--timing-reps", type=int, default=5)
    return parser.parse_args()


def read_row(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return next(csv.DictReader(handle))


def read_inputs(args):
    manifest = read_row(os.path.join(args.input_dir, "manifest.csv"))
    n, p = int(manifest["n"]), int(manifest["p"])
    data = np.fromfile(
        os.path.join(args.input_dir, "data_float32.bin"), dtype="<f4"
    ).reshape(n, p)
    rows = np.genfromtxt(
        os.path.join(args.input_dir, "rows_labels.csv"),
        delimiter=",", names=True, dtype=None, encoding="utf-8",
    )
    quality_text = np.char.lower(np.asarray(rows["quality_sample"]).astype(str))
    quality = np.isin(quality_text, ("true", "t", "1"))
    labels = np.asarray(rows["label"]).astype(str)
    source_rows = np.asarray(rows["source_row"], dtype=np.int64)
    edge = np.genfromtxt(
        os.path.join(args.input_dir, "quality_compact_affinity.csv"),
        delimiter=",", names=True, dtype=None, encoding="utf-8",
    )
    return manifest, data, quality, labels, source_rows, edge


def package_version(name):
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "unavailable"


def family(name):
    if "pca" in name:
        return "pca"
    if "tsne" in name:
        return "tsne"
    return "umap"


def synchronize(backend):
    if backend == "cuda":
        import cupy as cp
        cp.cuda.runtime.deviceSynchronize()


def to_numpy(value):
    if hasattr(value, "to_numpy"):
        value = value.to_numpy()
    try:
        import cupy as cp
        if isinstance(value, cp.ndarray):
            value = cp.asnumpy(value)
    except ImportError:
        pass
    return np.asarray(value)


def fit_cpu(method, data, rank, seed, threads):
    if method == "sklearn_pca":
        from sklearn.decomposition import PCA
        model = PCA(
            n_components=rank, svd_solver="randomized", random_state=seed
        )
    elif method == "sklearn_tsne":
        from sklearn.manifold import TSNE
        model = TSNE(
            n_components=2, perplexity=30,
            max_iter=TSNE_TOTAL_ITERATIONS,
            init="pca", learning_rate="auto", early_exaggeration=12,
            method="barnes_hut",
            random_state=seed, n_jobs=threads,
        )
    elif method == "python_opentsne":
        from openTSNE import TSNE
        model = TSNE(
            n_components=2, perplexity=30,
            n_iter=TSNE_NORMAL_ITERATIONS,
            early_exaggeration_iter=TSNE_EARLY_ITERATIONS,
            initialization="pca", learning_rate="auto",
            early_exaggeration=12, exaggeration=1,
            initial_momentum=0.5, final_momentum=0.8,
            negative_gradient_method="fft", n_jobs=threads,
            random_state=seed,
        )
    else:
        import umap
        model = umap.UMAP(
            n_neighbors=30, n_components=2, init="spectral",
            metric="euclidean", n_epochs=None, learning_rate=1,
            min_dist=0.1, spread=1, repulsion_strength=1,
            negative_sample_rate=5,
            random_state=seed, n_jobs=threads,
        )
    values = model.fit(data) if method == "python_opentsne" else (
        model.fit_transform(data)
    )
    return model, values


def fit_cuda(method, data, rank, seed):
    if method == "cuml_pca":
        from cuml.decomposition import PCA
        model = PCA(n_components=rank, output_type="cupy")
    elif method == "cuml_tsne":
        from cuml.manifold import TSNE
        model = TSNE(
            n_components=2, perplexity=30, n_neighbors=91,
            max_iter=TSNE_TOTAL_ITERATIONS,
            method="fft", init="pca", random_state=seed,
            early_exaggeration=12, late_exaggeration=1,
            exaggeration_iter=TSNE_EARLY_ITERATIONS,
            pre_momentum=0.5, post_momentum=0.8,
            output_type="cupy",
        )
    else:
        from cuml.manifold import UMAP
        model = UMAP(
            n_neighbors=30, n_components=2, init="spectral",
            metric="euclidean", n_epochs=None, learning_rate=1,
            min_dist=0.1, spread=1, repulsion_strength=1,
            negative_sample_rate=5,
            random_state=seed, output_type="cupy",
        )
    return model, model.fit_transform(data)


def fit_once(args, data, rank):
    started = time.perf_counter()
    if args.backend == "cuda":
        model, values = fit_cuda(args.method, data, rank, args.seed)
    else:
        model, values = fit_cpu(
            args.method, data, rank, args.seed, args.threads
        )
    host_values = to_numpy(values)
    synchronize(args.backend)
    elapsed = time.perf_counter() - started
    return model, host_values, elapsed


def neighbor_indices(values, k):
    count = min(k + 1, len(values))
    found = NearestNeighbors(n_neighbors=count).fit(values)
    indices = found.kneighbors(return_distance=False)
    result = np.empty((len(values), min(k, len(values) - 1)), dtype=int)
    for row in range(len(values)):
        candidates = indices[row][indices[row] != row]
        result[row] = candidates[: result.shape[1]]
    return result


def preservation(reference, candidate):
    return float(np.mean([
        len(set(left).intersection(right)) / reference.shape[1]
        for left, right in zip(reference, candidate)
    ]))


def label_accuracy(indices, labels):
    if np.all(np.isin(labels, ("", "NA", "nan"))):
        return np.nan
    predictions = []
    for row in indices:
        values, counts = np.unique(labels[row], return_counts=True)
        predictions.append(values[np.argmax(counts)])
    return float(np.mean(np.asarray(predictions) == labels))


def compact_kl(layout, edge):
    q = 1.0 / (1.0 + pdist(layout, metric="sqeuclidean"))
    q /= np.sum(q)
    n = len(layout)
    i = np.asarray(edge["i"], dtype=np.int64) - 1
    j = np.asarray(edge["j"], dtype=np.int64) - 1
    offset = n * i - i * (i + 1) // 2 + j - i - 1
    tiny = np.finfo(float).tiny
    p = np.maximum(np.asarray(edge["weight"], dtype=float), tiny)
    return float(np.sum(p * np.log(p / np.maximum(q[offset], tiny))))


def layout_quality(data, layout, labels, quality, edge, method_family):
    high = data[quality]
    low = layout[quality]
    used_labels = labels[quality]
    high_knn = neighbor_indices(high, 30)
    low_knn = neighbor_indices(low, 30)
    return {
        "trustworthiness": float(
            trustworthiness(high, low, n_neighbors=30)
        ),
        "preserve_at_30": preservation(high_knn, low_knn),
        "label_knn_accuracy": label_accuracy(low_knn, used_labels),
        "sampled_kl": (
            compact_kl(low, edge) if method_family == "tsne" else np.nan
        ),
        "reconstruction_relative_l2": np.nan,
        "retained_variance_fraction": np.nan,
    }


def pca_quality(model, data, scores, quality):
    components = to_numpy(model.components_)
    center = to_numpy(getattr(model, "mean_", np.zeros(data.shape[1])))
    reconstructed = scores[quality] @ components + center
    reference = data[quality]
    ratio = np.linalg.norm(reference - reconstructed) / np.linalg.norm(
        reference
    )
    score_variance = np.sum(np.var(scores, axis=0))
    retained = float(score_variance / np.sum(np.var(data, axis=0)))
    return {
        "trustworthiness": np.nan,
        "preserve_at_30": np.nan,
        "label_knn_accuracy": np.nan,
        "sampled_kl": np.nan,
        "reconstruction_relative_l2": float(ratio),
        "retained_variance_fraction": retained,
    }


def write_csv(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(rows, dict):
        rows = [rows]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def umap_epochs(n):
    return 500 if n < 10000 else 200


def read_parameter_contract(method):
    path = os.path.join(
        os.path.dirname(__file__), "workflow_parameter_contract.csv"
    )
    with open(path, newline="", encoding="utf-8") as handle:
        rows = [row for row in csv.DictReader(handle)
                if row["method"] == method]
    if len(rows) != 1:
        raise ValueError(f"Missing parameter contract for {method}")
    return rows[0]


def parameter_metadata(args, n):
    row = read_parameter_contract(args.method)
    row.pop("method")
    row.pop("family")
    row["learning_rate_value"] = {
        "sklearn_tsne": max(n / 48, 50),
        "python_opentsne": max(n / 12, 200),
        "python_umap": 1,
        "cuml_umap": 1,
    }.get(args.method, "")
    row["epochs_value"] = (
        umap_epochs(n) if family(args.method) == "umap" else ""
    )
    row["min_dist_value"] = (
        float(row["min_dist_policy"])
        if family(args.method) == "umap" else ""
    )
    return row


def result_row(args, manifest, elapsed, metrics):
    versions = {
        "python_version": sys.version.split()[0],
        "numpy_version": package_version("numpy"),
        "implementation_version": package_version({
            "sklearn_pca": "scikit-learn",
            "sklearn_tsne": "scikit-learn",
            "python_opentsne": "openTSNE",
            "python_umap": "umap-learn",
            "cuml_pca": "cuml",
            "cuml_tsne": "cuml",
            "cuml_umap": "cuml",
        }[args.method]),
    }
    row = {
        "dataset": args.dataset,
        "family": family(args.method),
        "method": args.method,
        "language": "Python",
        "backend": args.backend,
        "timing_scope": "direct_Python_fit",
        "timing_boundary": "host_float32_to_host_result",
        "timing_interface": "Python_estimator_fit_transform",
        "timing_eligible": True,
        "seed": args.seed,
        "timing_reps": args.timing_reps,
        "warmup_count": 1,
        "warmup_excluded": True,
        "device_synchronized": args.backend == "cuda",
        "output_materialized_on_host_before_timer": True,
        "n": int(manifest["n"]),
        "p": int(manifest["p"]),
        "elapsed_median_sec": float(np.median(elapsed)),
        "elapsed_q1_sec": float(np.quantile(elapsed, 0.25)),
        "elapsed_q3_sec": float(np.quantile(elapsed, 0.75)),
        "threads": args.threads,
        "metric": "" if family(args.method) == "pca" else "euclidean",
        "perplexity": 30 if family(args.method) == "tsne" else "",
        "n_neighbors": 30 if family(args.method) == "umap" else "",
        "iterations_policy": {
            "sklearn_tsne": "750_total",
            "python_opentsne": "250_early+500_normal",
            "cuml_tsne": "750_total",
        }.get(args.method, "package_default"),
        "early_iterations": (
            TSNE_EARLY_ITERATIONS if family(args.method) == "tsne" else ""
        ),
        "normal_iterations": (
            TSNE_NORMAL_ITERATIONS if family(args.method) == "tsne" else ""
        ),
        "total_iterations": (
            TSNE_TOTAL_ITERATIONS if family(args.method) == "tsne" else ""
        ),
        "comparison_contract": (
            "workflow_750_total_iterations"
            if family(args.method) == "tsne"
            else "workflow_package_policy"
        ),
        "knn_boundary": (
            "not_applicable" if family(args.method) == "pca"
            else "internal_to_fit_call"
        ),
        "input_precision": "float32",
    }
    parameters = parameter_metadata(args, int(manifest["n"]))
    return row | parameters | metrics | versions


def main(args):
    if args.timing_reps < 2:
        raise ValueError("At least two timing repetitions are required")
    manifest, data, quality, labels, source_rows, edge = read_inputs(args)
    rank = min(50, data.shape[0] - 1, data.shape[1] - 1)
    fit_once(args, data, rank)
    elapsed = []
    model, values = None, None
    for _ in range(args.timing_reps):
        model, values, seconds = fit_once(args, data, rank)
        elapsed.append(seconds)
    used_family = family(args.method)
    metrics = (
        pca_quality(model, data, values, quality)
        if used_family == "pca"
        else layout_quality(data, values, labels, quality, edge, used_family)
    )
    write_csv(
        os.path.join(args.output_dir, "result.csv"),
        result_row(args, manifest, elapsed, metrics),
    )
    write_csv(os.path.join(args.output_dir, "timing_repetitions.csv"), [
        {
            "dataset": args.dataset,
            "method": args.method,
            "backend": args.backend,
            "seed": args.seed,
            "timing_replicate": index,
            "warmup_count": 1,
            "warmup_excluded": True,
            "timing_scope": "direct_Python_fit",
            "timing_boundary": "host_float32_to_host_result",
            "total_iterations": (
                TSNE_TOTAL_ITERATIONS
                if family(args.method) == "tsne" else ""
            ),
            "elapsed_sec": seconds,
        }
        for index, seconds in enumerate(elapsed, start=1)
    ])
    if values.shape[1] >= 2:
        write_csv(os.path.join(args.output_dir, "embedding.csv"), [
            {
                "benchmark_row": int(index + 1),
                "source_row": int(source_rows[index]),
                "label": str(labels[index]),
                "dimension_1": float(values[index, 0]),
                "dimension_2": float(values[index, 1]),
            }
            for index in range(len(values))
        ])
        selected = values[quality, :2]
        indices = np.flatnonzero(quality)
        write_csv(os.path.join(args.output_dir, "quality_layout.csv"), [
            {
                "benchmark_row": int(row + 1),
                "x": float(selected[index, 0]),
                "y": float(selected[index, 1]),
            }
            for index, row in enumerate(indices)
        ])
    write_csv(os.path.join(args.output_dir, "status.csv"), {
        "experiment": "workflow_comparator",
        "dataset": args.dataset,
        "backend": f"python_{args.backend}",
        "status": "success",
        "error": "",
        "method": args.method,
    })


if __name__ == "__main__":
    parsed = parse_args()
    try:
        main(parsed)
    except Exception as error:
        write_csv(os.path.join(parsed.output_dir, "status.csv"), {
            "experiment": "workflow_comparator",
            "dataset": parsed.dataset,
            "backend": f"python_{parsed.backend}",
            "status": "failed",
            "error": str(error),
            "method": parsed.method,
        })
        raise
