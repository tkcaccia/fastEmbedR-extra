import unittest

from preflight_fullgraph import storage_plan


class StoragePlanTest(unittest.TestCase):
    def test_billion_admission_excludes_existing_input(self):
        plan = storage_plan(1_000_000_000, "full", 2_000_000_000_000)
        self.assertEqual(plan["required_bytes"], 632_000_000_008)
        self.assertEqual(plan["worst_case_bytes"], 1_352_000_000_008)
        self.assertTrue(plan["later_bucket_check_required"])
        self.assertEqual(plan["required_bytes_kind"],
                         "initial_admission")
        self.assertEqual(plan["status"], "READY")

    def test_billion_full_graph_is_blocked_without_margin(self):
        plan = storage_plan(1_000_000_000, "full", 5_000_000_000_000,
                            700_000_000_000)
        self.assertEqual(plan["status"], "BLOCKED_SPACE")
        self.assertEqual(plan["required_bytes"], 632_000_000_008)

    def test_admitted_run_may_need_more_space_after_bucketing(self):
        plan = storage_plan(1_000_000_000, "full", 800_000_000_000)
        self.assertEqual(plan["status"], "READY")
        self.assertGreater(plan["worst_case_bytes"],
                           plan["available_bytes"])

    def test_hundred_million_requires_explicit_capacity(self):
        blocked = storage_plan(100_000_000, "full", 70_000_000_000)
        ready = storage_plan(100_000_000, "full", 80_000_000_000)
        self.assertEqual(blocked["status"], "BLOCKED_SPACE")
        self.assertEqual(ready["status"], "READY")

    def test_single_method_routes_reclaim_unused_layouts(self):
        full = storage_plan(100_000_000, "full", 650_000_000_000)
        tsne = storage_plan(100_000_000, "full_tsne",
                            650_000_000_000)
        umap = storage_plan(100_000_000, "full_umap",
                            650_000_000_000)
        self.assertEqual(full["required_bytes"], 63_200_000_008)
        self.assertEqual(tsne["required_bytes"], 38_400_786_440)
        self.assertEqual(umap["required_bytes"], 38_400_786_440)
        self.assertEqual(tsne["worst_case_bytes"], 110_400_000_008)
        self.assertEqual(umap["worst_case_bytes"], 110_400_000_008)

    def test_rebuilt_knn_lowers_combined_ceiling(self):
        plan = storage_plan(1_000_000_000, "full",
                            2_000_000_000_000, rebuild_knn=True)
        self.assertEqual(plan["required_bytes"], 392_000_786_440)
        self.assertEqual(plan["worst_case_bytes"], 1_112_000_000_008)
        self.assertEqual(plan["knn_builds"], 2)
        self.assertTrue(plan["rebuild_knn_for_umap"])
        self.assertEqual(plan["scope"], "graph_stage")
        self.assertIn("clustering", plan["excludes"])
        self.assertTrue(plan["worst_case_fits_margin"])
        with self.assertRaises(ValueError):
            storage_plan(100_000, "full_umap", 1_000_000_000,
                         rebuild_knn=True)

    def test_billion_pca_does_not_need_a_graph(self):
        plan = storage_plan(1_000_000_000, "pca", 700_000_000_000)
        self.assertEqual(plan["status"], "READY")
        self.assertFalse(plan["later_bucket_check_required"])


if __name__ == "__main__":
    unittest.main()
