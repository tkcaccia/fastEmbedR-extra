"""Fail-closed checks for the matched Mac t-SNE case."""

import json
from pathlib import Path
import unittest

from policy import valid_case


HERE = Path(__file__).resolve().parent


class MatchedTsnePolicyTests(unittest.TestCase):
    def case(self):
        return json.loads((HERE / "pilot-case.json").read_text())

    def test_pilot_admitted(self):
        self.assertTrue(valid_case(self.case()))

    def test_scientific_controls_are_exact(self):
        for name, value in (("perplexity", 31),
                            ("early_exaggeration_iter", 249),
                            ("n_iter", 301),
                            ("auto_config", True)):
            with self.subTest(name=name):
                case = self.case()
                case["fit_controls"][name] = value
                self.assertFalse(valid_case(case))

    def test_storage_backend_and_scope_are_bounded(self):
        for name, value in (("storage_mode", "file_backed"),
                            ("fit_scope", "landmark"),
                            ("spill", True),
                            ("method", "UMAP"),
                            ("backend", "cuda"),
                            ("scientific_tests", 2),
                            ("warmup_fits", 1)):
            with self.subTest(name=name):
                case = self.case()
                case[name] = value
                self.assertFalse(valid_case(case))

    def test_extra_fields_and_paths_are_rejected(self):
        case = self.case()
        case["extra"] = True
        self.assertFalse(valid_case(case))
        case = self.case()
        case["output_dir"] = "/tmp/output"
        self.assertFalse(valid_case(case))


if __name__ == "__main__":
    unittest.main()
