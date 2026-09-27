#!/usr/bin/env python3
"""Board-only RPMsg TTY regression: stale FD + repeated active-writer restart.

Requires the fixed module to be loaded and both M7 services running. Sends
HELLO queries only (no lease/clear-fault), but restarts M7. Use on the existing
no-motor bench. No module replacement, OS reboot or automatic failure recovery.
"""

import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import re
import select
import shutil
import stat
import struct
import subprocess
import tempfile
import termios
import threading
import time
import tty


VERSION = "robobase-safe-teardown-1"
DEVICE = "/dev/ttyRPMSG30"
STATE = Path("/sys/class/remoteproc/remoteproc0/state")
VERSION_FILE = Path("/sys/module/imx_rpmsg_tty/version")
HEADER = struct.Struct("<IBBHHHII")
STATUS = struct.Struct("<IIBBBBIIIIII")
MAGIC = 0x31534652
GREETING = b"hello world!"
BAD_KERNEL = re.compile(
    # A bare BUG: also matches the suffix of the BSP's normal "debug:".
    r"\b(?:Oops:|Kernel panic|Unable to handle kernel|BUG:|WARNING:|"
    r"Call trace:|use-after-free|double[- ]free)", re.IGNORECASE)
DISCONNECT_ERRNOS = (errno.EIO, errno.ENODEV, errno.ENXIO, errno.EPIPE)


class Failure(RuntimeError):
    pass


class Disconnected(Failure):
    pass


def hello(seq):
    return HEADER.pack(MAGIC, 0, 1, 1, HEADER.size, 0, seq, 0)


def read_exact(fd, size, deadline):
    data = bytearray()
    while len(data) < size:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("STATUS receive timeout")
        readable, _, _ = select.select([fd], [], [], remaining)
        if not readable:
            raise TimeoutError("STATUS receive timeout")
        try:
            chunk = os.read(fd, size - len(data))
        except BlockingIOError:
            continue
        if not chunk:
            raise Disconnected("TTY read returned EOF")
        data.extend(chunk)
    return bytes(data)


def query(fd, seq, timeout=2.0):
    deadline = time.monotonic() + timeout
    frame = hello(seq)
    sent = 0
    while sent < len(frame):
        if time.monotonic() >= deadline:
            raise TimeoutError("HELLO send timeout")
        try:
            count = os.write(fd, frame[sent:])
        except BlockingIOError:
            time.sleep(0.005)
            continue
        if count <= 0:
            raise Disconnected("TTY write returned zero")
        sent += count
    # The driver's probe handshake can be echoed after the new TTY is opened.
    # Consume only that exact known greeting; never skip arbitrary bad frames.
    prefix = read_exact(fd, 4, deadline)
    if prefix == GREETING[:4]:
        greeting = prefix + read_exact(fd, len(GREETING) - 4, deadline)
        if greeting != GREETING:
            raise Failure("unexpected TTY greeting: {!r}".format(greeting))
        prefix = read_exact(fd, 4, deadline)
    values = HEADER.unpack(prefix + read_exact(fd, HEADER.size - 4, deadline))
    magic, major, minor, kind, header_len, payload_len, reply_seq, crc = values
    if (magic != MAGIC or major != 0 or minor != 1 or kind != 3 or
            header_len != HEADER.size or payload_len != STATUS.size or
            reply_seq != seq or crc != 0):
        raise Failure("invalid/mismatched STATUS header: {!r}".format(values))
    values = STATUS.unpack(read_exact(fd, STATUS.size, deadline))
    return dict(zip(("uptime_ms", "heartbeat", "state", "motion", "estop_nc",
                     "bumper_nc", "fault", "latched", "last_linux_seq",
                     "lease_age_ms", "loop_counter", "reserved"), values))


def open_tty():
    fd = os.open(DEVICE, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        tty.setraw(fd, termios.TCSANOW)
    except BaseException:
        os.close(fd)
        raise
    return fd


def reject_stale_write(fd, seq):
    # EBADF must not pass: this test requires a still-open old file descriptor.
    os.fstat(fd)
    try:
        count = os.write(fd, hello(seq))
    except OSError as exc:
        if exc.errno in DISCONNECT_ERRNOS:
            return errno.errorcode[exc.errno]
        raise Failure("unexpected stale-FD error: {}".format(exc)) from exc
    raise Failure("old FD accepted {} bytes after channel removal".format(count))


class Runner:
    def __init__(self, log_dir):
        self.log_dir = Path(log_dir)
        self.summary = {"result": "RUNNING", "old_fd": "NOT_RUN", "cycles": []}

    def log(self, text):
        line = "[{:.3f}] {}".format(time.monotonic(), text)
        print(line, flush=True)
        with (self.log_dir / "events.log").open("a") as out:
            out.write(line + "\n")

    def save_summary(self):
        (self.log_dir / "summary.json").write_text(
            json.dumps(self.summary, indent=2) + "\n")

    def command(self, *args):
        self.log("COMMAND " + " ".join(args))
        proc = subprocess.run(args, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=30,
                              universal_newlines=True)
        if proc.stdout:
            self.log(proc.stdout.rstrip())
        if proc.returncode:
            raise Failure("command failed ({}): {}".format(proc.returncode, args))
        return proc.stdout

    def checkpoint(self, label):
        proc = subprocess.run(["dmesg"], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=10,
                              universal_newlines=True)
        if proc.returncode:
            raise Failure("cannot collect kernel log: " + proc.stderr)
        (self.log_dir / (label + "-dmesg.log")).write_text(proc.stdout)
        # Refuse even a pre-existing Oops: this kernel is not a clean test base.
        match = BAD_KERNEL.search(proc.stdout)
        if match:
            start = proc.stdout.rfind("\n", 0, match.start()) + 1
            end = proc.stdout.find("\n", match.end())
            line = proc.stdout[start:end if end >= 0 else len(proc.stdout)]
            raise Failure("kernel warning/fault found: " + line)
        if VERSION_FILE.read_text().strip() != VERSION:
            raise Failure("fixed module is no longer loaded")

    def preflight(self):
        if os.geteuid() != 0:
            raise Failure("run as root on the MYIR board")
        for program in ("systemctl", "dmesg"):
            if not shutil.which(program):
                raise Failure("missing command: " + program)
        self.checkpoint("00-before")
        if STATE.read_text().strip() != "running":
            raise Failure("remoteproc0 must already be running")
        target = os.stat(DEVICE)
        if not stat.S_ISCHR(target.st_mode):
            raise Failure("TTY path is not a character device")
        for pid in Path("/proc").iterdir():
            if not pid.name.isdigit() or int(pid.name) == os.getpid():
                continue
            try:
                for entry in (pid / "fd").iterdir():
                    try:
                        info = entry.stat()
                        if stat.S_ISCHR(info.st_mode) and info.st_rdev == target.st_rdev:
                            raise Failure("TTY already held by PID " + pid.name)
                    except FileNotFoundError:
                        pass
            except (FileNotFoundError, ProcessLookupError):
                pass
        self.log("PREFLIGHT PASS: fixed module, clean kernel, no other TTY clients")

    def stop_m7(self, label):
        self.command("systemctl", "stop", "robobase-rpmsg-tty.service")
        self.command("systemctl", "stop", "robobase-m7.service")
        if STATE.read_text().strip() != "offline":
            raise Failure("remoteproc did not become offline")
        self.checkpoint(label + "-stopped")
        # Original Oops arrived about one second after stop completed.
        time.sleep(2)
        self.checkpoint(label + "-settled")

    def start_m7(self, label):
        self.checkpoint(label + "-before-start")
        self.command("systemctl", "start", "robobase-m7.service")
        self.command("systemctl", "start", "robobase-rpmsg-tty.service")
        if STATE.read_text().strip() != "running":
            raise Failure("remoteproc did not become running")
        self.checkpoint(label + "-started")

    def fresh_query(self, label):
        fd = open_tty()
        try:
            status = query(fd, 1)
            self.log("{} new-FD STATUS {}".format(label, status))
        finally:
            os.close(fd)
        self.checkpoint(label + "-query")

    def old_fd_test(self):
        fd = open_tty()
        try:
            self.log("old FD {} initially works: {}".format(fd, query(fd, 1)))
            self.stop_m7("old-fd")
            self.log("old FD while stopped: " + reject_stale_write(fd, 2))
            self.start_m7("old-fd")
            self.fresh_query("old-fd-still-held")
            self.log("old FD after restart: " + reject_stale_write(fd, 3))
        finally:
            os.close(fd)
        self.fresh_query("old-fd-closed")
        self.summary["old_fd"] = "PASS"
        self.save_summary()
        self.log("OLD_FD PASS")

    def cycle(self, number):
        label = "cycle-{:02d}".format(number)
        fd = open_tty()
        ready = threading.Event()
        stopping = threading.Event()
        cancel = threading.Event()
        outcome = {"completed_queries": 0, "disconnect": None, "error": None}

        def sender():
            seq = 1
            try:
                while not cancel.is_set():
                    query(fd, seq)
                    outcome["completed_queries"] += 1
                    if outcome["completed_queries"] >= 5:
                        ready.set()
                    seq += 1
                    cancel.wait(0.02)
            except (OSError, TimeoutError, Failure) as exc:
                expected = (isinstance(exc, (Disconnected, TimeoutError)) or
                            isinstance(exc, OSError) and exc.errno in DISCONNECT_ERRNOS)
                if stopping.is_set() and expected:
                    outcome["disconnect"] = "{}: {}".format(type(exc).__name__, exc)
                else:
                    outcome["error"] = "{}: {}".format(type(exc).__name__, exc)
            finally:
                ready.set()

        worker = threading.Thread(target=sender, daemon=True)
        worker.start()
        try:
            if not ready.wait(5) or not worker.is_alive() or outcome["error"]:
                raise Failure("sender not healthy before stop: {!r}".format(outcome))
            if outcome["completed_queries"] < 5:
                raise Failure("not enough successful queries before stop")
            self.log("{} sender active; {} valid replies".format(
                label, outcome["completed_queries"]))
            stopping.set()
            self.stop_m7(label)
            worker.join(3)
            if worker.is_alive() or outcome["error"] or not outcome["disconnect"]:
                raise Failure("sender did not disconnect cleanly: {!r}".format(outcome))
            self.log("{} disconnected: {}".format(label, outcome["disconnect"]))
            self.start_m7(label)
            self.fresh_query(label + "-old-held")
            self.log("{} stale FD: {}".format(label, reject_stale_write(fd, 999)))
        finally:
            cancel.set()
            worker.join(3)
            if not worker.is_alive():
                os.close(fd)
            # A stuck syscall cannot be safely recovered by this script.
        self.fresh_query(label + "-old-closed")
        self.summary["cycles"].append(dict(outcome, cycle=number, result="PASS"))
        self.save_summary()
        self.log("CYCLE {}/{} PASS".format(number, self.summary["requested_cycles"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("all", "old-fd", "cycles"), default="all")
    parser.add_argument("--cycles", type=int, default=10)
    parser.add_argument("--log-dir", type=Path)
    args = parser.parse_args()
    if not 1 <= args.cycles <= 100:
        parser.error("--cycles must be between 1 and 100")
    if args.log_dir:
        args.log_dir.mkdir(parents=True, exist_ok=False)
        log_dir = args.log_dir
    else:
        log_dir = Path(tempfile.mkdtemp(prefix="rb-tty-regression-", dir="/home"))
    runner = Runner(log_dir)
    runner.summary.update(mode=args.mode, requested_cycles=args.cycles,
                          messages="HELLO only; no LEASE or CLEAR_FAULT")
    lock_fd = os.open("/tmp/rb-tty-lifecycle.lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        runner.log("Logs: {}".format(log_dir))
        runner.preflight()
        if args.mode in ("all", "old-fd"):
            runner.old_fd_test()
        if args.mode in ("all", "cycles"):
            for number in range(1, args.cycles + 1):
                runner.cycle(number)
        runner.checkpoint("99-final")
        runner.summary["result"] = "PASS"
        runner.log("ALL REQUESTED TESTS PASS; M7 running, no lease sent")
        return 0
    except (Exception, KeyboardInterrupt) as exc:
        runner.summary["result"] = "FAIL"
        runner.summary["error"] = "{}: {}".format(type(exc).__name__, exc)
        runner.log("FAIL: " + runner.summary["error"])
        try:
            runner.checkpoint("failure")
        except Exception as snapshot_error:
            runner.log("Failure checkpoint: {}".format(snapshot_error))
        runner.log("Stopped. No automatic service recovery; retain serial output.")
        return 1
    finally:
        runner.save_summary()
        os.close(lock_fd)


if __name__ == "__main__":
    raise SystemExit(main())
