"""The archived controller must reject before invoking any audit stage."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


CONTROLLER = Path(__file__).with_name("run_complete_campaign_controller.sh")


class FullFinalAuditStatusTest(unittest.TestCase):
    def run_verdict(self, verdict):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            common = root / "common"
            common.mkdir()
            (common / "campaign_submit.sh").write_text(
                "campaign_require_environment() { :; }\n"
                "campaign_verify_suite_revision() { :; }\n"
                "campaign_init_ledger() { :; }\n"
                "campaign_record_previous_stage() { :; }\n"
                "campaign_record_controller_failure() { :; }\n"
                "campaign_record_stage() { printf '%s\\n' \"$*\" "
                ">> \"$JSS_CAMPAIGN_DIR/stages.txt\"; }\n"
            )
            audit = common / "run_full_final_audit.sh"
            audit.write_text(
                "#!/bin/bash\n"
                f"printf '%s\\n' '{verdict}' "
                '> "$JSS_CAMPAIGN_DIR/final_audit.txt"\n'
            )
            env = dict(os.environ, SUITE=str(root),
                       JSS_CAMPAIGN_DIR=str(root),
                       JSS_CAMPAIGN_ID="fixture", JSS_LEDGER=str(root),
                       JSS_STAGE="full_final_audit",
                       INPUT_ROOT=str(root), OUTPUT_ROOT=str(root),
                       FASTEMBEDR_IMAGE_SHA256="fixture",
                       FASTEMBEDR_DLL_SHA256="fixture",
                       FASTEMBEDR_SUITE_MANIFEST_SHA256="fixture")
            result = subprocess.run(["bash", str(CONTROLLER)], env=env,
                                    capture_output=True, text=True)
            return result, (root / "stages.txt").exists(), \
                (root / "final_audit.txt").exists()

    def test_archived_controller_never_runs_an_audit(self):
        for verdict in ("WARN", "INCOMPLETE"):
            with self.subTest(verdict=verdict):
                result, stages, audited = self.run_verdict(verdict)
                self.assertEqual(result.returncode, 78, result.stderr)
                self.assertIn("policy_rejected", result.stderr)
                self.assertFalse(stages)
                self.assertFalse(audited)


if __name__ == "__main__":
    unittest.main()
