import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "installer", Path(__file__).resolve().parents[1] / "board-install-m7-normal-stop.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class BundleInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "bundle"
        self.bundle.mkdir()
        self.targets = {}
        for name in m.EXPECTED:
            (self.bundle / name).write_text("new " + name)
            target = self.root / name
            target.write_text("old " + name)
            self.targets[name] = target
        for mocker in (patch.object(m, "EXPECTED", {n: m.sha(self.bundle / n) for n in self.targets}),
                       patch.object(m.os, "sync")):
            mocker.start()
            self.addCleanup(mocker.stop)

    def deploy(self, guard=lambda: None):
        return m.deploy(self.bundle, self.targets, self.root, guard)

    def assert_original(self):
        for name, target in self.targets.items():
            self.assertEqual(target.read_text(), "old " + name)

    def test_install_all_files_and_backups(self):
        backup = self.deploy()
        for name, target in self.targets.items():
            self.assertEqual(target.read_bytes(), (self.bundle / name).read_bytes())
            self.assertEqual((backup / name).read_text(), "old " + name)
            self.assertEqual(target.stat().st_mode & 0o777, 0o644 if name.endswith(".elf") else 0o755)

    def test_corrupt_input_changes_nothing(self):
        (self.bundle / "robobase-m7-stop").write_text("bad")
        with self.assertRaisesRegex(RuntimeError, "hash"):
            self.deploy()
        self.assert_original()
        self.assertFalse(list(self.root.glob("rb-m7-normal-stop-backup-*")))

    def test_running_core_changes_nothing(self):
        def running():
            raise RuntimeError("not offline")
        with self.assertRaisesRegex(RuntimeError, "offline"):
            self.deploy(running)
        self.assert_original()

    def test_partial_install_rolls_back_all_changed_files(self):
        original_copy = m.atomic_copy
        calls = []
        def failing_copy(source, target, mode):
            calls.append(str(source))
            if len(calls) == 2:
                raise OSError("simulated disk failure")
            original_copy(source, target, mode)
        with patch.object(m, "atomic_copy", side_effect=failing_copy):
            with self.assertRaisesRegex(OSError, "disk failure"):
                self.deploy()
        self.assert_original()

    def test_missing_original_changes_nothing(self):
        self.targets["robobase-m7-stop"].unlink()
        with self.assertRaisesRegex(RuntimeError, "missing"):
            self.deploy()
        self.assertEqual(self.targets["robobase-rpmsg-test"].read_text(), "old robobase-rpmsg-test")


if __name__ == "__main__":
    unittest.main()
