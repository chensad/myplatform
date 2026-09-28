#!/usr/bin/env python3
"""Install the matched QUIESCE bundle ONLY after M7 and its services are stopped."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

EXPECTED = {
    "robobase_m7_rpmsg_tty_echo.elf": "8a71d63992e5fcfc0bc25abed7ce23f24c9e8f8f3d25e66b20fdd0116293fd5d",
    "robobase-rpmsg-test": "6e01348cd63ee3599064bdd7938e24c25270b87a8437aa94a783437eda0ca303",
    "robobase-m7-start": "c2deb9652d4de34fc64d698f2173ab633452385533d90ab398c6aa2759e050b8",
    "robobase-m7-stop": "a19c11265e482e70c72f8ce3d9f5590b1c2993efd2378f92a5129cf8aae40306",
}
RPROC = Path("/sys/class/remoteproc/remoteproc0")
SERVICES = ("robobase-rpmsg-tty.service", "robobase-m7.service")


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def stopped():
    require((RPROC / "state").read_text().strip() == "offline",
            "M7 is not offline; stop it using the old tool/service first")
    for service in SERVICES:
        state = subprocess.check_output(
            ["systemctl", "show", "-p", "ActiveState", "--value", service],
            universal_newlines=True, timeout=10).strip()
        require(state in ("inactive", "failed"), service + " is " + state)


def atomic_copy(source, target, mode):
    fd, temporary = tempfile.mkstemp(prefix=".rb-quiesce-", dir=str(target.parent))
    try:
        with os.fdopen(fd, "wb") as out:
            with Path(source).open("rb") as inp:
                shutil.copyfileobj(inp, out)
            os.fchmod(out.fileno(), mode)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, str(target))
        directory_fd = os.open(str(target.parent), os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def deploy(bundle, targets, backup_root=Path("/home"), guard=stopped):
    guard()
    # Verify every input before changing any destination.
    for name, target in targets.items():
        require(sha(bundle / name) == EXPECTED[name], "incorrect bundle hash: " + name)
        require(target.is_file(), "original file missing: " + str(target))
    backup = Path(tempfile.mkdtemp(prefix="rb-m7-normal-stop-backup-", dir=str(backup_root)))
    manifest = {"result": "BACKED_UP", "files": {}}
    for name, target in targets.items():
        shutil.copy2(str(target), str(backup / name))
        old_hash = sha(target)
        require(sha(backup / name) == old_hash, "backup mismatch: " + name)
        manifest["files"][name] = {"target": str(target), "original_sha256": old_hash,
                                    "installed_sha256": EXPECTED[name],
                                    "original_mode": target.stat().st_mode & 0o777}
    report = backup / "manifest.json"
    report.write_text(json.dumps(manifest, indent=2) + "\n")
    os.sync()
    print("BACKUP: " + str(backup), flush=True)
    changed = []
    try:
        for name, target in targets.items():
            guard()
            changed.append(name)
            atomic_copy(bundle / name, target, 0o644 if name.endswith(".elf") else 0o755)
            require(sha(target) == EXPECTED[name], "installed hash mismatch: " + name)
        guard()
        manifest["result"] = "INSTALLED"
    except BaseException:
        manifest["result"] = "FAILED"
        try:
            guard()  # Never restore firmware underneath an unexpectedly running core.
            for name in reversed(changed):
                atomic_copy(backup / name, targets[name], manifest["files"][name]["original_mode"])
                require(sha(targets[name]) == manifest["files"][name]["original_sha256"],
                        "rollback hash mismatch: " + name)
            manifest["result"] = "ROLLED_BACK"
        except BaseException as exc:
            manifest["rollback_error"] = str(exc)
            print("Rollback incomplete; retain backup and do not start M7: " + str(exc), flush=True)
        raise
    finally:
        report.write_text(json.dumps(manifest, indent=2) + "\n")
        os.sync()
    print("INSTALL PASS: four matched files installed; M7 remains offline")
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", nargs="?", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    require(os.geteuid() == 0, "run as root on the MYIR board")
    require(Path("/sys/module/imx_rpmsg_tty/version").read_text().strip() ==
            "robobase-safe-teardown-1", "load the tested RPMsg driver before deployment")
    require((RPROC / "firmware").read_text().strip() == "robobase_m7_rpmsg_tty_echo.elf",
            "unexpected firmware name; preserve custom deployment and investigate")
    targets = {name: (Path("/lib/firmware") if name.endswith(".elf") else Path("/usr/bin")) / name
               for name in EXPECTED}
    # Resolve usrmerge directory links but reject individual custom file symlinks.
    for name, target in targets.items():
        require(not target.is_symlink(), "custom file symlink requires manual review: " + str(target))
        targets[name] = target.resolve()
    lock_fd = os.open("/tmp/rb-m7-normal-stop-install.lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        deploy(args.bundle.resolve(), targets)
    finally:
        os.close(lock_fd)


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as exc:
        print("FAIL: {}: {}".format(type(exc).__name__, exc), flush=True)
        raise SystemExit(1)
