"""Normal-stop protocol tests using the real M7 state machine and host TTYs."""
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
RECIPES = ROOT / "platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-robobase"
APP = ROOT / "third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only"
HEADER = struct.Struct("<IBBHHHII")
STATUS = struct.Struct("<IIBBBBIIIIII")

HARNESS = r'''
#include <assert.h>
#include <string.h>
#include "robobase/rb_safety_proto.h"
#include "robobase_safe_app.h"
#include "robobase_safety_inputs.h"
#include "robobase_safety_outputs.h"
static unsigned output, barriers;
void test_barrier(void) { assert(output == 0); barriers++; }
void robobase_safety_outputs_init(void) { output = 0; }
void robobase_safety_outputs_set_safety_allow(uint8_t allow) { output = allow; }
void robobase_safety_inputs_init(void) {}
void robobase_safety_inputs_sample(robobase_safety_inputs_t *p) {
    p->estop_nc_closed = p->bumper_nc_closed = 1;
}
void robobase_safety_inputs_set_debug_gpio_level(uint8_t a, uint8_t b, uint32_t mask) {
    (void)a; (void)b; (void)mask;
}
static struct rb_safe_status_msg send_frame(unsigned type, const void *payload, unsigned n) {
    unsigned char rx[128], tx[128];
    struct rb_safe_status_msg status;
    struct rb_safe_hdr h;
    rb_safe_hdr_init(&h, type, 77, n);
    memcpy(rx, &h, sizeof(h));
    if (n) memcpy(rx + sizeof(h), payload, n);
    assert(robobase_safe_handle_frame(rx, sizeof(h) + n, tx, sizeof(tx)) ==
           sizeof(h) + sizeof(status));
    memcpy(&h, tx, sizeof(h));
    assert(h.msg_type == RB_SAFE_MSG_STATUS && h.seq == 77);
    memcpy(&status, tx + sizeof(h), sizeof(status));
    return status;
}
int main(void) {
    struct rb_safe_lease_msg lease = {0, 200, 1, 1, 1, 1, 0, 0};
    struct rb_safe_clear_fault_msg clear = {1, 0xffffffff, RB_SAFE_CLEAR_CONFIRM};
    struct rb_safe_debug_inputs_msg debug = {0};
    struct rb_safe_status_msg s;
    unsigned i;
    robobase_safe_init();
    assert(!output);
    s = send_frame(RB_SAFE_MSG_LEASE, &lease, sizeof(lease));
    assert(s.motion_enable == 1 && output == 1);
    s = send_frame(RB_SAFE_MSG_QUIESCE, "x", 1);
    assert(!(s.fault_bits & RB_FAULT_STOP_REQUESTED) && output == 1);
    s = send_frame(RB_SAFE_MSG_QUIESCE, 0, 0);
    assert(!output && !s.motion_enable && barriers == 1);
    assert(s.fault_bits & RB_FAULT_STOP_REQUESTED);
    for (i = 0; i < 10; i++) {
        s = send_frame(RB_SAFE_MSG_LEASE, &lease, sizeof(lease));
        assert(!output && !s.motion_enable && (s.fault_bits & RB_FAULT_STOP_REQUESTED));
        s = send_frame(RB_SAFE_MSG_CLEAR_FAULT, &clear, sizeof(clear));
        assert(!output && !s.motion_enable && (s.fault_bits & RB_FAULT_STOP_REQUESTED));
        s = send_frame(RB_SAFE_MSG_DEBUG_INPUTS, &debug, sizeof(debug));
        assert(!output && !s.motion_enable && (s.fault_bits & RB_FAULT_STOP_REQUESTED));
        robobase_safe_tick_1ms();
        assert(robobase_safe_process_pending_tick());
        s = send_frame(RB_SAFE_MSG_HELLO, 0, 0);
        assert(!output && !s.motion_enable && (s.fault_bits & RB_FAULT_STOP_REQUESTED));
    }
    s = send_frame(RB_SAFE_MSG_QUIESCE, 0, 0);
    assert(!output && !s.motion_enable && barriers == 2);
    return 0;
}
'''


class QuiesceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.tool = cls.root / "robobase-rpmsg-test"
        subprocess.run(["gcc", "-Wall", "-Wextra", "-Werror", "-O2",
                        "-I" + str(ROOT / "platform/common/include"),
                        str(RECIPES / "robobase-rpmsg-test/files/robobase-rpmsg-test.c"),
                        "-o", str(cls.tool)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_real_firmware_stop_latch(self):
        (self.root / "fsl_device_registers.h").write_text(
            "void test_barrier(void);\n#define __DSB() test_barrier()\n"
            "#define __disable_irq() ((void)0)\n#define __enable_irq() ((void)0)\n")
        source = self.root / "harness.c"
        source.write_text(HARNESS)
        binary = self.root / "firmware-test"
        subprocess.run(["gcc", "-Wall", "-Wextra", "-Werror",
                        "-I" + str(self.root), "-I" + str(APP),
                        "-I" + str(ROOT / "platform/common/include"),
                        str(source), str(APP / "robobase_safe_app.c"),
                        "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)

    def exchange(self, fault=128, motion=0, reply=True, greeting=False, wrong_seq=False):
        master, slave = pty.openpty()
        child = subprocess.Popen([str(self.tool), "--quiesce", "-t", "100",
                                  "-d", os.ttyname(slave)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertTrue(select.select([master], [], [], 3)[0])
            frame = bytearray()
            while len(frame) < HEADER.size:
                self.assertTrue(select.select([master], [], [], 1)[0])
                frame.extend(os.read(master, HEADER.size - len(frame)))
            header = HEADER.unpack(frame)
            self.assertEqual(header[3:6], (6, 20, 0))
            if reply:
                response = HEADER.pack(header[0], 0, 1, 3, 20, 36,
                                       header[6] ^ int(wrong_seq), 0)
                response += STATUS.pack(1, 1, 4, motion, 1, 1, fault, 0, header[6], 0, 1, 0)
                if greeting:
                    response = b"hello world!" + response
                os.write(master, response)
            stdout, stderr = child.communicate(timeout=3)
            return child.returncode, stdout + stderr
        finally:
            if child.poll() is None:
                child.kill()
                child.communicate()
            os.close(master)
            os.close(slave)

    def test_ack_with_greeting(self):
        result, log = self.exchange(greeting=True)
        self.assertEqual(result, 0, log)
        self.assertIn("QUIESCE confirmed", log)

    def test_old_firmware_low_motion_is_not_ack(self):
        self.assertNotEqual(self.exchange(fault=64)[0], 0)

    def test_motion_high_is_not_ack(self):
        self.assertNotEqual(self.exchange(motion=1)[0], 0)

    def test_wrong_sequence_is_not_ack(self):
        self.assertNotEqual(self.exchange(wrong_seq=True)[0], 0)

    def test_no_ack_fails(self):
        self.assertNotEqual(self.exchange(reply=False)[0], 0)

    def test_busy_tty_fails_without_writing(self):
        import fcntl
        master, slave = pty.openpty()
        try:
            fcntl.flock(slave, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = subprocess.run([str(self.tool), "--quiesce", "-d", os.ttyname(slave)],
                                    capture_output=True, text=True, timeout=3)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("TTY busy", result.stderr)
            self.assertFalse(select.select([master], [], [], 0)[0])
        finally:
            os.close(master)
            os.close(slave)

    def run_stop(self, state, acknowledged):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "state").write_text(state + "\n")
            helper = root / "robobase-rpmsg-test"
            helper.write_text("#!/bin/sh\n/bin/cat \"$ROBOBASE_M7_REMOTEPROC/state\" > " +
                              str(root / "before-ack") + "\nexit " + str(0 if acknowledged else 1) + "\n")
            helper.chmod(0o755)
            cat = root / "cat"
            cat.write_text('#!/bin/sh\nx=$(/bin/cat "$1")\n'
                           'if [ "$x" = stop ]; then echo offline; else echo "$x"; fi\n')
            cat.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + ":" + os.environ["PATH"],
                       ROBOBASE_M7_REMOTEPROC=str(root))
            result = subprocess.run(["sh", str(RECIPES / "robobase-m7-services/files/robobase-m7-stop")],
                                    env=env, capture_output=True, text=True, timeout=3)
            return result, (root / "state").read_text().strip(), (
                (root / "before-ack").read_text().strip() if (root / "before-ack").exists() else None)

    def test_stop_only_after_ack(self):
        result, state, before = self.run_stop("running", True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((state, before), ("stop", "running"))

    def test_stop_refuses_missing_ack(self):
        result, state, _ = self.run_stop("running", False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state, "running")

    def test_offline_is_idempotent(self):
        result, state, before = self.run_stop("offline", False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(state, "offline")
        self.assertIsNone(before)

    def test_crashed_not_forcibly_stopped(self):
        result, state, before = self.run_stop("crashed", True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state, "crashed")
        self.assertIsNone(before)


if __name__ == "__main__":
    unittest.main()
