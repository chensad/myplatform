"""Host tests; no board, services or network required."""
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "lifecycle", Path(__file__).resolve().parents[1] /
    "board-test-rpmsg-tty-lifecycle.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ReceiveTests(unittest.TestCase):
    def response(self, seq=7):
        return (m.HEADER.pack(m.MAGIC, 0, 1, 3, 20, 36, seq, 0) +
                m.STATUS.pack(123, 4, 1, 0, 1, 1, 0, 0, 7, 999, 55, 0))

    def query_bytes(self, data, fragment=4096):
        rx, tx = os.pipe()
        try:
            os.write(tx, data)
            original_read = os.read
            with patch.object(m.os, "write", return_value=20), patch.object(
                    m.os, "read", side_effect=lambda fd, n:
                    original_read(fd, min(n, fragment))):
                return m.query(rx, 7, timeout=0.02)
        finally:
            os.close(rx)
            os.close(tx)

    def test_plain_status(self):
        self.assertEqual(self.query_bytes(self.response())["uptime_ms"], 123)

    def test_greeting_with_fragmented_status(self):
        for fragment in (1, 3, 12, 4096):
            with self.subTest(fragment=fragment):
                result = self.query_bytes(b"hello world!" + self.response(), fragment)
                self.assertEqual(result["loop_counter"], 55)

    def test_greeting_alone_does_not_pass(self):
        with self.assertRaises(TimeoutError):
            self.query_bytes(b"hello world!")

    def test_bad_greeting_rejected(self):
        with self.assertRaises(m.Failure):
            self.query_bytes(b"hello wrong!" + self.response())

    def test_bad_frame_not_skipped(self):
        with self.assertRaises(m.Failure):
            self.query_bytes(b"x" * 20 + self.response())

    def test_wrong_sequence_after_greeting(self):
        with self.assertRaises(m.Failure):
            self.query_bytes(b"hello world!" + self.response(8))

    def test_kernel_debug_not_bug(self):
        self.assertIsNone(m.BAD_KERNEL.search("robobase debug: fw_boot"))
        for text in ("BUG: failure", "Internal error: Oops: 96000007",
                     "WARNING: CPU: 2", "Kernel panic", "Call trace:"):
            self.assertIsNotNone(m.BAD_KERNEL.search(text))


if __name__ == "__main__":
    unittest.main()
