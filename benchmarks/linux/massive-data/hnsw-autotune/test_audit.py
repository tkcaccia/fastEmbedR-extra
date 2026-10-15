#!/usr/bin/env python3
"""Focused checks for recall-constrained speed screening."""

import unittest

from audit import projected_seconds, recommendation


def candidate(m, build, query, recall=0.995, rows=20000):
    return dict(dataset="deep", scope="pilot", shard_rows="20000",
                k="30", split="tune", m=str(m),
                ef_construction="80", ef_search="120",
                fit_rows=str(rows), n_queries="1024",
                build_seconds=str(build), query_seconds=str(query),
                timing_median_seconds=str(query), timing_queries="2048",
                collect_seconds="0", merge_seconds="0",
                lower_95_recall=str(recall))


class SpeedScreenTest(unittest.TestCase):
    def test_query_heavy_workload_prefers_fast_search(self):
        rows = [candidate(12, 1, 20), candidate(24, 5, 2)]
        self.assertEqual(recommendation(rows, "deep", "pilot",
                                        "20000", "30")["m"], "24")

    def test_build_heavy_workload_prefers_fast_build(self):
        rows = [candidate(12, 1, 20, rows=100),
                candidate(24, 5, 2, rows=100)]
        self.assertEqual(recommendation(rows, "deep", "pilot",
                                        "20000", "30")["m"], "12")

    def test_recall_gate_and_measured_query_count(self):
        rows = [candidate(12, 1, 1, recall=0.98),
                candidate(24, 5, 2)]
        self.assertEqual(recommendation(rows, "deep", "pilot",
                                        "20000", "30")["m"], "24")
        self.assertEqual(projected_seconds(rows[1], 2048), 7)
        rows[1]["timing_queries"] = "128"
        rows[1]["timing_median_seconds"] = "0.125"
        rows[1]["collect_seconds"] = "1"
        rows[1]["merge_seconds"] = "1"
        self.assertEqual(projected_seconds(rows[1], 2048), 9)
        self.assertIsNone(recommendation(rows[:1], "deep", "pilot",
                                         "20000", "30"))


if __name__ == "__main__":
    unittest.main()
