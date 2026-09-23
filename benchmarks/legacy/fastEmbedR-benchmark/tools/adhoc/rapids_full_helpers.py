import time

import cupy as cp


def _sync():
    cp.cuda.Stream.null.synchronize()


def run_umap(x_np, n_neighbors=30, random_state=4):
    from cuml.manifold import UMAP

    t0 = time.perf_counter()
    xg = cp.asarray(x_np, dtype=cp.float32)
    _sync()
    upload = time.perf_counter() - t0

    model = UMAP(
        n_components=2,
        n_neighbors=int(n_neighbors),
        init="spectral",
        random_state=int(random_state),
        output_type="cupy",
    )
    t0 = time.perf_counter()
    y = model.fit_transform(xg)
    _sync()
    fit = time.perf_counter() - t0
    return {
        "upload_sec": upload,
        "fit_sec": fit,
        "total_sec": upload + fit,
        "shape": tuple(y.shape),
    }


def run_tsne(x_np, perplexity=30, random_state=4):
    from cuml.manifold import TSNE

    t0 = time.perf_counter()
    xg = cp.asarray(x_np, dtype=cp.float32)
    _sync()
    upload = time.perf_counter() - t0

    n_neighbors = max(3 * int(perplexity) + 1, int(perplexity) + 1)
    model = TSNE(
        n_components=2,
        perplexity=float(perplexity),
        n_neighbors=int(n_neighbors),
        method="fft",
        init="pca",
        random_state=int(random_state),
        output_type="cupy",
    )
    t0 = time.perf_counter()
    y = model.fit_transform(xg)
    _sync()
    fit = time.perf_counter() - t0
    return {
        "upload_sec": upload,
        "fit_sec": fit,
        "total_sec": upload + fit,
        "shape": tuple(y.shape),
    }
