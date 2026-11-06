#!/usr/bin/env python3
"""Turn audited Mac Deep1B 100M evidence into a JSS supplement table."""

import csv
import json
import math
import sys
from pathlib import Path


STAGES = (
    "smoke_fullgraph", "pca_cpu1", "pca_cpu8", "pca_cpu20",
    "pca_cpu28", "pca_metal", "knn_cpu20", "tsne_affinity",
    "tsne_cpu20", "umap_membership", "umap_fuzzy", "umap_metal",
    "umap_cpu20", "umap_cpu1", "leiden_cpu",
)
LABELS = {
    "smoke_fullgraph": "Full-graph smoke test",
    "pca_cpu1": "PCA CPU 1 thread",
    "pca_cpu8": "PCA CPU 8 threads",
    "pca_cpu20": "PCA CPU 20 threads",
    "pca_cpu28": "PCA CPU 28 threads",
    "pca_metal": "PCA Metal",
    "knn_cpu20": "30-neighbor HNSW CPU 20 threads",
    "tsne_affinity": "t-SNE affinities CPU",
    "tsne_cpu20": "t-SNE 750 iterations CPU 20 threads",
    "umap_membership": "UMAP directed weights CPU",
    "umap_fuzzy": "UMAP fuzzy union CPU",
    "umap_metal": "UMAP 200 epochs Metal",
    "umap_cpu20": "UMAP 200 epochs CPU 20 threads",
    "umap_cpu1": "UMAP 200 epochs CPU 1 thread",
    "leiden_cpu": "Leiden CPU",
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def read_one(path):
    with path.open(newline="") as stream:
        records = list(csv.DictReader(stream))
    require(len(records) == 1, f"Expected one row: {path}")
    return records[0]


def evidence(run):
    audit = run / "postprocess-audit-v1"
    require((run / "postprocess/postprocess.exit").read_text().strip() ==
            "0", "Independent postprocess did not pass")
    metadata = json.loads((audit / "audit.json").read_text())
    require(metadata.get("status") == "passed" and
            metadata.get("rows") == 100_000_000 and
            metadata.get("neighbors") == 30 and
            metadata.get("stage_count") == len(STAGES),
            "Byte audit is incomplete")
    with (audit / "stages.csv").open(newline="") as stream:
        stages = list(csv.DictReader(stream))
    require([row["stage"] for row in stages] == list(STAGES),
            "Expected stage order changed")
    graph = read_one(audit / "graph_audit.csv")
    require(int(graph["rows"]) == 100_000_000 and
            int(graph["neighbors"]) == 30 and
            int(graph["recall_sample_size"]) == 32,
            "Graph audit dimensions changed")
    require(graph["recall_gate_pass"] in ("TRUE", "FALSE"),
            "Recall quality outcome is missing")
    return stages, graph


def table_rows(stages):
    rows = []
    for item in stages:
        seconds = int(item["wall_seconds"])
        free = float(item["free_pct_min"])
        peak = (int(item["peak_rss_bytes"])
                if item["peak_rss_bytes"] else None)
        edges = int(item["graph_edges"]) if item["graph_edges"] else None
        require(seconds >= 0 and math.isfinite(free) and free >= 50 and
                (peak is None or peak >= 0) and
                (edges is None or edges > 0),
                f"Invalid stage evidence: {item['stage']}")
        rows.append({
            "stage": item["stage"], "label": LABELS[item["stage"]],
            "wall_seconds": seconds,
            "wall_hours": round(seconds / 3600, 4),
            "peak_rss_gib": "" if peak is None else
                round(peak / 2**30, 3),
            "minimum_free_memory_pct": free,
            "directed_edges": "" if edges is None else edges,
        })
    return rows


def tex(rows, graph):
    result = [
        r"\begin{longtable}{lrrrr}",
        r"\caption{Deep1B 100 million row Mac run, using every tenth "
        r"original row and 30 neighbors. Timings are single observed "
        r"wall times; the stages use different methods and are not "
        r"end-to-end speed comparisons. Peak RSS is per worker; free "
        r"memory is the lowest system percentage measured by the guard. "
        r"No SSD streaming was used on the HPC.}"
        r"\label{tab:deep1b-100m-mac}" + "\\\\",
        r"\toprule",
        r"Stage & Hours & Peak RSS (GiB) & Free RAM (\%) & Edges "
        + "\\\\",
        r"\midrule", r"\endfirsthead", r"\toprule",
        r"Stage & Hours & Peak RSS (GiB) & Free RAM (\%) & Edges "
        + "\\\\", r"\midrule", r"\endhead",
    ]
    for row in rows:
        peak = row["peak_rss_gib"]
        edge = row["directed_edges"]
        result.append(" & ".join((
            row["label"], f'{row["wall_hours"]:.2f}',
            "NA" if peak == "" else f"{peak:.2f}",
            f'{row["minimum_free_memory_pct"]:.1f}',
            "NA" if edge == "" else f"{edge:,}")) + " \\\\")
    result.extend((r"\bottomrule", r"\end{longtable}"))
    result.append(
        "Sampled 30-neighbor strict ID recall over "
        f"{graph['recall_sample_size']} rows: mean "
        f"{float(graph['recall_mean']):.4f}, minimum "
        f"{float(graph['recall_min']):.4f}; "
        f"{graph['rows_below_target']} rows below 0.99. "
        "This is a sample diagnostic, not a whole-graph guarantee.")
    return "\n".join(result) + "\n"


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: script.py DEEP1B_RUN_ROOT")
    run = Path(sys.argv[1]).resolve()
    require(str(run).startswith(
            "/Users/silvanopiazza/Documents/Stefano/"),
            "Report output must remain under Stefano")
    stages, graph = evidence(run)
    rows = table_rows(stages)
    output = run / "report"
    output.mkdir(exist_ok=False)
    with (output / "deep1b_100m_mac_stages.csv").open(
            "w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    (output / "deep1b_100m_mac_stages.tex").write_text(
        tex(rows, graph))
    print("Saved 15 audited 100M stage observations")


if __name__ == "__main__":
    main()
