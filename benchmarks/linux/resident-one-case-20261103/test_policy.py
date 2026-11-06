"""Safety checks for the resident one-case HPC entry point."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from policy import DEEP1B_SOURCE_SHA256, validate_case, validate_plan
from run_case import (
    allocation_matches, allocation_identity, claim_allocation,
)


HERE = Path(__file__).resolve().parent
ROUTES = json.loads((HERE / "routes.json").read_text())


def cpu_case() -> dict:
    return {
        "case_id": "coil20_pca_cpu2_seed4_rep1",
        "dataset": "COIL20",
        "method": "PCA",
        "implementation": "fastEmbedR",
        "backend": "cpu",
        "storage_mode": "in_memory",
        "runtime_input": "resident",
        "algorithm_state": "resident",
        "spill": False,
        "fit_scope": "all_rows_optimized",
        "dimensions": 2,
        "cores": 2,
        "gpus": 0,
        "seed": 4,
        "repetition": 1,
        "scientific_tests": 1,
        "warmup_fits": 0,
        "route_id": "fastembedr_cpu_pca",
    }


class ResidentPolicyTests(unittest.TestCase):
    def test_eligible_cpu_case(self):
        self.assertEqual(validate_case(cpu_case(), ROUTES)["status"],
                         "eligible")

    def test_no_file_backed_input_state_or_spill(self):
        for field, value in (
            ("storage_mode", "file_backed"),
            ("runtime_input", "mmap"),
            ("algorithm_state", "streamed"),
            ("spill", True),
        ):
            with self.subTest(field=field):
                case = cpu_case()
                case[field] = value
                self.assertEqual(validate_case(case, ROUTES)["status"],
                                 "policy_rejected")

    def test_one_fit_and_no_warmup(self):
        for field, value in (("scientific_tests", 2),
                             ("warmup_fits", 1)):
            case = cpu_case()
            case[field] = value
            self.assertEqual(validate_case(case, ROUTES)["status"],
                             "policy_rejected")

    def test_unqualified_cuda_and_deep1b_are_blocked(self):
        cuda = cpu_case()
        cuda.update(backend="cuda", gpus=2)
        self.assertEqual(validate_case(cuda, ROUTES)["status"],
                         "blocked_missing_in_memory_implementation")
        deep = cpu_case()
        deep.update(dataset="Deep1B 10M", study="stress",
                    row_rule="source_row%100==0",
                    source_sha256=DEEP1B_SOURCE_SHA256,
                    dataset_sha256="a" * 64)
        self.assertEqual(validate_case(deep, ROUTES)["status"],
                         "blocked_missing_in_memory_implementation")
        deep["row_rule"] = "source_row%10==0"
        self.assertEqual(validate_case(deep, ROUTES)["status"],
                         "policy_rejected")

    def test_tsne_affinity_width_and_iterations_are_explicit(self):
        case = cpu_case()
        case.update(method="t-SNE", route_id="fastembedr_cpu_tsne",
                    perplexity=30, affinity_k=90,
                    early_exaggeration_iter=250, n_iter=500)
        self.assertEqual(validate_case(case, ROUTES)["status"],
                         "eligible")
        for changes in ({"affinity_k": 29}, {"affinity_k": 90.5},
                        {"n_iter": -1}, {"perplexity": float("nan")}):
            with self.subTest(changes=changes):
                invalid = dict(case, **changes)
                self.assertEqual(validate_case(invalid, ROUTES)["status"],
                                 "policy_rejected")
        unrelated = dict(cpu_case(), affinity_k=90)
        self.assertEqual(validate_case(unrelated, ROUTES)["status"],
                         "policy_rejected")

    def test_resident_embedding_landmark_routes_and_fraction(self):
        case = cpu_case()
        case.update(case_id="coil20_pca_landmark_cpu2_seed4_rep1",
                    fit_scope="landmark_fit_plus_projection",
                    route_id="fastembedr_cpu_pca_landmark",
                    landmark_fraction=0.5, expected_rows=120)
        self.assertEqual(validate_case(case, ROUTES)["status"],
                         "eligible")
        for method, route in (("t-SNE", "fastembedr_cpu_tsne_landmark"),
                              ("UMAP", "fastembedr_cpu_umap_landmark"),
                              ("Leiden", "fastembedr_cpu_leiden_landmark"),
                              ("Louvain", "fastembedr_cpu_louvain_landmark")):
            embedding = dict(case, method=method, route_id=route)
            if method in ("Leiden", "Louvain"):
                embedding["dimensions"] = 0
            if method == "t-SNE":
                embedding.update(perplexity=3, affinity_k=9,
                                 early_exaggeration_iter=1, n_iter=2)
            self.assertEqual(validate_case(embedding, ROUTES)["status"],
                             "eligible")
        for changes in ({"landmark_fraction": 0.3},
                        {"fit_scope": "all_rows_optimized"},
                        {"method": "Walktrap"}):
            with self.subTest(changes=changes):
                invalid = dict(case, **changes)
                self.assertEqual(validate_case(invalid, ROUTES)["status"],
                                 "policy_rejected")
        short = dict(case, method="UMAP",
                     route_id="fastembedr_cpu_umap_landmark",
                     expected_rows=48)
        self.assertEqual(validate_case(short, ROUTES)["status"],
                         "policy_rejected")
        short_tsne = dict(case, method="t-SNE",
                          route_id="fastembedr_cpu_tsne_landmark",
                          perplexity=30)
        self.assertEqual(validate_case(short_tsne, ROUTES)["status"],
                         "policy_rejected")
        missing = dict(case)
        del missing["expected_rows"]
        self.assertEqual(validate_case(missing, ROUTES)["status"],
                         "policy_rejected")

    def test_duplicate_ids_cannot_be_eligible(self):
        outcomes = validate_plan([cpu_case(), cpu_case()], ROUTES)
        self.assertEqual(outcomes[0]["status"], "eligible")
        self.assertEqual(outcomes[1]["status"], "policy_rejected")

    def test_worker_requires_matching_slurm_allocation(self):
        valid = {
            "SLURM_JOB_ID": "12345",
            "SLURM_NTASKS": "1",
            "SLURM_CPUS_PER_TASK": "2",
            "CUDA_VISIBLE_DEVICES": "",
        }
        with patch.dict("os.environ", valid, clear=True):
            self.assertTrue(allocation_matches(cpu_case()))
        with patch.dict("os.environ", {**valid,
                        "CUDA_VISIBLE_DEVICES": "0"}, clear=True):
            self.assertFalse(allocation_matches(cpu_case()))
        with patch.dict("os.environ", {**valid,
                        "SLURM_CPUS_PER_TASK": "1"}, clear=True):
            self.assertFalse(allocation_matches(cpu_case()))

    def test_one_allocation_cannot_claim_two_scientific_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertTrue(claim_allocation(root, "12345", "first"))
            self.assertFalse(claim_allocation(root, "12345", "second"))
            marker = json.loads((root / ".slurm-12345.claim").read_text())
            self.assertEqual(marker["case_id"], "first")
            self.assertTrue(claim_allocation(root, "12346", "second"))

    def test_array_elements_have_distinct_allocation_claims(self):
        with patch.dict("os.environ", {
                "SLURM_JOB_ID": "12345",
                "SLURM_ARRAY_TASK_ID": "2",
                "SLURM_NTASKS": "1",
                "SLURM_CPUS_PER_TASK": "2",
                "CUDA_VISIBLE_DEVICES": ""}, clear=True):
            self.assertEqual(allocation_identity(), "12345_2")
            self.assertTrue(allocation_matches(cpu_case()))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertTrue(claim_allocation(root, "12345_2", "first"))
            self.assertTrue(claim_allocation(root, "12345_3", "second"))

    @unittest.skipUnless(shutil.which("Rscript"), "Rscript is unavailable")
    def test_r_worker_rejects_forbidden_input_and_unallocated_gpu(self):
        cases = (
            ({"storage_mode": "file_backed"},
             "Resident one-case contract is not satisfied"),
            ({"backend": "cuda", "gpus": 1},
             "Worker GPU visibility does not match"),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for index, (changes, message) in enumerate(cases):
                case = dict(cpu_case(), **changes)
                path = root / f"case_{index}.json"
                path.write_text(json.dumps(case))
                result = subprocess.run(
                    ["Rscript", str(HERE / "worker.R"), str(path),
                     str(root), str(root)],
                    env={**os.environ, "CUDA_VISIBLE_DEVICES": ""},
                    capture_output=True, text=True, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)


if __name__ == "__main__":
    unittest.main()
