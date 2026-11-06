import importlib.util
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest import mock

source = Path('/tmp/hpc_resident_pilot_runner_b825116.py')
spec = importlib.util.spec_from_file_location('pilot', source)
pilot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pilot)


class PilotLifecycleTests(unittest.TestCase):
    def test_ordinary_child_failure_cannot_be_success(self):
        child = subprocess.Popen([sys.executable, '-c', 'raise SystemExit(7)'],
                                 start_new_session=True)
        self.assertEqual(child.wait(timeout=5), 7)
        pilot.stop_group(child.pid)
        self.assertFalse(pilot.group_pids(child.pid))

    def test_parent_exit_leaves_owned_descendant_to_clean(self):
        parent = subprocess.Popen([
            sys.executable, '-c',
            'import subprocess; subprocess.Popen(["sleep", "30"]);'
            'raise SystemExit(0)'], start_new_session=True)
        parent.wait(timeout=5)
        end = time.monotonic() + 3
        while not pilot.group_pids(parent.pid) and time.monotonic() < end:
            time.sleep(0.05)
        self.assertTrue(pilot.group_pids(parent.pid))
        pilot.stop_group(parent.pid)
        self.assertFalse(pilot.group_pids(parent.pid))

    def test_term_ignoring_child_is_boundedly_killed(self):
        child = subprocess.Popen([
            sys.executable, '-c',
            'import signal,time; signal.signal(signal.SIGTERM, '
            'signal.SIG_IGN); time.sleep(30)'], start_new_session=True)
        time.sleep(0.1)
        pilot.stop_group(child.pid)
        child.wait(timeout=5)
        self.assertFalse(pilot.group_pids(child.pid))

    def test_persistent_context_blocks_success(self):
        with mock.patch.object(pilot, 'group_pids', return_value=set()), \
             mock.patch.object(pilot, 'contexts',
                               return_value={(123, 'GPU-test')}), \
             mock.patch.object(pilot.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'Cleanup unknown'):
                pilot.verify_cleanup(987654321, {'GPU-test'})

    def test_scheduler_warning_latches_abort(self):
        pilot.ABORT = None
        pilot.on_signal(__import__('signal').SIGUSR1, None)
        self.assertEqual(pilot.ABORT, 'SIGUSR1')
        pilot.ABORT = None

    def test_telemetry_failure_is_not_clean(self):
        with mock.patch.object(pilot, 'group_pids', return_value=set()), \
             mock.patch.object(pilot, 'contexts',
                               side_effect=TimeoutError('nvidia-smi timeout')):
            with self.assertRaises(TimeoutError):
                pilot.verify_cleanup(987654321, {'GPU-test'})


if __name__ == '__main__':
    unittest.main()
