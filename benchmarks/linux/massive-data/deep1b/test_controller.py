"""Focused checks for automatic queue planning and failure gates."""

import csv
import json
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import controller


class ControllerTest(unittest.TestCase):
    def test_image_identity_omits_node_local_device_number(self):
        suite = Path(__file__).parent
        formats = []
        for name in ("slurm_preflight.sbatch", "run_case.sh"):
            script = (suite / name).read_text()
            match = re.search(r"stat -Lc '([^']+)'", script)
            self.assertIsNotNone(match)
            formats.append(match.group(1))
        self.assertEqual(formats, ["%i:%s:%Y"] * 2)

    def test_selects_only_tuning_rows(self):
        rows = [dict(dataset="deep", split="tune", recall_gate="True",
                     consistency_gate="True", build_seconds="100",
                     query_seconds="20", m="32", ef_construction="200",
                     ef_search="150"),
                dict(dataset="deep", split="tune", recall_gate="True",
                     consistency_gate="True", build_seconds="70",
                     query_seconds="10", m="24", ef_construction="160",
                     ef_search="80"),
                dict(dataset="deep", split="holdout",
                     recall_gate="True", consistency_gate="True",
                     build_seconds="1", query_seconds="1", m="48",
                     ef_construction="300", ef_search="240")]
        self.assertEqual(controller.selected_controls(rows, "deep"),
                         dict(m=24, ef_construction=160, ef_search=80))
        self.assertIsNone(controller.selected_controls(rows, "turing"))

    def test_plan_keeps_cpu_gpu_and_graph_order(self):
        plan = controller.make_plan(2, {"deep": None,
                                        "turing": dict(m=32,
                                        ef_construction=200,
                                        ef_search=240)})
        self.assertEqual(len(plan), 18)
        self.assertEqual(plan[0]["phase"], "threads1m")
        self.assertEqual(plan[8]["phase"], "screen")
        self.assertEqual(plan[10]["policy"], "shape")
        self.assertEqual(plan[11]["policy"], "selected")
        self.assertTrue(all(row["lane"] == "cpu" for row in plan[:12]))
        self.assertTrue(all(row["lane"] == "cuda" for row in plan[12:]))

    def test_recall_gap_does_not_hide_hard_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            campaign = root / "campaign"
            campaign.mkdir()
            record = dict(phase="threads1m", campaign=str(campaign))
            state = dict(quality_gaps=[])
            (campaign / "audit.json").write_text(json.dumps(dict(
                case_count=16,
                failures=["cpu_knn: sampled KNN recall 0.95 < 0.99"])))
            controller.audit_previous(state, record)
            self.assertEqual(len(state["quality_gaps"]), 1)
            self.assertIn("audited", record)
            (campaign / "audit.json").write_text(json.dumps(dict(
                case_count=16,
                failures=["cuda_pca: GPU memory evidence unavailable"])))
            with self.assertRaisesRegex(ValueError, "GPU memory evidence"):
                controller.audit_previous(state, record)

    def test_comprehensive_plan_separates_lanes_and_scales(self):
        cpu = controller.make_comprehensive_plan("cpu", 3)
        cuda = controller.make_comprehensive_plan("cuda", 3)
        self.assertTrue(all(row["lane"] == "cpu" for row in cpu))
        self.assertTrue(all(row["lane"] == "cuda" for row in cuda))
        self.assertEqual(sum(row["phase"] == "threads1m" for row in
                             cpu), 2)
        self.assertFalse(any(row["phase"] == "threads1m" for row in
                             cuda))
        for plan in (cpu, cuda):
            self.assertEqual(sum(row["phase"] == "scale10m" for row in
                                 plan), 6)
            self.assertEqual(sum(row["phase"] == "billion" for row in
                                 plan), 2)
            self.assertEqual(plan[-1]["phase"], "graph10m")
        deep_cpu = controller.make_comprehensive_plan("cpu", 3, "deep")
        self.assertTrue(all(row["dataset"] == "deep" for row in deep_cpu))
        self.assertEqual(sum(row["phase"] == "scale10m" for row in
                             deep_cpu), 3)

    def test_visualization_queues_after_first_successful_repeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite = root / "visualization"
            suite.mkdir()
            campaign = root / "campaign"
            campaign.mkdir()
            (campaign / "image.sha256").write_text(
                "a" * 64 + f"  {campaign / 'image.sif'}\n")
            state = dict(base=str(root), lane="cpu",
                         refinement_image="a" * 64, plan=[
                dict(phase="scale10m", dataset="deep", repeat=1),
                dict(phase="scale10m", dataset="deep", repeat=2)])
            first = dict(state["plan"][0], campaign=str(campaign),
                         audit_job="123")
            last = dict(state["plan"][1], campaign=str(campaign))
            with mock.patch.dict(controller.os.environ,
                                 {"VIS_SUITE": str(suite)}), \
                 mock.patch.object(controller.subprocess,
                                   "check_output", return_value=
                                   "b" * 64 + " script\n"), \
                 mock.patch.object(controller.subprocess, "run",
                                   return_value=mock.Mock(
                                       returncode=0, stdout="123\n")) as run:
                controller.queue_visual(state, first)
                controller.queue_visual(state, last)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(first["visual_job"], "123")
            self.assertNotIn("visual_job", last)
            self.assertEqual(run.call_args.args[0][1], "--parsable")
            self.assertIn(f"VIS_IMAGE={campaign / 'image.sif'}",
                          run.call_args.args[0][-2])
            self.assertIn("--dependency=afterany:123",
                          run.call_args.args[0])
            self.assertEqual(run.call_args.args[0][-1],
                             str(suite / "slurm_full_layouts.sh"))

    def test_pilot_queues_full_row_plot(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite = root / "visualization"
            suite.mkdir()
            campaign = root / "campaign"
            campaign.mkdir()
            (campaign / "image.sha256").write_text(
                "a" * 64 + f"  {campaign / 'image.sif'}\n")
            record = dict(phase="pilot", dataset="deep", repeat=1,
                          campaign=str(campaign))
            state = dict(base=str(root), lane="cpu",
                         refinement_image="a" * 64, plan=[record])
            with mock.patch.dict(controller.os.environ,
                                 {"VIS_SUITE": str(suite)}), \
                 mock.patch.object(controller.subprocess,
                                   "check_output", return_value=
                                   "b" * 64 + " script\n"), \
                 mock.patch.object(controller.subprocess, "run",
                                   return_value=mock.Mock(
                                       returncode=0, stdout="123\n")):
                controller.queue_visual(state, record)
            self.assertEqual(record["visual_job"], "123")
            self.assertIn("pilot_20000", record["visual_output"])

    def test_plot_rejects_changed_image_and_submission_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            campaign = root / "campaign"
            campaign.mkdir()
            (campaign / "image.sha256").write_text(
                "b" * 64 + f"  {campaign / 'image.sif'}\n")
            record = dict(phase="pilot", dataset="deep", repeat=1,
                          campaign=str(campaign))
            state = dict(base=str(root), lane="cpu",
                         refinement_image="a" * 64, plan=[record])
            with mock.patch.dict(controller.os.environ,
                                 {"VIS_SUITE": str(root)}), \
                 mock.patch.object(controller.subprocess, "check_output",
                                   return_value="c" * 64 + " script\n"):
                with self.assertRaisesRegex(RuntimeError,
                                            "differs from campaign"):
                    controller.queue_visual(state, record)
            (campaign / "image.sha256").write_text(
                "a" * 64 + f"  {campaign / 'image.sif'}\n")
            with mock.patch.dict(controller.os.environ,
                                 {"VIS_SUITE": str(root)}), \
                 mock.patch.object(controller.subprocess, "check_output",
                                   return_value="c" * 64 + " script\n"), \
                 mock.patch.object(controller.subprocess, "run",
                                   return_value=mock.Mock(
                                       returncode=1, stderr="queue down")):
                with self.assertRaisesRegex(RuntimeError, "queue down"):
                    controller.queue_visual(state, record)
            self.assertNotIn("visual_job", record)

    def test_extended_lanes_are_independent_and_strict(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            previous = root / "previous"
            previous.mkdir()
            controller.save(previous, dict(status="QUALITY_GAPS",
                plan=[dict(phase="fresh5m")],
                records=[dict(audited="now")],
                refinement_image="a" * 64,
                quality_gaps=["turing HNSW recall gap"]))
            cpu = root / "cpu"
            cuda = root / "cuda"
            cpu.mkdir()
            cuda.mkdir()
            controller.initialize_extended(cpu, previous, "cpu", root)
            controller.initialize_extended(cuda, previous, "cuda", root)
            cpu_plan = controller.load(cpu)["plan"]
            gpu_plan = controller.load(cuda)["plan"]
            self.assertEqual([row["phase"] for row in cpu_plan],
                             ["cluster_pilot"] * 2 +
                             ["cluster_scale"] * 2 +
                             ["fresh5m_3d"] * 2 +
                             ["boundary"] * 2 + ["billion"] * 2)
            self.assertEqual([row["dataset"] for row in gpu_plan],
                             ["deep", "turing"] * 5)
            self.assertTrue(all(row["lane"] == "cpu" for row in cpu_plan))
            self.assertTrue(all(row["lane"] == "cuda" for row in gpu_plan))
            campaign = root / "failed_stage"
            campaign.mkdir()
            (campaign / "audit.json").write_text(json.dumps(dict(
                case_count=1, failures=["missing cluster sample"])))
            with self.assertRaisesRegex(ValueError, "missing cluster"):
                controller.audit_previous(controller.load(cpu),
                                          dict(phase="boundary",
                                               campaign=str(campaign)))

    def test_parse_job_ledger(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with (root / "jobs.tsv").open("w", newline="") as stream:
                writer = csv.writer(stream, delimiter="\t")
                writer.writerow(("kind", "job_id", "case_count"))
                writer.writerow(("cpu", "123", "4"))
                writer.writerow(("audit", "124", "1"))
            self.assertEqual(controller.parse_submission(
                f"Campaign: {root}\n", False), (root, "124"))

    def test_comprehensive_stage_uses_versioned_suite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            suite = root / "deep1b_20261010"
            suite.mkdir()
            campaign = root / "campaign"
            campaign.mkdir()
            (campaign / "jobs.tsv").write_text(
                "kind\tjob_id\tcase_count\n"
                "cpu\t123\t4\n"
                "audit\t124\t1\n")
            result = mock.Mock(returncode=0,
                stdout=f"Campaign: {campaign}\n", stderr="")
            stage = dict(phase="scale10m", dataset="deep", lane="cpu")
            with mock.patch.dict(controller.os.environ,
                                 {"DEEP1B_SUITE": str(suite)}), \
                 mock.patch.object(controller.subprocess, "run",
                                   return_value=result) as run:
                self.assertEqual(controller.submit_stage(
                    dict(base=str(root), comprehensive=True), stage),
                    (campaign, "124"))
            self.assertEqual(run.call_args.args[0][1],
                             str(suite / "submit.sh"))
            self.assertEqual(run.call_args.kwargs["env"]
                             ["DEEP1B_SERIALIZE"], "0")

    def test_comprehensive_fans_out_independent_stages(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plan = [dict(phase=phase, dataset="deep", lane="cpu",
                         repeat=repeat)
                    for phase, repeat in (("pilot", 1), ("scale", 1),
                                          ("scale", 2), ("fresh5m", 1),
                                          ("graph10m", 1))]
            controller.save(root, dict(status="RUNNING", base=str(root),
                refinement_image="a" * 64, comprehensive=True,
                plan=plan, records=[], quality_gaps=[]))
            campaigns = [root / f"campaign_{i}" for i in range(5)]
            for campaign in campaigns:
                campaign.mkdir()
            submitted = [(campaigns[i], str(100 + i))
                         for i in range(len(campaigns))]
            def plot(state, record):
                if record["phase"] != "graph10m" and record["repeat"] == 1:
                    record["visual_job"] = str(200 + record["index"])
            with mock.patch.object(controller, "submit_stage",
                                   side_effect=submitted) as submit, \
                 mock.patch.object(controller, "queue_visual",
                                   side_effect=plot), \
                 mock.patch.object(controller, "queue_controller",
                                   side_effect=["500", "501"]) as queue, \
                 mock.patch.object(controller.subprocess, "check_output",
                                   return_value="a" * 64 + " image\n"):
                controller.advance_comprehensive(root, 0)
                (campaigns[0] / "audit.json").write_text(json.dumps(
                    dict(case_count=6, failures=[])))
                controller.advance_comprehensive(root, 1)
            state = controller.load(root)
            self.assertEqual(submit.call_count, len(plan))
            self.assertEqual(state["status"], "WAITING")
            self.assertEqual(len(state["records"]), len(plan))
            self.assertEqual(queue.call_args.args[2],
                             ["100", "101", "102", "103", "104",
                              "200", "201", "203"])
            self.assertEqual(state["final_controller"], "501")

    def test_final_controller_depends_only_on_its_lane(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state = dict(base=str(root), comprehensive=True,
                         lane="cpu", dataset="deep")
            result = mock.Mock(returncode=0, stdout="501\n")
            with mock.patch.object(controller.subprocess, "run",
                                   return_value=result) as run:
                controller.queue_controller(root, 3,
                                            ["101", "102", "101"], state)
            args = run.call_args.args[0]
            self.assertIn("--job-name=feR_cpu_deep_final", args)
            self.assertIn("--dependency=afterany:101:102", args)
            self.assertNotIn("--dependency=afterany:201", args)

    def test_comprehensive_final_collects_all_stage_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            records = []
            for index, reason in enumerate(("PCA failed", "KNN failed")):
                campaign = root / f"campaign_{index}"
                campaign.mkdir()
                (campaign / "audit.json").write_text(json.dumps(dict(
                    case_count=1, failures=[reason])))
                records.append(dict(phase="scale", dataset="deep",
                    lane="cpu", repeat=index + 1,
                    campaign=str(campaign), audit_job=str(100 + index)))
            controller.save(root, dict(status="WAITING", base=str(root),
                comprehensive=True, plan=[dict(phase="scale")] * 2,
                records=records, quality_gaps=[]))
            with mock.patch.object(controller.audit_visuals, "audit",
                return_value=dict(status="PASS", images_checked=1)):
                with self.assertRaisesRegex(RuntimeError, "PCA failed"):
                    controller.advance_comprehensive(root, 2)
            state = controller.load(root)
            self.assertEqual(state["status"], "STOPPED")
            self.assertIn("KNN failed", state["failure"])

    def test_controller_advances_after_audit_without_waiting(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            campaign = root / "campaign"
            campaign.mkdir()
            state = dict(status="RUNNING", base=str(root),
                refinement_image="a" * 64,
                plan=[dict(phase="threads1m", dataset="deep",
                           lane="cpu", repeat=1)],
                records=[], quality_gaps=[])
            controller.save(root, state)
            command = mock.Mock(returncode=0, stdout="125\n", stderr="")
            with mock.patch.object(controller, "submit_stage",
                                   return_value=(campaign, "124")), \
                 mock.patch.object(controller.subprocess, "run",
                                   return_value=command), \
                 mock.patch.object(controller.subprocess, "check_output",
                                   return_value="a" * 64 + " image"):
                controller.advance(root, 0)
            self.assertEqual(controller.load(root)["records"][0]
                             ["audit_job"], "124")
            (campaign / "audit.json").write_text(json.dumps(dict(
                case_count=16, failures=[])))
            with mock.patch.object(controller.subprocess, "run",
                                   return_value=command):
                controller.advance(root, 1)
            self.assertEqual(controller.load(root)["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
