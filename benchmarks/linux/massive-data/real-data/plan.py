#!/usr/bin/env python3
"""Create matched real-data cases without claiming unsupported GPU routes."""

import csv
import sys
from pathlib import Path


DATASETS = {
    "flow18": (1_000_021, 11),
    "imagenet": (1_281_167, 1024),
    "FlowRepository_FR-FCM-ZYRM_files": (5_220_347, 32),
}


def cases(dataset):
    rows, columns = DATASETS[dataset]
    for route in ("classic", "file"):
        for backend, cores, devices in (
            ("cpu", 1, "-"), ("cpu", 8, "-"),
            ("cuda", 1, "-"), ("cuda", 1, "0,1")
        ):
            if route == "classic" and devices != "-":
                continue
            for mode in ("pca", "tsne", "umap", "cluster"):
                if route == "classic" and mode == "cluster":
                    continue
                yield dict(name=f"{route}_{backend}{cores}_" +
                           ("gpu2_" if devices != "-" else "") + mode,
                           route=route, backend=backend, cores=cores,
                           devices=devices, mode=mode, rows=rows,
                           columns=columns, dataset=dataset)


def main(root):
    root.mkdir(parents=True, exist_ok=True)
    for dataset in DATASETS:
        path = root / dataset
        path.mkdir()
        rows = list(cases(dataset))
        with (path / "cases.tsv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, rows[0], delimiter="\t")
            writer.writeheader()
            writer.writerows(rows)
        with (path / "unsupported_routes.tsv").open("w") as handle:
            handle.write("route\tbackend\tdevices\treason\n")
            handle.write("classic\tcuda\t0,1\t"
                         "Classic fit does not accept devices.\n")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
