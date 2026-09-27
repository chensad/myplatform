"""Exercise persistent installation on temporary files, never /lib/modules."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "installer", Path(__file__).resolve().parents[1] / "board-install-rpmsg-tty-fix.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "new.ko"
        self.target = self.root / "system.ko"
        self.source.write_bytes(b"tested-new-module")
        self.target.write_bytes(b"original-module")
        values = {"name": m.NAME, "version": m.VERSION, "vermagic": m.VERMAGIC}
        for mocker in (
                patch.object(m, "SHA256", hashlib.sha256(self.source.read_bytes()).hexdigest()),
                patch.object(m, "field", side_effect=lambda path, key: values[key]),
                patch.object(m, "module_target", return_value=self.target),
                patch.object(m.os, "sync")):
            mocker.start()
            self.addCleanup(mocker.stop)

    def test_install_preserves_backup(self):
        with patch.object(m, "run", return_value=""):
            m.install(self.source, self.target, self.root)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        backup = list(self.root.glob("rb-rpmsg-module-backup-*"))
        self.assertEqual(len(backup), 1)
        self.assertEqual((backup[0] / "imx_rpmsg_tty.ko.original").read_bytes(), b"original-module")
        self.assertTrue((backup[0] / "manifest.json").is_file())

    def test_depmod_failure_restores_original(self):
        with patch.object(m, "run", side_effect=[RuntimeError("depmod failed"), ""]):
            with self.assertRaisesRegex(RuntimeError, "depmod failed"):
                m.install(self.source, self.target, self.root)
        self.assertEqual(self.target.read_bytes(), b"original-module")

    def test_wrong_source_never_replaces_target(self):
        self.source.write_bytes(b"wrong-module")
        with self.assertRaisesRegex(RuntimeError, "SHA256"):
            m.install(self.source, self.target, self.root)
        self.assertEqual(self.target.read_bytes(), b"original-module")
        self.assertFalse(list(self.root.glob("rb-rpmsg-module-backup-*")))

    def test_reinstall_keeps_existing_backup(self):
        with patch.object(m, "run", return_value=""):
            m.install(self.source, self.target, self.root)
            m.install(self.source, self.target, self.root)
        self.assertEqual(len(list(self.root.glob("rb-rpmsg-module-backup-*"))), 1)

    def test_verification_failure_restores_original(self):
        with patch.object(m, "run", return_value=""), patch.object(
                m, "verify_disk", side_effect=RuntimeError("wrong resolution")):
            with self.assertRaisesRegex(RuntimeError, "wrong resolution"):
                m.install(self.source, self.target, self.root)
        self.assertEqual(self.target.read_bytes(), b"original-module")


if __name__ == "__main__":
    unittest.main()
