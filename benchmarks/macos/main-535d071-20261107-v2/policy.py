"""Admission checks for one resident Mac CPU or Metal case."""

from pathlib import Path
import re


ROOT = Path("/Users/silvanopiazza/Documents/Stefano")
METHODS = {"PCA", "t-SNE", "UMAP", "Leiden", "Louvain"}
DATASETS = {"COIL20", "USPS", "MNIST", "Fashion-MNIST",
            "MetRef", "mass41", "flow18", "ImageNet features",
            "FlowRepository", "Tabula Muris", "Macosko retina"}
REQUIRED = {"case_id", "dataset", "input_path", "input_sha256",
            "source_dir", "source_sha256", "dll_sha256", "output_dir",
            "method", "backend", "cores", "seed", "repetition",
            "dimensions", "pca_rank", "expected_rows", "expected_columns",
            "storage_mode", "fit_scope", "timeout_seconds",
            "quality_sample", "spill", "scientific_tests", "warmup_fits"}


def under_stefano(value):
    if not isinstance(value, str):
        return False
    path = Path(value)
    try:
        return path.is_absolute() and path != ROOT and \
            path.is_relative_to(ROOT) and path.resolve().is_relative_to(ROOT)
    except OSError:
        return False


def valid_case(case):
    if not isinstance(case, dict) or set(case) != REQUIRED:
        return False
    if not isinstance(case["case_id"], str) or not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9_.-]{0,95}", case["case_id"]):
        return False
    if not isinstance(case["dataset"], str) or \
            not isinstance(case["method"], str) or \
            case["dataset"] not in DATASETS or case["method"] not in METHODS:
        return False
    if not isinstance(case["backend"], str) or \
            type(case["cores"]) is not int or \
            case["backend"] not in {"cpu", "metal"} or \
            case["cores"] not in {1, 2, 4, 8, 16} or \
            (case["backend"] == "metal" and case["cores"] != 1):
        return False
    if not isinstance(case["storage_mode"], str) or \
            not isinstance(case["fit_scope"], str) or \
            case["storage_mode"] != "resident" or \
            case["fit_scope"] != "full" or case["spill"] is not False or \
            type(case["scientific_tests"]) is not int or \
            type(case["warmup_fits"]) is not int or \
            case["scientific_tests"] != 1 or case["warmup_fits"] != 0:
        return False
    positive = ("seed", "repetition", "pca_rank", "expected_rows",
                "expected_columns", "timeout_seconds", "quality_sample")
    if any(type(case[key]) is not int or case[key] < 1 for key in positive):
        return False
    long_tsne = (case["method"] == "t-SNE" and
                 case["dimensions"] == 3 and
                 case["expected_rows"] >= 500000)
    ceiling = 7200 if long_tsne else 1800
    if type(case["dimensions"]) is not int or \
            case["timeout_seconds"] > ceiling or \
            case["quality_sample"] > case["expected_rows"] or \
            case["pca_rank"] > min(case["expected_rows"],
                                   case["expected_columns"]):
        return False
    if case["method"] == "PCA":
        if case["dimensions"] < 1 or case["dimensions"] > min(
                case["expected_rows"], case["expected_columns"]):
            return False
    elif case["method"] in {"t-SNE", "UMAP"}:
        if case["dimensions"] not in {2, 3} or \
                case["pca_rank"] < case["dimensions"] or \
                case["pca_rank"] >= min(case["expected_rows"],
                                         case["expected_columns"]):
            return False
    elif case["dimensions"] != 0:
        return False
    if not all(under_stefano(case[key]) for key in
               ("input_path", "source_dir", "output_dir")):
        return False
    return all(isinstance(case[key], str) and re.fullmatch(
        r"[0-9a-f]{64}", case[key]) for key in
        ("input_sha256", "source_sha256", "dll_sha256"))
