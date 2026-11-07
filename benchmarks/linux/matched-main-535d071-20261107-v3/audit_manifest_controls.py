"""Audit whether each v3 manifest declares the worker's fit controls.

This independent audit does not modify the source-locked HPC worker or cases.
It reports a publication contract gap even when the worker's fixed defaults
would execute the intended calculation.
"""

from __future__ import annotations

import collections
import json
import sys
from pathlib import Path


CONTROLS = {
    "t-SNE": {
        "perplexity": 30,
        "early_exaggeration_iter": 250,
        "n_iter": 300,
        "auto_config": False,
    },
    "UMAP": {"n_neighbors": 30},
    "Leiden": {"graph_k": 30},
    "Louvain": {"graph_k": 30},
}


def audit(path: Path) -> dict:
    counts = collections.Counter()
    examples = {}
    total = 0
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        case = json.loads(line)
        total += 1
        for field, expected in CONTROLS.get(case["method"], {}).items():
            if field not in case:
                issue = f"{case['method']}:missing:{field}"
            elif case[field] != expected or type(case[field]) is not \
                    type(expected):
                issue = f"{case['method']}:mismatch:{field}"
            else:
                continue
            counts[issue] += 1
            examples.setdefault(issue, case["case_id"])
    return {"cases": total, "issues": dict(sorted(counts.items())),
            "examples": dict(sorted(examples.items()))}


if __name__ == "__main__":
    source = (Path(sys.argv[1]) if len(sys.argv) == 2 else
              Path(__file__).with_name("cases.jsonl"))
    result = audit(source)
    print(json.dumps(result, sort_keys=True, indent=2))
    sys.exit(bool(result["issues"]))
