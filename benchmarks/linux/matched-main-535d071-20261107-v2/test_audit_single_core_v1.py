"""Check the exact seven-method pilot selection from the staged plan."""

import json
from pathlib import Path
import tempfile
import unittest

from audit_single_core_v1 import pilot_cases
from plan_scaling import HERE, expand_cases, write_plan
from policy import load_jsonl


class SingleCorePilotTests(unittest.TestCase):
    def test_mass41_cpu4_roster_is_exact(self):
        source = load_jsonl(HERE / "cases.jsonl")
        routes = json.loads((HERE / "routes.json").read_text())
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "plan"
            expanded = expand_cases(source, routes)
            write_plan(root, expanded)
            cases = [case for group in expanded.values()
                     for case in group]
            selected = pilot_cases(root, "mass41", 4, cases)
            self.assertEqual([index for index, _ in selected],
                             list(range(42, 49)))
            self.assertEqual(len({case["case_id"] for _, case in selected}), 7)


if __name__ == "__main__":
    unittest.main()
