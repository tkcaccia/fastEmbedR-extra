#!/usr/bin/env python3
"""Isolate cuML t-SNE layout collapse on a small full dataset."""

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


def variants():
    return (
        (750, "adaptive", "pca", "fft"),
        (1000, "adaptive", "pca", "fft"),
        (1000, "none", "pca", "fft"),
        (1000, "adaptive", "random", "fft"),
        (1000, "none", "random", "fft"),
        (1000, "none", "pca", "exact"),
    )


def run(data, output):
    import cupy as cp
    import cuml
    from cuml.manifold import TSNE

    high_neighbors = neighbors(data, 30)
    rows = []
    for iterations, rate_policy, init, method in variants():
        model = TSNE(
            n_components=2, perplexity=30, n_neighbors=91,
            max_iter=iterations, method=method, init=init,
            random_state=4, early_exaggeration=12,
            late_exaggeration=1, exaggeration_iter=250,
            pre_momentum=0.5, post_momentum=0.8,
            learning_rate_method=rate_policy, output_type="cupy",
        )
        started = time.perf_counter()
        layout = cp.asnumpy(model.fit_transform(data))
        cp.cuda.runtime.deviceSynchronize()
        elapsed = time.perf_counter() - started
        name = f"{iterations}_{rate_policy}_{init}_{method}"
        np.savetxt(output / f"{name}.csv", layout,
                   delimiter=",", header="x,y", comments="")
        rows.append(dict(
            variant=name, cuml_version=cuml.__version__, n=len(data),
            p=data.shape[1], elapsed_sec=elapsed,
            requested_neighbors=91,
            reported_neighbors=getattr(model, "n_neighbors", ""),
            reported_perplexity=getattr(model, "perplexity", ""),
            reported_learning_rate=getattr(
                model, "learning_rate_float", ""),
            n_iter=getattr(model, "n_iter_", ""),
            fitted_kl=getattr(model, "kl_divergence_", ""),
            trustworthiness=trustworthiness(data, layout,
                                             n_neighbors=30),
            preserve_at_30=preservation(
                high_neighbors, neighbors(layout, 30)),
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
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    data = np.fromfile(args.input, dtype="<f4").reshape(args.n, args.p)
    if not np.isfinite(data).all():
        raise ValueError("Non-finite input data")
    run(data, output)


if __name__ == "__main__":
    main()
