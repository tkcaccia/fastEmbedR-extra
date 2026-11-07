"""The independent control audit must find missing and changed settings."""

import json
import tempfile
import unittest
from pathlib import Path

from audit_manifest_controls import audit


class ManifestControlAuditTest(unittest.TestCase):
    def check(self, cases):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "cases.jsonl"
            path.write_text("\n".join(json.dumps(x) for x in cases))
            return audit(path)

    def test_complete_controls_pass(self):
        cases = [{"case_id": "t", "method": "t-SNE",
                  "perplexity": 30, "early_exaggeration_iter": 250,
                  "n_iter": 300, "auto_config": False},
                 {"case_id": "u", "method": "UMAP",
                  "n_neighbors": 30},
                 {"case_id": "l", "method": "Leiden",
                  "graph_k": 30}]
        self.assertEqual(self.check(cases)["issues"], {})

    def test_missing_and_mismatched_controls_fail(self):
        cases = [{"case_id": "t", "method": "t-SNE",
                  "perplexity": 30, "early_exaggeration_iter": 250,
                  "n_iter": 300},
                 {"case_id": "u", "method": "UMAP",
                  "n_neighbors": 29}]
        self.assertEqual(self.check(cases)["issues"], {
            "t-SNE:missing:auto_config": 1,
            "UMAP:mismatch:n_neighbors": 1,
        })


if __name__ == "__main__":
    unittest.main()
