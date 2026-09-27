#!/usr/bin/env python3
"""Persist the board-tested RPMsg module; do not unload modules or reboot."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

NAME = "imx_rpmsg_tty"
VERSION = "robobase-safe-teardown-1"
RELEASE = "5.10.72-lts-5.10.y+ge456793341af"
VERMAGIC = RELEASE + " SMP preempt mod_unload modversions aarch64"
SHA256 = "71eca06393a487595498a5e3bb74a9b2c7b06c6f2cda77a6f43ecfa56822127d"


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.STDOUT,
                                   universal_newlines=True, timeout=30).strip()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def field(path, key):
    return run("modinfo", "-F", key, str(path))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate_source(path):
    require(digest(path) == SHA256, "source SHA256 is not the board-tested module")
    require(field(path, "name") == NAME, "incorrect module name")
    require(field(path, "version") == VERSION, "incorrect module version")
    require(field(path, "vermagic") == VERMAGIC, "incorrect module vermagic")


def module_target():
    root = (Path("/lib/modules") / RELEASE).resolve()
    path = Path(run("modinfo", "-n", NAME))
    require(path.is_absolute() and not path.is_symlink(),
            "module path must be an absolute non-symlink file: " + str(path))
    require(path.is_file() and path.suffix == ".ko",
            "expected an existing uncompressed .ko: " + str(path))
    require(root in path.resolve().parents, "module path is outside current kernel tree")
    return path


def atomic_copy(source, target):
    fd, name = tempfile.mkstemp(prefix=".rb-module-", dir=str(target.parent))
    try:
        with os.fdopen(fd, "wb") as out:
            with Path(source).open("rb") as inp:
                shutil.copyfileobj(inp, out)
            os.fchmod(out.fileno(), 0o644)
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, str(target))
        directory_fd = os.open(str(target.parent), os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def verify_disk(target):
    require(module_target() == target, "modinfo resolves a different module after depmod")
    validate_source(target)


def install(source, target, backup_root=Path("/home")):
    validate_source(source)
    if digest(target) == SHA256:
        run("depmod", "-a", RELEASE)
        verify_disk(target)
        print("INSTALL PASS: fixed module already installed; index refreshed")
        return
    backup = Path(tempfile.mkdtemp(prefix="rb-rpmsg-module-backup-", dir=str(backup_root)))
    original = backup / "imx_rpmsg_tty.ko.original"
    shutil.copy2(str(target), str(original))
    old_hash = digest(target)
    require(digest(original) == old_hash, "backup checksum mismatch")
    (backup / "manifest.json").write_text(json.dumps({
        "target": str(target), "kernel_release": RELEASE,
        "original_sha256": old_hash, "installed_sha256": SHA256,
        "boot_id_at_install": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
    }, indent=2) + "\n")
    os.sync()
    print("BACKUP: " + str(backup), flush=True)
    print("TARGET: " + str(target), flush=True)
    try:
        atomic_copy(source, target)
        run("depmod", "-a", RELEASE)
        verify_disk(target)
    except BaseException:
        print("Installation failed; restoring original on-disk module", flush=True)
        atomic_copy(original, target)
        run("depmod", "-a", RELEASE)
        require(digest(target) == old_hash, "rollback checksum mismatch")
        raise
    os.sync()
    print("INSTALL PASS: persistent file and modinfo verified; reboot verification pending")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=Path("/home/imx_rpmsg_tty.ko"))
    parser.add_argument("--verify", action="store_true", help="read-only disk/loaded version check")
    args = parser.parse_args()
    require(os.geteuid() == 0, "run as root on the board")
    require(os.uname().release == RELEASE, "running kernel release does not match tested module")
    require(Path("/sys/module/imx_rpmsg_tty/version").read_text().strip() == VERSION,
            "loaded driver is not the verified fix")
    target = module_target()
    if args.verify:
        verify_disk(target)
        print("VERIFY PASS: disk hash/version/vermagic and loaded version match")
        print("BOOT_ID: " + Path("/proc/sys/kernel/random/boot_id").read_text().strip())
        print("TARGET: " + str(target))
    else:
        install(args.source, target)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (Exception, KeyboardInterrupt) as exc:
        print("FAIL: {}: {}".format(type(exc).__name__, exc), flush=True)
        raise SystemExit(1)
