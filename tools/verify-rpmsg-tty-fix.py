#!/usr/bin/env python3
"""Apply the BSP patch to a scratch copy and build a matching ARM64 module.

Requires an already-built MYIR kernel (configuration, Module.symvers and
Yocto cross compiler). Does not modify the kernel source or deploy to a board.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parents[1]
    platform_out = root / "build/out/myir_imx8m_plus"
    yocto_tmp = platform_out / "xwayland/yocto/tmp"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel-work", type=Path, default=yocto_tmp /
                        "work/myd_jx8mp-poky-linux/linux-imx/"
                        "5.10.72+gitAUTOINC+7da54520b8-r0")
    parser.add_argument("--kernel-source", type=Path, default=yocto_tmp /
                        "work-shared/myd-jx8mp/kernel-source")
    parser.add_argument("--output", type=Path, default=platform_out /
                        "diagnostics/rpmsg-tty-stop-fix")
    args = parser.parse_args()
    work = args.kernel_work.resolve()
    source = args.kernel_source.resolve()
    output = args.output.resolve()
    patch = root / ("platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/"
                    "recipes-kernel/linux/files/"
                    "0003-rpmsg-tty-serialize-remove-and-keep-port-alive.patch")
    driver = source / "drivers/rpmsg/imx_rpmsg_tty.c"
    build = work / "build"
    cross = work / ("recipe-sysroot-native/usr/bin/aarch64-poky-linux/"
                    "aarch64-poky-linux-")
    for path in (patch, driver, build / ".config", build / "Module.symvers",
                 Path(str(cross) + "gcc")):
        if not path.is_file():
            parser.error("required build input missing: {}".format(path))
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["PATH"] = str(cross.parent) + os.pathsep + env["PATH"]

    with tempfile.TemporaryDirectory(prefix="verify-", dir=str(output)) as tmp:
        scratch = Path(tmp)
        module_dir = scratch / "drivers/rpmsg"
        module_dir.mkdir(parents=True)
        patched = module_dir / driver.name
        shutil.copy2(driver, patched)
        with (output / "build.log").open("w") as log:
            subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-d",
                            str(scratch), "-i", str(patch)], check=True,
                           stdout=log, stderr=subprocess.STDOUT)
            (module_dir / "Makefile").write_text("obj-m += imx_rpmsg_tty.o\n")
            subprocess.run(["make", "-C", str(build), "M=" + str(module_dir),
                            "ARCH=arm64", "CROSS_COMPILE=" + str(cross),
                            "W=1", "modules"], env=env, check=True,
                           stdout=log, stderr=subprocess.STDOUT)
        module = output / "imx_rpmsg_tty.ko"
        shutil.copy2(module_dir / module.name, module)
        shutil.copy2(patched, output / "imx_rpmsg_tty.patched.c")
        info = subprocess.check_output(["modinfo", str(module)], text=True)
        (output / "modinfo.txt").write_text(info)
        manifest = {
            "module_sha256": sha256(module),
            "patch_sha256": sha256(patch),
            "original_source_sha256": sha256(driver),
            "patched_source_sha256": sha256(patched),
            "kernel_config_sha256": sha256(build / ".config"),
            "module_symvers_sha256": sha256(build / "Module.symvers"),
            "kernel_work": str(work),
            "kernel_source": str(source),
            "validation": "ARM64 external module build only; not board-tested",
        }
        (output / "manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n")
    print((output / "build.log").read_text())
    print(info)
    print("Artifact: {}\nSHA256: {}".format(module, manifest["module_sha256"]))


if __name__ == "__main__":
    main()
