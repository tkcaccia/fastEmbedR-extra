#!/usr/bin/env python3

import argparse
import csv
import gc
import importlib.metadata
import os
import sys
import time

import numpy as np
from scipy.spatial.distance import pdist
from sklearn.manifold import trustworthiness
from sklearn.neighbors import NearestNeighbors

TSNE_EARLY_ITERATIONS = 250
TSNE_TOTAL_ITERATIONS = 1000
TSNE_NORMAL_ITERATIONS = TSNE_TOTAL_ITERATIONS - TSNE_EARLY_ITERATIONS
CUML_TSNE_MIN_GRAD_NORM = 0.0
NOMAD_EPOCHS = 100
NOMAD_MAX_BATCH = 8192
NOMAD_NEIGHBORS = 8
NOMAD_NOISE = 10000


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
    parser.add_argument("--timeout-seconds", type=float, default=7200)
    parser.add_argument("--deadline-epoch", type=float, default=float("inf"))
    parser.add_argument("--n-components", type=int, default=2)
    parser.add_argument("--defer-quality", action="store_true")
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
    edge = None
    if not args.defer_quality:
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
    if name == "nomad":
        return "nomad"
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


def fit_cpu(method, data, rank, seed, threads, components):
    if method == "sklearn_pca":
        from sklearn.decomposition import PCA
        model = PCA(
            n_components=rank, svd_solver="randomized", random_state=seed
        )
    elif method == "sklearn_tsne":
        from sklearn.manifold import TSNE
        model = TSNE(
            n_components=components, perplexity=30,
            max_iter=TSNE_TOTAL_ITERATIONS,
            init="pca", learning_rate="auto", early_exaggeration=12,
            method="barnes_hut",
            random_state=seed, n_jobs=threads,
        )
    elif method == "python_opentsne":
        from openTSNE import TSNE
        model = TSNE(
            n_components=components, perplexity=30,
            n_iter=TSNE_NORMAL_ITERATIONS,
            early_exaggeration_iter=TSNE_EARLY_ITERATIONS,
            initialization="pca", learning_rate="auto",
            early_exaggeration=12, exaggeration=1,
            initial_momentum=0.5, final_momentum=0.8,
            negative_gradient_method=("fft" if components == 2 else "bh"),
            n_jobs=threads,
            random_state=seed,
        )
    elif method == "python_umap":
        import umap
        model = umap.UMAP(
            n_neighbors=30, n_components=components, init="spectral",
            metric="euclidean", n_epochs=None, learning_rate=1,
            min_dist=0.1, spread=1, repulsion_strength=1,
            negative_sample_rate=5,
            random_state=seed, n_jobs=threads,
        )
    else:
        raise ValueError(f"Unsupported CPU comparator: {method}")
    values = model.fit(data) if method == "python_opentsne" else (
        model.fit_transform(data)
    )
    return model, values


def fit_cuda(method, data, rank, seed, components):
    if method == "nomad":
        import torch
        from nomad_projection import NomadProjection
        if not torch.cuda.is_available() or torch.cuda.device_count() != 1:
            raise RuntimeError("NOMAD requires exactly one visible CUDA GPU")
        np.random.seed(seed)
        torch.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)
        torch.cuda.reset_peak_memory_stats()
        model = NomadProjection()
        values = model.fit_transform(
            X=data, epochs=NOMAD_EPOCHS,
            batch_size=min(NOMAD_MAX_BATCH, len(data)),
            n_neighbors=NOMAD_NEIGHBORS, n_noise=NOMAD_NOISE,
            n_cells=1 if len(data) < 5000 else 5,
        )
        torch.cuda.synchronize()
        model.cuda_peak_allocated_bytes = torch.cuda.max_memory_allocated()
        return model, values
    if method == "cuml_pca":
        from cuml.decomposition import PCA
        model = PCA(n_components=rank, output_type="cupy")
    elif method == "cuml_tsne":
        from cuml.manifold import TSNE
        model = TSNE(
            n_components=components, perplexity=30, n_neighbors=91,
            max_iter=TSNE_TOTAL_ITERATIONS,
            method="fft", init="pca", random_state=seed,
            early_exaggeration=12, late_exaggeration=1,
            exaggeration_iter=TSNE_EARLY_ITERATIONS,
            pre_momentum=0.5, post_momentum=0.8,
            learning_rate=200, learning_rate_method="none",
            min_grad_norm=CUML_TSNE_MIN_GRAD_NORM,
            output_type="cupy",
        )
    elif method == "cuml_umap":
        from cuml.manifold import UMAP
        model = UMAP(
            n_neighbors=30, n_components=components, init="spectral",
            metric="euclidean", n_epochs=None, learning_rate=1,
            min_dist=0.1, spread=1, repulsion_strength=1,
            negative_sample_rate=5,
            random_state=seed, output_type="cupy",
        )
    else:
        raise ValueError(f"Unsupported CUDA comparator: {method}")
    return model, model.fit_transform(data)


def fit_once(args, data, rank):
    started = time.perf_counter()
    if args.backend == "cuda":
        model, values = fit_cuda(
            args.method, data, rank, args.seed, args.n_components,
        )
    else:
        model, values = fit_cpu(
            args.method, data, rank, args.seed, args.threads,
            args.n_components
        )
    if args.method == "cuml_tsne":
        actual = getattr(model, "n_iter_", None)
        if actual != TSNE_TOTAL_ITERATIONS:
            raise RuntimeError(
                f"cuML t-SNE stopped at {actual} of "
                f"{TSNE_TOTAL_ITERATIONS} requested iterations"
            )
    host_values = to_numpy(values)
    synchronize(args.backend)
    if host_values.shape != (len(data), args.n_components):
        raise RuntimeError("Comparator returned the wrong embedding shape")
    if not np.isfinite(host_values).all():
        raise RuntimeError("Comparator returned non-finite coordinates")
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
    rows = iter(rows)
    first = next(rows)
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(first))
        writer.writeheader()
        writer.writerow(first)
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
    if args.n_components == 3 and args.method == "python_opentsne":
        row["optimizer"] = "Barnes-Hut"
    row["learning_rate_value"] = {
        "sklearn_tsne": max(n / 48, 50),
        "python_opentsne": max(n / 12, 200),
        "python_umap": 1,
        "cuml_umap": 1,
        "cuml_tsne": 200,
    }.get(args.method, "")
    row["epochs_value"] = (
        NOMAD_EPOCHS if args.method == "nomad" else
        umap_epochs(n) if family(args.method) == "umap" else ""
    )
    row["min_dist_value"] = (
        float(row["min_dist_policy"])
        if family(args.method) == "umap" else ""
    )
    return row


def can_fit_repetitions(args, observed, count):
    reserve = min(300, args.timeout_seconds * 0.05)
    remaining = args.deadline_epoch - time.time()
    return remaining >= reserve + 1.2 * max(observed) * count


def result_row(args, manifest, elapsed, metrics, model, warmup_excluded):
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
            "nomad": "nomad_projection",
        }[args.method]),
    }
    row = {
        "dataset": args.dataset,
        "family": family(args.method),
        "method": args.method,
        "n_components": args.n_components,
        "language": "Python",
        "backend": args.backend,
        "timing_scope": "direct_Python_fit",
        "timing_boundary": "host_float32_to_host_result",
        "timing_interface": "Python_estimator_fit_transform",
        "timing_eligible": warmup_excluded and len(elapsed) == args.timing_reps,
        "seed": args.seed,
        "timing_reps": len(elapsed),
        "timing_reps_requested": args.timing_reps,
        "warmup_count": int(warmup_excluded),
        "warmup_excluded": warmup_excluded,
        "timing_policy": (
            "single_fit_budget" if not warmup_excluded else
            "partial_budget" if len(elapsed) < args.timing_reps else
            "complete_repeated"
        ),
        "method_timeout_seconds": args.timeout_seconds,
        "device_synchronized": args.backend == "cuda",
        "output_materialized_on_host_before_timer": True,
        "n": int(manifest["n"]),
        "p": int(manifest["p"]),
        "elapsed_median_sec": float(np.median(elapsed)),
        "elapsed_q1_sec": float(np.quantile(elapsed, 0.25)),
        "elapsed_q3_sec": float(np.quantile(elapsed, 0.75)),
        "threads": args.threads,
        "metric": (
            "" if family(args.method) == "pca" else
            "inner_product" if args.method == "nomad" else "euclidean"
        ),
        "perplexity": 30 if family(args.method) == "tsne" else "",
        "n_neighbors": (
            NOMAD_NEIGHBORS if args.method == "nomad" else
            30 if family(args.method) == "umap" else ""
        ),
        "iterations_policy": {
            "sklearn_tsne": "1000_total",
            "python_opentsne": "250_early+750_normal",
            "cuml_tsne": "1000_total",
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
            "distinct_nomad_objective" if args.method == "nomad" else
            "workflow_1000_total_iterations"
            if family(args.method) == "tsne" else
            "workflow_package_policy"
        ),
        "nomad_batch_size": (
            min(NOMAD_MAX_BATCH, int(manifest["n"]))
            if args.method == "nomad" else ""
        ),
        "nomad_n_noise": NOMAD_NOISE if args.method == "nomad" else "",
        "nomad_n_cells": (
            1 if int(manifest["n"]) < 5000 else 5
        ) if args.method == "nomad" else "",
        "nomad_cuda_peak_allocated_bytes": (
            getattr(model, "cuda_peak_allocated_bytes", "")
            if args.method == "nomad" else ""
        ),
        "knn_boundary": (
            "not_applicable" if family(args.method) == "pca"
            else "internal_to_fit_call"
        ),
        "input_precision": "float32",
        "quality_deferred": args.defer_quality,
        "cuml_tsne_learning_rate_method": (
            "none" if args.method == "cuml_tsne" else ""
        ),
        "cuml_tsne_reported_neighbors": (
            getattr(model, "n_neighbors", "")
            if args.method == "cuml_tsne" else ""
        ),
        "cuml_tsne_reported_iterations": (
            getattr(model, "n_iter_", "")
            if args.method == "cuml_tsne" else ""
        ),
        "fitted_kl_divergence": float(getattr(
            model, "kl_divergence_", np.nan
        )) if args.method == "cuml_tsne" else np.nan,
    }
    parameters = parameter_metadata(args, int(manifest["n"]))
    return row | parameters | metrics | versions


def main(args):
    if args.timing_reps < 2:
        raise ValueError("At least two timing repetitions are required")
    if not np.isfinite(args.timeout_seconds) or args.timeout_seconds <= 0:
        raise ValueError("Timeout must be positive")
    if args.n_components not in (2, 3):
        raise ValueError("Output dimensions must be 2 or 3")
    if args.method == "nomad" and args.backend != "cuda":
        raise ValueError("NOMAD requires the CUDA backend")
    if args.n_components == 3 and args.method in ("cuml_tsne", "nomad"):
        write_csv(os.path.join(args.output_dir, "status.csv"), {
            "experiment": "workflow_comparator",
            "dataset": args.dataset,
            "backend": f"python_{args.backend}",
            "status": "unsupported",
            "error": f"{args.method} supports only two output components.",
            "method": args.method,
        })
        return
    manifest, data, quality, labels, source_rows, edge = read_inputs(args)
    rank = min(50, data.shape[0] - 1, data.shape[1] - 1)
    pilot_model, pilot_values, pilot_seconds = fit_once(args, data, rank)
    print(f"Pilot completed: {pilot_seconds:.3f} seconds", flush=True)
    warmup_excluded = can_fit_repetitions(
        args, [pilot_seconds], args.timing_reps
    )
    if warmup_excluded:
        del pilot_model, pilot_values
        if args.defer_quality:
            gc.collect()
        elapsed = []
        model, values = None, None
        for index in range(args.timing_reps):
            if index and not can_fit_repetitions(
                args, [pilot_seconds, *elapsed], 1
            ):
                break
            if args.defer_quality:
                model, values = None, None
                gc.collect()
            model, values, seconds = fit_once(args, data, rank)
            elapsed.append(seconds)
            print(f"Timing repetition {index + 1}/{args.timing_reps}: "
                  f"{seconds:.3f} seconds", flush=True)
    else:
        model, values = pilot_model, pilot_values
        elapsed = [pilot_seconds]
        print("Skipping timing repeats: method time budget", flush=True)
    used_family = family(args.method)
    if args.defer_quality:
        metrics = dict.fromkeys((
            "trustworthiness", "preserve_at_30", "label_knn_accuracy",
            "sampled_kl", "reconstruction_relative_l2",
            "retained_variance_fraction",
        ), np.nan)
    else:
        metrics = (
            pca_quality(model, data, values, quality)
            if used_family == "pca" else layout_quality(
                data, values, labels, quality, edge, used_family
            )
        )
    write_csv(
        os.path.join(args.output_dir, "result.csv"),
        result_row(args, manifest, elapsed, metrics, model,
                   warmup_excluded),
    )
    write_csv(os.path.join(args.output_dir, "timing_repetitions.csv"), [
        {
            "dataset": args.dataset,
            "method": args.method,
            "backend": args.backend,
            "seed": args.seed,
            "timing_replicate": index,
            "warmup_count": int(warmup_excluded),
            "warmup_excluded": warmup_excluded,
            "timing_reps_requested": args.timing_reps,
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
        write_csv(os.path.join(args.output_dir, "embedding.csv"), (
            {
                "benchmark_row": int(index + 1),
                "source_row": int(source_rows[index]),
                "label": str(labels[index]),
                "dimension_1": float(values[index, 0]),
                "dimension_2": float(values[index, 1]),
                **({"dimension_3": float(values[index, 2])}
                   if args.n_components == 3 else {}),
            }
            for index in range(len(values))
        ))
        if not args.defer_quality:
            selected = values[quality, :args.n_components]
            indices = np.flatnonzero(quality)
            write_csv(os.path.join(args.output_dir, "quality_layout.csv"), [
                {
                    "benchmark_row": int(row + 1),
                    "x": float(selected[index, 0]),
                    "y": float(selected[index, 1]),
                    **({"z": float(selected[index, 2])}
                       if args.n_components == 3 else {}),
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
