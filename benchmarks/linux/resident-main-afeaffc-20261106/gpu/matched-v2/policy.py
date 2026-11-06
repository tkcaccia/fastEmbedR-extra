"""Pure planner and worker checks for resident HPC benchmark cases."""

from __future__ import annotations

import json
import math
import re
from pathlib import Path


COMPARISON_DATASETS = frozenset({
    "COIL20", "USPS", "MNIST", "Fashion-MNIST", "MetRef",
    "mass41", "flow18", "ImageNet features", "FlowRepository",
    "Tabula Muris", "Macosko retina",
})
METHODS = frozenset({"PCA", "t-SNE", "UMAP", "Leiden", "Louvain"})
DEEP1B_SOURCE_SHA256 = (
    "1178bb266619c2d7882795861772b50cb0e2bf111a3b786a188aa3ea6137c7c4"
)
REQUIRED = frozenset({
    "case_id", "dataset", "method", "implementation", "backend",
    "storage_mode", "runtime_input", "algorithm_state", "spill",
    "fit_scope", "dimensions", "cores", "gpus", "seed",
    "repetition", "scientific_tests", "warmup_fits", "route_id",
    "expected_rows", "expected_columns", "input_sha256",
    "preprocessing_rank", "quality_sample",
})


def reject(reason: str, status: str = "policy_rejected") -> dict:
    return {"status": status, "reason": reason}


def validate_case(case: dict, routes: dict) -> dict:
    """Return a status; never infer residency from a function name."""
    if not isinstance(case, dict):
        return reject("Case must be one JSON object.")
    missing = sorted(REQUIRED - case.keys())
    if missing:
        return reject("Missing fields: " + ", ".join(missing))
    if not isinstance(case["case_id"], str) or not re.fullmatch(
            r"[A-Za-z0-9_-]+", case["case_id"]):
        return reject("case_id must be a safe scalar identifier.")
    scalar = ("dataset", "method", "implementation", "backend",
              "storage_mode", "runtime_input", "algorithm_state",
              "fit_scope", "route_id")
    if any(not isinstance(case[key], str) for key in scalar):
        return reject("Case identity and route fields must be scalar text.")
    if (type(case["expected_rows"]) is not int or
            case["expected_rows"] < 2 or
            type(case["expected_columns"]) is not int or
            case["expected_columns"] < 3 or
            not isinstance(case["input_sha256"], str) or
            not re.fullmatch(r"[0-9a-f]{64}", case["input_sha256"])):
        return reject("Resident input identity or dimensions are invalid.")
    if (type(case["preprocessing_rank"]) is not int or
            case["preprocessing_rank"] != 30 or
            type(case["quality_sample"]) is not int or
            case["quality_sample"] != 600):
        return reject("Matched preprocessing or quality settings differ.")
    if case["storage_mode"] != "in_memory" or \
            case["runtime_input"] != "resident" or \
            case["algorithm_state"] != "resident" or \
            case["spill"] is not False:
        return reject("HPC input and algorithm state must remain resident.")
    if type(case["scientific_tests"]) is not int or \
            type(case["warmup_fits"]) is not int or \
            case["scientific_tests"] != 1 or case["warmup_fits"] != 0:
        return reject("One allocation may run one fit and no warm-up fit.")
    if case["dataset"] not in COMPARISON_DATASETS | {"Deep1B 10M"}:
        return reject("Dataset is outside the HPC campaign manifest.")
    if case["dataset"] == "Deep1B 10M" and (
            case["implementation"] != "fastEmbedR" or
            case.get("study") != "stress" or
            case.get("row_rule") != "source_row%100==0" or
            case.get("source_sha256") != DEEP1B_SOURCE_SHA256 or
            not isinstance(case.get("dataset_sha256"), str) or
            not re.fullmatch(r"[0-9a-f]{64}",
                             case["dataset_sha256"])):
        return reject("Deep1B is fastEmbedR stress only, with fixed rows.")
    if case["method"] not in METHODS:
        return reject("Method is outside the declared campaign.")
    tsne_controls = ("perplexity", "affinity_k",
                     "early_exaggeration_iter", "n_iter")
    if case["method"] == "t-SNE":
        perplexity = case.get("perplexity", 30)
        if type(perplexity) not in (int, float) or \
                not math.isfinite(perplexity) or perplexity <= 0:
            return reject("t-SNE perplexity must be positive and finite.")
        width = case.get("affinity_k")
        if width is not None and (type(width) is not int or
                width < math.ceil(perplexity)):
            return reject("t-SNE affinity_k must cover perplexity.")
        early = case.get("early_exaggeration_iter", 250)
        normal = case.get("n_iter", 500)
        if type(early) is not int or type(normal) is not int or \
                early < 0 or normal < 0 or early + normal < 1:
            return reject("t-SNE iteration counts are invalid.")
    elif any(key in case for key in tsne_controls):
        return reject("t-SNE controls belong to a t-SNE case only.")
    if case["fit_scope"] not in {
            "all_rows_optimized", "landmark_fit_plus_projection"}:
        return reject("Fit scope is missing or ambiguous.")
    if case["fit_scope"] == "landmark_fit_plus_projection":
        fractions = ((0.001, 0.005, 0.01, 0.05, 0.1)
                     if case["dataset"] == "Deep1B 10M" else
                     (0.01, 0.05, 0.1, 0.2, 0.5))
        if case["method"] not in ("PCA", "t-SNE", "UMAP",
                                 "Leiden", "Louvain") or \
                type(case.get("landmark_fraction")) not in (int, float) or \
                case["landmark_fraction"] not in fractions:
            return reject("Resident landmark method or fraction is invalid.")
        rows = case.get("expected_rows")
        if type(rows) is not int or rows < 2 or rows > 2_147_483_647:
            return reject("Landmark case needs an exact expected row count.")
        selected = math.ceil(rows * case["landmark_fraction"])
        if case["method"] == "PCA":
            if type(case["dimensions"]) is not int:
                return reject("PCA rank must be an integer.")
            minimum = case["dimensions"] + 1
        elif case["method"] in ("UMAP", "Leiden", "Louvain"):
            minimum = 31
        else:
            perplexity = case.get("perplexity", 30)
            if type(perplexity) not in (int, float) or \
                    not math.isfinite(perplexity) or perplexity <= 0:
                return reject("Landmark t-SNE perplexity is invalid.")
            if perplexity > (selected - 1) / 3:
                return reject("Landmark count is too small for perplexity.")
            width = case.get("affinity_k")
            if width is None:
                width = math.ceil(perplexity)
            elif type(width) is not int or width < 1:
                return reject("Landmark t-SNE width is invalid.")
            minimum = max(math.ceil(3 * perplexity) + 1,
                          width + 1)
        if selected < minimum or selected >= rows:
            return reject("Landmark count cannot support fit controls.")
    elif "landmark_fraction" in case:
        return reject("Full-data case must not declare landmarks.")
    counts = ("dimensions", "cores", "gpus", "seed", "repetition")
    if any(type(case[key]) is not int for key in counts):
        return reject("Dimension, resource, seed and repeat counts must be integers.")
    valid_dimensions = {
        "PCA": (2, 3, 50), "t-SNE": (2, 3),
        "UMAP": (2, 3), "Leiden": (0,), "Louvain": (0,),
    }
    if case["dimensions"] not in valid_dimensions[case["method"]] or \
            case["cores"] not in (1, 2, 4, 8, 16, 32) or \
            case["gpus"] not in (0, 1, 2, 3) or \
            case["repetition"] < 1:
        return reject("Requested dimensions or resource counts are invalid.")
    if case["backend"] == "cpu":
        if case["gpus"] != 0:
            return reject("CPU case must not allocate GPUs.")
    elif case["backend"] == "cuda":
        if case["gpus"] == 0:
            return reject("CUDA case requires allocated GPUs.")
    else:
        return reject("HPC backend must be CPU or CUDA.")
    route = routes.get(case["route_id"])
    if not isinstance(route, dict) or \
            route.get("verified_resident") is not True:
        return reject("No verified resident implementation for route.",
                      "blocked_missing_in_memory_implementation")
    if route.get("method") != case["method"] or \
            route.get("implementation") != case["implementation"] or \
            route.get("backend") != case["backend"] or \
            case["dataset"] not in route.get("datasets", []) or \
            case["gpus"] not in route.get("gpu_counts", []) or \
            case["fit_scope"] not in route.get("fit_scopes", []) or \
            case["dimensions"] not in route.get("dimensions", []):
        return reject("Verified route does not support this case.",
                      "blocked_missing_in_memory_implementation")
    if case["gpus"] > 1 and route.get("coordinated") is not True:
        return reject("Multi-GPU case needs one coordinated resident fit.",
                      "blocked_missing_in_memory_implementation")
    if route.get("worker") != "fastembedr_resident_r":
        return reject("Route has no reviewed resident worker.",
                      "blocked_missing_in_memory_implementation")
    return {"status": "eligible", "reason": "resident route declared"}


def validate_plan(cases: list[dict], routes: dict) -> list[dict]:
    """Keep every request, but never mark duplicate IDs eligible."""
    seen = set()
    outcomes = []
    for case in cases:
        result = validate_case(case, routes)
        case_id = case.get("case_id") if isinstance(case, dict) else None
        if case_id in seen:
            result = reject("Duplicate case_id in plan.")
        seen.add(case_id)
        outcomes.append({"case_id": case_id, **result})
    return outcomes


def load_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()
            if line.strip()]
