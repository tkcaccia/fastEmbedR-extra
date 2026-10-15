"""All-row image audits reject missing rows and invented colors."""

import csv
import json
import tempfile
import unittest
from pathlib import Path

import audit_visuals


class VisualAuditTest(unittest.TestCase):
    def test_pilot_is_required(self):
        self.assertEqual(audit_visuals.ROWS["pilot"], 20000)

    def test_requires_every_row_and_uncolored_image(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            campaign = root / "campaign"
            campaign.mkdir()
            output = root / "pictures" / "deep"
            output.mkdir(parents=True)
            (campaign / "cases_cpu.tsv").write_text(
                "case\tmode\tcomponents\n"
                "cpu_pca_1m\tpca\t2\n")
            (output / "cpu_pca_1m.png").write_bytes(b"png")
            manifest = output / "visual_manifest.csv"
            record = dict(phase="scale", dataset="deep", repeat=1,
                          campaign=str(campaign), visual_job="123",
                          visual_output=str(output.parent))
            state = dict(status="COMPUTE_COMPLETE_PLOTS_PENDING",
                         quality_gaps=[], plan=[record], records=[record])
            (root / "state.json").write_text(json.dumps(state))
            with manifest.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=[
                    "case", "view", "rows", "plotted_rows",
                    "color_semantics",
                    "image"])
                writer.writeheader()
                writer.writerow(dict(case="cpu_pca_1m", view="xy",
                    rows="1e+06",
                    plotted_rows=1000000, color_semantics="none",
                    image="cpu_pca_1m.png"))
            self.assertEqual(audit_visuals.audit(root)["status"], "PASS")
            self.assertEqual(json.loads((root / "state.json").read_text())
                             ["status"], "PASS")
            content = manifest.read_text().replace(",none,", ",group,")
            manifest.write_text(content)
            self.assertEqual(audit_visuals.audit(root)["status"], "FAIL")

    def test_passing_stage_requires_manuscript_panel(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            campaign = root / "campaign"
            campaign.mkdir()
            (campaign / "audit.json").write_text(
                json.dumps({"status": "PASS"}))
            output = root / "pictures/deep"
            output.mkdir(parents=True)
            cases = ("cpu_pca_1m", "cpu_tsne_1m", "cpu_umap_1m")
            (campaign / "cases_cpu.tsv").write_text(
                "case\tmode\tcomponents\n" + "".join(
                    f"{case}\t{case.split('_')[1]}\t2\n"
                    for case in cases))
            record = dict(phase="scale", dataset="deep", repeat=1,
                          campaign=str(campaign), visual_job="123",
                          visual_output=str(output.parent))
            state = dict(status="WAITING", quality_gaps=[], plan=[record],
                         records=[record])
            (root / "state.json").write_text(json.dumps(state))
            with (output / "visual_manifest.csv").open(
                    "w", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(("case", "view", "rows", "plotted_rows",
                                 "color_semantics", "image"))
                for case in cases:
                    (output / f"{case}.png").write_bytes(b"png")
                    writer.writerow((case, "xy", "1000000", "1000000",
                                     "none", f"{case}.png"))
            self.assertEqual(audit_visuals.audit(root)["status"], "FAIL")
            (output / "comparison.png").write_bytes(b"png")
            with (output / "figure_manifest.csv").open(
                    "w", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(("backend", "rows", "pca", "tsne",
                                 "umap", "image", "color_semantics"))
                writer.writerow(("cpu", "1e+06", *cases,
                                 "comparison.png", "none"))
            self.assertEqual(audit_visuals.audit(root)["status"], "PASS")


if __name__ == "__main__":
    unittest.main()
