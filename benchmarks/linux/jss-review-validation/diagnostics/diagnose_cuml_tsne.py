#!/usr/bin/env python3
"""Isolate cuML t-SNE layout collapse while fitting every input row."""

import argparse
import csv
import time
from pathlib import Path

import numpy as np
from sklearn.manifold import trustworthiness
from sklearn.metrics import pairwise_distances


def neighbors(data, k):
    distances = pairwise_distances(data)
    np.fill_diagonal(distances, np.inf)
    return np.argpartition(distances, k - 1, axis=1)[:, :k]


def preservation(reference, layout):
    return np.mean([
        len(set(a) & set(b)) / reference.shape[1]
        for a, b in zip(reference, layout)
    ])


def variants(n):
    if n > 5000:
        return ((200, "none", "fft"), (200, "adaptive", "fft"))
    return (
        (25, "none", "fft"),
        (50, "none", "fft"),
        (100, "none", "fft"),
        (200, "none", "fft"),
        (200, "adaptive", "fft"),
        (50, "none", "exact"),
    )


def run(data, output, seed, n_neighbors, quality_n):
    import cupy as cp
    import cuml
    from cuml.manifold import TSNE

    sample = np.sort(np.random.default_rng(seed).choice(
        len(data), size=min(quality_n, len(data)), replace=False
    ))
    high = np.asarray(data[sample])
    k = min(30, (len(sample) - 2) // 2)
    if k < 1:
        raise ValueError("At least four quality rows are required")
    high_neighbors = neighbors(high, k)
    rows = []
    for learning_rate, rate_policy, method in variants(len(data)):
        model = TSNE(
            n_components=2, perplexity=30, n_neighbors=n_neighbors,
            max_iter=1000, method=method, init="pca",
            random_state=seed, early_exaggeration=12,
            late_exaggeration=1, exaggeration_iter=250,
            pre_momentum=0.5, post_momentum=0.8,
            learning_rate=learning_rate,
            learning_rate_method=rate_policy, output_type="cupy",
            min_grad_norm=0.0, n_iter_without_progress=1001,
        )
        started = time.perf_counter()
        layout = cp.asnumpy(model.fit_transform(data))
        cp.cuda.runtime.deviceSynchronize()
        elapsed = time.perf_counter() - started
        name = f"rate_{learning_rate}_{rate_policy}_{method}"
        sampled = layout[sample]
        np.savetxt(output / f"{name}.csv",
                   np.column_stack((sample + 1, sampled)),
                   delimiter=",", header="source_row,x,y", comments="")
        rows.append(dict(
            variant=name, seed=seed, cuml_version=cuml.__version__,
            n=len(data),
            p=data.shape[1], elapsed_sec=elapsed,
            requested_learning_rate=learning_rate,
            requested_rate_policy=rate_policy,
            requested_method=method,
            requested_neighbors=n_neighbors,
            reported_neighbors=getattr(model, "n_neighbors", ""),
            reported_perplexity=getattr(model, "perplexity", ""),
            reported_learning_rate=getattr(
                model, "learning_rate_float", ""),
            n_iter=getattr(model, "n_iter_", ""),
            fitted_kl=getattr(model, "kl_divergence_", ""),
            quality_scope="fixed_sample_internal",
            quality_sample_n=len(sample),
            trustworthiness=trustworthiness(high, sampled,
                                             n_neighbors=k),
            preserve_at_k=preservation(
                high_neighbors, neighbors(sampled, k)),
            sd_x=np.std(layout[:, 0]), sd_y=np.std(layout[:, 1]),
            finite=np.isfinite(layout).all(),
        ))
        print(rows[-1], flush=True)
    with (output / "summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--n", type=int, required=True)
    parser.add_argument("--p", type=int, required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--seed", type=int, default=4)
    parser.add_argument("--neighbors", type=int, default=90)
    parser.add_argument("--quality-n", type=int, default=2048)
    args = parser.parse_args()
    if not 1 <= args.neighbors < args.n:
        raise ValueError("neighbors must be between 1 and n - 1")
    if args.quality_n < 4:
        raise ValueError("quality-n must be at least four")
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    expected = args.n * args.p * np.dtype("<f4").itemsize
    if Path(args.input).stat().st_size != expected:
        raise ValueError("Input size does not match n * p * float32")
    data = np.memmap(args.input, dtype="<f4", mode="r",
                     shape=(args.n, args.p))
    if not np.isfinite(data).all():
        raise ValueError("Non-finite input data")
    run(data, output, args.seed, args.neighbors, args.quality_n)


if __name__ == "__main__":
    main()
