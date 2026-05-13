# Current Project Status

Updated: 2026-05-14

This file is intended as the first file to read when starting a new Codex CLI
session. It captures the workspace context, current project state, verified
progress, and recommended next steps.

## New Codex CLI Startup Prompt

Copy or adapt this prompt when opening a fresh Codex CLI session:

```text
myplatform 下是我的工程文件，里面包含了我的两个项目 imx6ull 和 imx8mplus。

Imx8mp 下是 imx8mplus 的源码、原理图、硬件资料和软件开发教程。

i.MX8M Plus + Jetson Orin Nano Super 双脑机器人项目设计与实现报告.pdf
和 deep-research-report.md 是我即将要实现的大型项目。

请先阅读 myplatform/CURRENT_STATUS.md，再重点阅读 myplatform 里面的文档。
重点关注：

1. myplatform 的平台化工程结构和统一构建入口。
2. imx6ull_100ask_pro 当前 Buildroot/驱动学习进度。
3. myir_imx8m_plus 当前 Yocto、DTS、remoteproc、RPMsg、M7 固件进度。
4. 双脑机器人项目的主线：Jetson 负责 ROS2/感知/规划，i.MX8MP Linux
   负责 BSP/驱动/网关/日志，i.MX8MP M7 负责安全状态机和断链降级。

不要直接从零猜项目结构。先读当前状态，再根据任务继续推进。
```

## Workspace Map

Repository/workspace root:

```text
/home/compile/workstation/project/codex
```

Important top-level paths:

```text
myplatform/
Imx8mp/
deep-research-report.md
i.MX8M Plus + Jetson Orin Nano Super 双脑机器人项目设计与实现报告.pdf
PLATFORM_ARCH_DRAFT.md
PLATFORM_BUILD_FLOW_DRAFT.md
NOTES.md
100ask_imx6ull-sdk/
```

Meaning of the main directories:

- `myplatform/`: main platform workspace and long-term project repository.
- `Imx8mp/`: MYIR i.MX8M Plus vendor sources, hardware files, schematics, and
  software manuals.
- `100ask_imx6ull-sdk/`: legacy/reference SDK for the 100ask i.MX6ULL board.
- `deep-research-report.md` and the robot PDF: architecture and implementation
  target for the dual-brain robot project.

## myplatform Architecture

`myplatform` is the active engineering workspace.

Key directories:

```text
myplatform/
  apps/          user-space applications and shared app libraries
  platform/      board/product/manifests/common platform logic
  third_party/   Buildroot, Linux, U-Boot, Yocto, M7 SDK source entries
  build/         local build output, downloads, logs, sstate, mirrors
  tools/         bootstrap, fetch, build, pack, sdk, compare helpers
  docs/          architecture, board notes, build notes, debug records
```

The main build entry is:

```bash
cd /home/compile/workstation/project/codex/myplatform
make BOARD=<board> <target>
```

Current board backends:

- `imx6ull_100ask_pro`: Buildroot backend.
- `myir_imx8m_plus`: Yocto backend.

Important files:

- `Makefile`: top-level dispatcher.
- `README.md`: quick overview.
- `README_PLATFORM.md`: platform workspace guide.
- `docs/build_guide.md`: day-to-day build usage.
- `platform/common/mk/backend-buildroot.mk`: Buildroot backend.
- `platform/common/mk/backend-yocto.mk`: Yocto backend.
- `platform/boards/<board>/board.mk`: board-level paths.
- `platform/boards/<board>/model.mk`: model/backend/features/source selection.

## Project 1: imx6ull_100ask_pro

Board:

```text
BOARD=imx6ull_100ask_pro
SoC: i.MX6ULL
Vendor/reference: 100ask
Backend: Buildroot
Legacy SDK: 100ask_imx6ull-sdk
```

Current status:

- The platformized Buildroot path can build a full image from the unified entry.
- Linux, U-Boot, rootfs, and final SD image generation are already working.
- The output is not yet functionally or byte-for-byte equivalent to the old SDK.
- This board is currently best treated as the Linux driver learning and
  Buildroot platformization board.

Common commands:

```bash
cd /home/compile/workstation/project/codex/myplatform
./tools/bootstrap.sh imx6ull_100ask_pro
make BOARD=imx6ull_100ask_pro vars
make BOARD=imx6ull_100ask_pro buildroot
make BOARD=imx6ull_100ask_pro linux
make BOARD=imx6ull_100ask_pro uboot
make BOARD=imx6ull_100ask_pro busybox
make BOARD=imx6ull_100ask_pro app
```

Important output path:

```text
myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/images
```

Known image artifacts:

```text
100ask-imx6ull-pro-512d-systemv-v1.img
u-boot-dtb.imx
zImage
100ask_imx6ull-14x14.dtb
rootfs.ext2
rootfs.tar
```

Important documents:

- `docs/boards/imx6ull_100ask_pro_context_handover.md`
- `docs/boards/imx6ull_100ask_pro_artifact_compare.md`
- `docs/boards/imx6ull_100ask_pro_driver_learning_plan.md`
- `docs/boards/imx6ull_100ask_pro_pinctrl_learning_notes.md`
- `docs/boards/imx6ull_100ask_pro_i2c_learning_notes.md`
- `docs/boards/imx6ull_100ask_pro_uart_learning_notes.md`

Current imx6ull conclusions:

- `myplatform` can produce the full Buildroot image.
- The old SDK and `myplatform` outputs still differ.
- Key differences include rootfs size, network services, firmware directories,
  LVGL/HMI demo services, and package/overlay composition.
- If the goal is SDK compatibility, compare and align Buildroot configs,
  rootfs size, firmware directories, and old SDK services.
- If the goal is learning, focus on GPIO, pinctrl, UART, I2C, RS485, CAN, and
  platform drivers.

Recommended next imx6ull work:

1. Create a board signal map for `J5`, `J16`, `J17`, `J6`, and `J7`.
2. Add real lab notes under a board-specific lab directory.
3. Implement a minimal GPIO character/platform driver.
4. Continue comparing SDK vs `myplatform` rootfs only if compatibility is a
   concrete requirement.

## Project 2: myir_imx8m_plus

Board:

```text
BOARD=myir_imx8m_plus
SoC: i.MX8M Plus / i.MX8MP
Vendor/reference: MYIR MYD-JX8MP
Backend: Yocto
Yocto baseline: vendor 5.10.72 / Yocto 3.2.1 style BSP
Recommended host: Ubuntu 18.04 Docker container
```

Current status:

- Yocto builds have been brought up through the Docker environment.
- A custom `meta-robobase` layer exists.
- A custom `robobase-image` exists.
- A `test-yocto` recipe exists and is used to verify recipe-to-image install.
- DTB replacement workflow has been validated.
- CM7 remoteproc DTS support has been added by Yocto kernel patch.
- The CM7 TCM remoteproc hang has been debugged and fixed.
- A minimal M7 WFI firmware exists.
- A minimal M7 RPMsg tty echo firmware exists.
- The same M7 RPMsg firmware now also recognizes the first RoboBase safety
  protocol frames over `/dev/ttyRPMSG30`.
- A Linux user-space RPMsg tty echo and safety protocol test tool recipe now exists:
  `robobase-rpmsg-test`.
- M7 safety input handling has been split into a real GPIO input layer.
- M7 now samples J25 pin 23 / GPIO5_IO10 for E-stop NC and J25 pin 21 /
  GPIO5_IO12 for bumper NC.
- M7 safety work is now driven by a SysTick-backed 1ms pending tick path instead
  of being tied directly to RPMsg receive cadence.
- `robobase-m7-firmware` installs the M7 ELF into `/lib/firmware`.
- `robobase-m7-services` installs systemd services for automatic M7 remoteproc
  startup and RPMsg TTY loading.
- The latest source walkthrough records the minimal RPMsg path as successfully
  reaching `/dev/ttyRPMSG30` echo.

Common commands:

```bash
cd /home/compile/workstation/project/codex/myplatform
./platform/boards/myir_imx8m_plus/scripts/enter-env.sh --docker
make BOARD=myir_imx8m_plus vars
make BOARD=myir_imx8m_plus yocto
make BOARD=myir_imx8m_plus linux
make BOARD=myir_imx8m_plus uboot
make BOARD=myir_imx8m_plus sdk
```

Recommended Yocto command from inside the Docker/container workflow:

```bash
./platform/boards/myir_imx8m_plus/env/run-yocto.sh
```

Important Yocto output path:

```text
myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
```

Important artifacts:

```text
myir-image-full-myd-jx8mp.ext4
myir-image-full-myd-jx8mp.wic.bz2
myir-image-full-myd-jx8mp.tar.bz2
robobase-image-myd-jx8mp.wic.bz2
Image-myd-jx8mp.bin
myd-jx8mp-base.dtb
imx-boot
u-boot-myd-jx8mp.bin
```

Important documents:

- `docs/yocto_myir_imx8mp_guide.md`
- `docs/boards/myir_imx8m_plus_yocto_dts_beginner_notes.md`
- `docs/boards/myir_imx8m_plus_yocto_layer_remoteproc_rpmsg_notes.md`
- `docs/boards/myir_imx8m_plus_remoteproc_tcm_hang_debug.md`
- `docs/boards/myir_imx8m_plus_minimal_m7_rpmsg_firmware.md`
- `docs/boards/myir_imx8m_plus_remoteproc_rpmsg_source_walkthrough.md`
- `docs/boards/myir_imx8m_plus_m7_local_watchdog_validation.md`
- `docs/boards/myir_imx8m_plus_m7_autostart_services.md`
- `docs/boards/myir_imx8m_plus_jetson_robobase_project_roadmap.md`

## i.MX8MP Yocto Details

Board model config:

```text
platform/boards/myir_imx8m_plus/model.mk
```

Key settings:

```make
MODEL_BUILD_BACKEND := yocto
MODEL_OUTPUT_TAG := xwayland
MODEL_YOCTO_MACHINE := myd-jx8mp
MODEL_YOCTO_DISTRO := fsl-imx-xwayland
MODEL_YOCTO_IMAGE_TARGET := myir-image-full
MODEL_YOCTO_KERNEL_TARGET := virtual/kernel
MODEL_YOCTO_UBOOT_TARGET := u-boot-imx
```

Board `local.conf` fragment:

```text
platform/boards/myir_imx8m_plus/yocto/local.conf.fragment
```

Important settings:

- `UBOOT_CONFIG = "sd"`
- `UBOOT_CONFIG[sd] = "myd_jx8mp_defconfig,sdcard"`
- `BBMASK` masks unrelated `linux-yocto` recipes.
- `BB_SIGNATURE_HANDLER = "OEBasicHash"`
- `BB_HASHSERVE = ""`
- Parallelism is limited to `8` to avoid OOM on a 16 GiB host.

The DDR choice is explicit because the target board reports about `2.9 GiB`
usable RAM, matching the MYIR 3 GiB DDR option.

## meta-robobase Layer

Layer path:

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase
```

Current contents:

```text
conf/layer.conf
recipes-core/images/robobase-image.bb
recipes-robobase/robobase-demo/test-yocto_0.1.bb
recipes-robobase/robobase-rpmsg-test/robobase-rpmsg-test_0.1.bb
recipes-robobase/robobase-m7-firmware/robobase-m7-firmware_0.1.bb
recipes-robobase/robobase-m7-services/robobase-m7-services_0.1.bb
recipes-kernel/linux/linux-imx_%.bbappend
recipes-kernel/linux/files/0001-myir-imx8mp-enable-cm7-remoteproc.patch
recipes-kernel/linux/files/0002-remoteproc-add-robobase-cm7-boot-debug-logs.patch
```

Shared Linux/M7 protocol header:

```text
platform/common/include/robobase/rb_safety_proto.h
```

Notes:

- `robobase-image.bb` currently requires the MYIR `myir-image-full.bb` and
  appends `test-yocto`, `robobase-rpmsg-test`, `robobase-m7-firmware`, and
  `robobase-m7-services`.
- `robobase-rpmsg-test` installs `/usr/bin/robobase-rpmsg-test`, a Linux
  user-space tool for writing to `/dev/ttyRPMSG30`, verifying the echoed
  response from the M7 RPMsg tty firmware, and sending first-version RoboBase
  safety protocol messages. It also supports GPIO debug input commands for
  bench validation.
- `robobase-m7-firmware` installs
  `/lib/firmware/robobase_m7_rpmsg_tty_echo.elf` from the M7 build output.
- `robobase-m7-services` installs and enables `robobase-m7.service` and
  `robobase-rpmsg-tty.service`.
- `rb_safety_proto.h` defines the first shared Linux/M7 safety ABI:
  `LEASE`, `STATUS`, `CLEAR_FAULT`, `DEBUG_INPUTS`, state enum, and fault
  bitmask.
- `linux-imx_%.bbappend` appends the CM7 remoteproc DTS patch and a debug patch.
- The debug patch is useful during bring-up but should be removed or converted
  to `dev_dbg` once the path is stable.

## CM7 Remoteproc/RPMsg Status

Linux remoteproc path:

```text
/sys/class/remoteproc/remoteproc0
```

Expected name:

```text
imx-rproc
```

Important DTS node added by patch:

```dts
imx8mp-cm7 {
	compatible = "fsl,imx8mp-cm7";
	rsc-da = <0x55000000>;
	clocks = <&clk IMX8MP_CLK_M7_CORE>;
	mbox-names = "tx", "rx", "rxdb";
	mboxes = <&mu 0 1
		  &mu 1 1
		  &mu 3 1>;
	memory-region = <&vdevbuffer>, <&vdev0vring0>,
			<&vdev0vring1>, <&rsc_table>;
	status = "okay";
};
```

Critical debug conclusion:

- The original hang happened while Linux remoteproc was loading ELF segments
  into CM7 ITCM at `0x007e0000`.
- M7 code had not started yet, so it was not caused by M7 application logic.
- U-Boot could read/write ITCM and `bootaux` could start CM7.
- `clk_ignore_unused` made Linux remoteproc work, proving a clock dependency
  problem.
- The proper fix was changing the CM7 remoteproc clock from the old/non-working
  `IMX8MP_CLK_M7_DIV` path to the real registered clock
  `IMX8MP_CLK_M7_CORE`.

Verify running DTB clock cell on the board:

```sh
hexdump -Cv /proc/device-tree/imx8mp-cm7/clocks
```

Expected final bytes:

```text
00 00 00 02 00 00 01 31
```

`0x131` is `305`, which corresponds to `IMX8MP_CLK_M7_CORE`.

## M7 Firmware Status

M7 dependency directory:

```text
third_party/m7
```

Main firmware project:

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only
```

Current firmware outputs:

```text
armgcc/debug/robobase_m7_boot_only.elf
armgcc/debug/robobase_m7_boot_only.bin
armgcc/debug/robobase_m7_boot_only_wfi.elf
armgcc/debug/robobase_m7_rpmsg_tty_echo.elf
armgcc/debug/robobase_m7_rpmsg_tty_echo.bin
```

Build:

```bash
export ARMGCC_DIR=/home/compile/workstation/project/codex/myplatform/third_party/m7/gcc-arm-none-eabi-7-2017-q4-major
cd /home/compile/workstation/project/codex/myplatform/third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc
./build_debug.sh
```

Deploy:

```bash
bitbake robobase-m7-firmware
bitbake robobase-m7-services
bitbake robobase-image
```

The current productized path installs
`/lib/firmware/robobase_m7_rpmsg_tty_echo.elf` into the image and starts it via
systemd. Manual `scp` is still useful for quick bring-up, but is no longer the
preferred validation path.

RPMsg shared memory layout:

```text
vring0:     0x55000000, size 0x8000
vring1:     0x55008000, size 0x8000
rsc_table:  0x550ff000, size 0x1000
vdevbuffer: 0x55400000, size 0x100000
```

RPMsg channel name:

```text
rpmsg-virtual-tty-channel-1
```

Latest documented successful Linux user path:

```text
Linux userspace
-> ttyRPMSG30
-> imx_rpmsg_tty
-> rpmsg core
-> virtio_rpmsg_bus
-> remoteproc virtio
-> imx_rproc MU kick
-> M7 RPMsg-Lite
-> M7 echo
-> MU kick
-> Linux rpmsg_recv_done
-> ttyRPMSG30
-> Linux userspace
```

## Board-Side RPMsg Test Commands

Start from a clean board boot when possible.

```sh
R=/sys/class/remoteproc/remoteproc0
cat "$R/name"
cat "$R/state"
cat "$R/firmware"
```

Load Linux tty RPMsg driver:

```sh
modprobe imx_rpmsg_tty
lsmod | grep -Ei 'rpmsg|imx_rpmsg_tty'
```

Manual start firmware:

```sh
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_rpmsg_tty_echo.elf > "$R/firmware"
echo start > "$R/state"
cat "$R/state"
```

Preferred automatic services:

```sh
systemctl status robobase-m7.service
systemctl status robobase-rpmsg-tty.service
systemctl restart robobase-m7.service
systemctl restart robobase-rpmsg-tty.service
ls /dev/ttyRPMSG*
```

Inspect:

```sh
dmesg | grep -Ei 'remoteproc|imx-rproc|virtio_rpmsg|rpmsg|ttyRPMSG' | tail -160
find /sys/bus/rpmsg -maxdepth 3 -type f -o -type l
ls -l /dev | grep -Ei 'rpmsg|ttyRPMSG'
```

Echo test:

```sh
robobase-rpmsg-test -d /dev/ttyRPMSG30 -n 10 -t 1000
```

If all messages report `ok`, A53 to M7 to A53 RPMsg communication works.

Safety protocol test:

```sh
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 -n 10 -t 1000
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 --upstream-invalid
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 --driver-fault
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 --power-fault
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 --clear-fault 0xffffffff
```

GPIO safety input status is included in `STATUS`:

```text
estop_nc=<0|1> bumper_nc=<0|1>
```

Current hardware mapping:

```text
E-stop NC auxiliary contact: J25 pin 23, ECSPI2_SCLK_3V3, GPIO5_IO10
Bumper/microswitch NC:       J25 pin 21, ECSPI2_MISO_3V3, GPIO5_IO12
```

Expected first-version behavior:

- Valid lease: M7 reports `state=RUNNING`, `motion=1`, and `fault=0x00000000`.
- Invalid upstream lease: M7 reports `state=SAFE_STOP`, `motion=0`, and sets
  `RB_FAULT_UPSTREAM_TIMEOUT`.
- Driver or power fault flags currently behave as transient Linux health
  inputs; they clear when later valid leases report them healthy again.

M7 local watchdog test:

```sh
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 --lease-timeout-ms 200 -n 1
sleep 1
robobase-rpmsg-test --query-status -d /dev/ttyRPMSG30
```

Expected watchdog behavior:

- Query does not refresh the lease.
- M7 reports `state=SAFE_STOP`, `motion=0`, and `fault=0x00000004`.
- `0x00000004` is `RB_FAULT_LINUX_TIMEOUT`.

## Dual-Brain Robot Project

Project concept:

```text
RoboBase-X: dual-brain safety mobile robot base
```

Target split:

- Jetson Orin Nano Super:
  ROS2, perception, planning, visualization, rosbag, high-level debugging.
- i.MX8M Plus Linux:
  BSP, drivers, board peripherals, lower-level gateway, logging, config,
  health monitoring, factory diagnostics.
- i.MX8M Plus M7:
  safety state machine, estop/bumper latch, Linux watchdog, link-loss degrade,
  motion authorization.

Important project reports:

- `deep-research-report.md`
- `i.MX8M Plus + Jetson Orin Nano Super 双脑机器人项目设计与实现报告.pdf`
- `docs/boards/myir_imx8m_plus_jetson_robobase_project_roadmap.md`

Core principle:

```text
Do not build two Linux boards fighting for control.
Use Jetson as the task/perception brain, i.MX8MP Linux as the gateway/BSP brain,
and M7 as the safety island.
```

Recommended system direction:

- Do not send naked `/cmd_vel` directly to the actuator layer.
- Use a lease-based board-to-board protocol.
- Include `seq`, `lease_expiry`, `crc`, version/capability negotiation, and
  explicit fault/state messages.
- Log every safety transition.
- Make failures measurable through fault injection, soak tests, and blackbox
  records.

Planned high-level milestones:

1. M1: i.MX8MP lower-board baseline.
   Yocto builds, board boots, serial/network work.
2. M2: safety chain.
   M7 remoteproc works, RPMsg heartbeat works, at least one safety degrade path.
3. M3: dual-board control.
   Jetson sends lease/control, i.MX replies with state, link loss stops motion.
4. M4: demonstrable project.
   Basic actuator loop, perception safety scenario, metrics, logs, docs, video.

## Current Recommended Next Steps

Highest priority for the active robot path:

1. Run `bitbake robobase-rpmsg-test` inside the MYIR Yocto Docker environment
   to produce the ARM64 board binary with the new safety protocol support.
2. SCP both artifacts to the board:
   `/usr/bin/robobase-rpmsg-test` and
   `/lib/firmware/robobase_m7_rpmsg_tty_echo.elf`.
3. Validate echo mode first, then validate safety mode:
   `--safety`, `--upstream-invalid`, `--driver-fault`, `--power-fault`, and
   `--clear-fault`.
1. Replace temporary/noisy remoteproc debug logs with quieter debug-level output
   once no longer needed.
2. Decide whether to keep M7 in bare-metal cooperative scheduling for the next
   milestone or introduce RTOS for a high-priority safety task.
3. Add CRC or another integrity check for the shared Linux/M7 safety protocol.
4. Rename Linux-provided `driver_ok` and `power_ok` fields to make the safety
   responsibility boundary clearer.
5. Wire and validate the final two-NC E-stop and bumper hardware path.
6. Start designing the permanent `robobase-safetyd` Linux daemon. The current
   `robobase-rpmsg-test` remains a validation tool, not the final service
   process.

Do not prioritize Jetson/ROS2 integration before the i.MX8MP lower-board and
M7 safety chain are stable.

## Latest Implementation Snapshot On 2026-05-14

The first RoboBase M7 safety protocol has been extended into a boot-integrated
lower-board safety bring-up path over `/dev/ttyRPMSG30`.

Implemented source paths:

```text
platform/common/include/robobase/rb_safety_proto.h
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-robobase/robobase-rpmsg-test/
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-robobase/robobase-m7-firmware/
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-robobase/robobase-m7-services/
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/
```

Implemented protocol pieces:

- Linux to M7 `LEASE`
- M7 to Linux `STATUS`
- Linux to M7 `CLEAR_FAULT`
- Linux to M7 `HELLO` as a status query that does not refresh the lease
- States: `BOOT`, `STANDBY`, `ARMED`, `RUNNING`, `SAFE_STOP`,
  `FAULT_LATCHED`
- Fault bits: estop, bumper, Linux timeout, upstream timeout, driver fault,
  power fault, protocol error
- M7 local SysTick watchdog detects Linux lease expiry even when no new RPMsg
  frame arrives.
- M7 1ms safety tick processing samples real GPIO inputs and updates watchdog
  state outside the SysTick interrupt.
- Systemd can start M7 via remoteproc and then load RPMsg TTY automatically.
- Yocto can package the M7 ELF into `/lib/firmware`.

Verified locally:

```text
gcc -Wall -Wextra -std=c11 ... robobase-rpmsg-test.c
./build_debug.sh for robobase_m7_rpmsg_tty_echo.elf
bitbake robobase-rpmsg-test
bitbake robobase-m7-firmware
bitbake robobase-m7-services -n
git diff --check
```

Verified on MYD-JX8MP board:

```text
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 -n 3
-> state=RUNNING motion=1 fault=0x00000000, 3/3 ok

robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 --lease-timeout-ms 200 -n 1
sleep 1
robobase-rpmsg-test --query-status -d /dev/ttyRPMSG30
-> state=SAFE_STOP motion=0 fault=0x00000004
```

Also verified on board:

```text
robobase-image with robobase-m7-firmware and robobase-m7-services boots.
M7 firmware is present under /lib/firmware.
robobase-m7.service and robobase-rpmsg-tty.service bring up the RPMsg path.
```

Detailed validation note:

```text
docs/boards/myir_imx8m_plus_m7_local_watchdog_validation.md
docs/boards/myir_imx8m_plus_m7_autostart_services.md
```

## Known Risks And Notes

- Yocto build output, `sstate-cache`, downloads, and local mirrors are large
  local build assets. Do not treat them as normal source code.
- `third_party/m7/mcuxpresso-sdk` is a large west-downloaded workspace and
  should not be committed wholesale.
- The current RPMsg-Lite build uses the curated `rpmsg-lite-minimal` copy.
- The `0002-remoteproc-add-robobase-cm7-boot-debug-logs.patch` is a bring-up
  aid, not a long-term product patch.
- If `modprobe imx_rpmsg_tty` fails on the board, check that running `Image`,
  DTB, and `/lib/modules/$(uname -r)` all come from the same Yocto build.
- If remoteproc hangs again, first verify the running DTB clock cell and confirm
  `clk_ignore_unused` is not being relied on as the final fix.

## Observed Worktree State On 2026-05-06

At the time this status file was written, `myplatform` already had unrelated
local/untracked changes. Do not remove them unless the user explicitly asks.

Observed examples:

```text
M docs/boards/README.md
? third_party/buildroot/buildroot-2020.02
?? apps/private/24c16/
?? apps/private/Makefile.txt
?? apps/private/eeprom24c16/eeprom24c16
?? build/local-mirrors/
?? build/sstate-cache/
?? docs/boards/myir_imx8m_plus_remoteproc_rpmsg_source_walkthrough.md
?? platform/boards/imx6ull_100ask_pro/env/host-manual-packages.txt
```

This file itself was added as:

```text
myplatform/CURRENT_STATUS.md
```
