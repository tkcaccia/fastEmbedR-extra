import copy
import json
from pathlib import Path
import tempfile
import unittest

from plan_scaling import CORES, HERE, expand_cases, write_plan
from policy import load_jsonl, validate_plan


class ScalingPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = load_jsonl(HERE / "cases.jsonl")
        cls.routes = json.loads((HERE / "routes.json").read_text())

    def test_all_six_core_counts_keep_exact_resident_scope(self):
        expanded = expand_cases(self.source, self.routes)
        self.assertEqual(tuple(expanded), CORES)
        self.assertEqual(sum(map(len, expanded.values())), 462)
        self.assertEqual(len({case["case_id"] for cases in expanded.values()
                              for case in cases}), 462)
        self.assertTrue(all(item["status"] == "eligible"
            for cases in expanded.values()
            for item in validate_plan(cases, self.routes)))
        for cores, cases in expanded.items():
            for source, case in zip(self.source, cases):
                original = {key: value for key, value in source.items()
                            if key not in ("case_id", "cores")}
                scaled = {key: value for key, value in case.items()
                          if key not in ("case_id", "cores")}
                self.assertEqual(original, scaled)
                self.assertEqual(case["cores"], cores)
                self.assertEqual(case["gpus"], 0)
                self.assertIs(case["spill"], False)
        self.assertTrue(all(case["cores"] == 4 for case in self.source))

    def test_rejects_storage_or_scope_mutation_before_generation(self):
        for key, value in (("storage_mode", "file_backed"),
                           ("runtime_input", "stream"),
                           ("algorithm_state", "mmap"),
                           ("spill", True),
                           ("scientific_tests", 2),
                           ("fit_scope", "landmark_fit_plus_projection")):
            changed = copy.deepcopy(self.source)
            changed[0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                expand_cases(changed, self.routes)

    def test_plan_is_written_once_with_one_case_per_array_element(self):
        expanded = expand_cases(self.source, self.routes)
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / "scaling"
            write_plan(target, expanded)
            summary = json.loads((target / "plan-summary.json").read_text())
            self.assertEqual(summary["total_cases"], 462)
            self.assertEqual(summary["scientific_tests_per_allocation"], 1)
            self.assertEqual(summary["warmup_fits_per_allocation"], 0)
            self.assertEqual(len(list((target / "cases").glob("*.json"))), 462)
            self.assertEqual((target / "matched_worker.R").read_bytes(),
                             (HERE / "matched_worker_scaling.R").read_bytes())
            for name in ("run_case.py", "policy.py", "routes.json"):
                self.assertEqual((target / name).read_bytes(),
                                 (HERE / name).read_bytes())
            worker = (target / "matched_worker.R").read_text()
            self.assertIn("fit$n.cores_effective", worker)
            self.assertIn("fit$parameters$n.cores_effective", worker)
            self.assertIn("cores_effective", worker)
            self.assertIn("Effective CPU worker count differs", worker)
            for cores in CORES:
                names = (target / f"wave_cpu{cores}.txt").read_text().splitlines()
                self.assertEqual(len(names), 77)
                self.assertEqual(len(set(names)), 77)
                self.assertTrue(all((target / "cases" /
                    (name + ".json")).is_file() for name in names))
                script = (target / f"wave_cpu{cores}.sbatch").read_text()
                self.assertIn(f"#SBATCH --cpus-per-task={cores}\n", script)
                self.assertIn("#SBATCH --partition=ada\n", script)
                self.assertIn("CUDA_VISIBLE_DEVICES", script)
                self.assertIn("FastEmbedRCommit=77b852fc", script)
                self.assertIn('"$root/run_case.py"', script)
                self.assertNotIn("--gres=", script)
                self.assertNotIn("--gpus=", script)
            with self.assertRaises(FileExistsError):
                write_plan(target, expanded)


if __name__ == "__main__":
    unittest.main()
