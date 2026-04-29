# MYIR i.MX8MP 最小 M7 RPMsg 固件实现记录

本文记录在 MYIR MYD-JX8MP 上为 CM7 制作最小 RPMsg tty echo 固件的过程。目标是用尽量少的 M7 侧代码验证 Linux `remoteproc` + `virtio_rpmsg_bus` + `imx_rpmsg_tty` 通信链路，而不是直接运行 NXP/MYIR 预置 FreeRTOS demo。

适用对象：

```text
Board: MYIR MYD-JX8MP
SoC: NXP i.MX8M Plus
Linux: linux-imx 5.10.72
Remote core: Cortex-M7 / CM7
Linux remoteproc: imx-rproc
Linux RPMsg driver: imx_rpmsg_tty
```

相关工程路径：

```text
/home/compile/workstation/project/codex/myplatform
```

最小固件工程：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only
```

新增 RPMsg 固件产物：

```text
armgcc/debug/robobase_m7_rpmsg_tty_echo.elf
armgcc/debug/robobase_m7_rpmsg_tty_echo.bin
```

---

## 1. 背景和问题

前面已经完成了 Linux 侧 CM7 `remoteproc` bring-up：

```text
1. Yocto layer 和内核补丁已经能构建。
2. DTS 中已经加入 imx8mp-cm7 节点。
3. CM7 TCM 卡死问题已定位并修复。
4. Linux 下 remoteproc0 能启动 boot-only WFI 固件。
5. Linux 下 virtio_rpmsg_bus 能上线。
```

但测试 NXP/MYIR 预置 RPMsg 固件时，出现过两个问题：

```text
1. 早期会在 remoteproc 加载 TCM 段时卡死。
2. 修复 TCM clock 后，virtio rpmsg host 能上线，但只有 rpmsg_ctrl/rpmsg_ns，没有业务 channel，也没有 /dev/ttyRPMSG0。
```

典型现象：

```text
virtio_rpmsg_bus virtio0: rpmsg host is online
remoteproc0#vdev0buffer: registered virtio0 (type 7)

/sys/bus/rpmsg/devices/virtio0.rpmsg_ctrl.0.0
/sys/bus/rpmsg/devices/virtio0.rpmsg_ns.53.53
/dev/rpmsg_ctrl0
```

这说明 Linux 侧 RPMsg transport 已经起来，但 M7 固件没有成功 announce 业务通道，或者没有运行到业务代码。

预置固件不适合作为下一步基线，原因是：

```text
1. 固件源码不可见，无法确认它改了哪些 clock/RDC/pinmux/外设。
2. FreeRTOS demo 会调用 BOARD_InitHardware()、BOARD_InitDebugConsole() 和 PRINTF。
3. 板子不是标准 EVK，官方 demo 的 UART/pinmux/外设假设不一定适配 MYIR 板。
4. 出问题时无法在 M7 侧加最小化调试点。
```

因此采用更稳的策略：

```text
先做一个最小 M7 RPMsg tty echo 固件，只初始化 MU + RPMsg-Lite，不初始化板级外设。
```

---

## 2. 基线依赖

### 2.1 旧 SDK 作为可启动骨架

当前已经验证过的 boot-only 工程来自旧 SDK：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP
```

这个工程已经验证：

```text
1. startup/linker/toolchain 可用。
2. remoteproc 能把 ELF 段加载到 CM7 TCM。
3. CM7 能启动并进入 WFI。
```

保留它作为可靠骨架，而不是切换到全新的 SDK 构建系统。

### 2.2 新 MCUX SDK 只作为 RPMsg-Lite 上游来源

旧 SDK 缺少完整 `rpmsg-lite` middleware，因此通过 west 下载新 MCUX SDK：

```text
third_party/m7/mcuxpresso-sdk/mcuxsdk
```

关键源码路径：

```text
middleware/multicore/rpmsg-lite
middleware/multicore/remoteproc/remoteproc.h
examples/_boards/evkmimx8mp/multicore_examples/rpmsg_lite_str_echo_rtos
examples/_boards/evkmimx8mp/rsc_table.c
examples/_boards/evkmimx8mp/rsc_table.h
```

这个 8.3 GB workspace 不作为工程的直接构建依赖，也不建议提交。它只用于追溯和抽取源码。

### 2.3 当前实际构建依赖的最小源码副本

现在已从新 MCUX SDK 中抽出当前固件真正需要的最小源码副本：

```text
third_party/m7/rpmsg-lite-minimal
```

该目录包含：

```text
rpmsg-lite/lib/rpmsg_lite/rpmsg_lite.c
rpmsg-lite/lib/rpmsg_lite/rpmsg_ns.c
rpmsg-lite/lib/rpmsg_lite/porting/environment/rpmsg_env_bm.c
rpmsg-lite/lib/rpmsg_lite/porting/platform/imx8mp_m7/rpmsg_platform.c
rpmsg-lite/lib/virtio/virtqueue.c
rpmsg-lite/lib/common/llist.c
rpmsg-lite/lib/include/*
rpmsg-lite/lib/include/environment/bm/rpmsg_env_specific.h
rpmsg-lite/lib/include/platform/imx8mp_m7/rpmsg_platform.h
remoteproc/remoteproc.h
```

也就是说，`robobase_m7_rpmsg_tty_echo.elf` 的构建不再需要访问完整 `mcuxpresso-sdk/`。

---

## 3. 固件设计原则

最小固件必须满足：

```text
1. 使用 Linux remoteproc 启动。
2. ELF 内包含 .resource_table。
3. resource table 声明 virtio rpmsg vdev 和两个 vring。
4. 共享内存地址与 Linux DTS reserved-memory 完全一致。
5. M7 侧 announce Linux imx_rpmsg_tty 能匹配的 channel name。
6. 不初始化 UART、pinmux、clock tree、RDC、AudioMix、I2C、SPI、CAN、SAI、SDMA。
```

通道名选择：

```text
rpmsg-virtual-tty-channel-1
```

依据是 Linux 侧 `imx_rpmsg_tty` 驱动支持该 ID。预置 `str_echo` 固件里也能通过 `strings` 看到同名 channel。

共享内存地址：

```text
vring0:     0x55000000, size 0x8000
vring1:     0x55008000, size 0x8000
rsc_table:  0x550ff000, size 0x1000
vdevbuffer: 0x55400000, size 0x100000
```

这些地址必须和 Yocto DTS 补丁中的 reserved-memory 保持一致。

---

## 4. 新增文件

### 4.1 `robobase_m7_rpmsg_tty_echo.c`

路径：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/robobase_m7_rpmsg_tty_echo.c
```

作用：

```text
1. 调用 rpmsg_lite_remote_init() 初始化 remote 端。
2. 等待 Linux host link up。
3. 创建 endpoint 30。
4. announce rpmsg-virtual-tty-channel-1。
5. 收到 Linux 发来的数据后原样 echo 回去。
```

关键点：

```text
ROBOBASE_RPMSG_SHMEM_BASE = 0x55000000
ROBOBASE_RPMSG_LOCAL_EPT_ADDR = 30
ROBOBASE_RPMSG_CHANNEL_NAME = "rpmsg-virtual-tty-channel-1"
```

为什么不用 `rpmsg_queue`：

```text
1. `rpmsg_queue` 依赖环境层 queue API。
2. RPMsg-Lite bare-metal 环境没有实现真正 OS queue。
3. 最小固件只需要一个 endpoint callback，把收到的数据复制到静态 buffer，再在主循环中发送回去。
```

为什么使用静态 API：

```text
1. 减少 malloc/free 对 heap 的依赖。
2. 行为更可控。
3. 固件更适合早期 bring-up。
```

### 4.2 `robobase_m7_rsc_table.c`

路径：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/robobase_m7_rsc_table.c
```

作用：

```text
1. 在 ELF 的 .resource_table section 中放入 resource table。
2. 声明一个 RSC_VDEV，virtio id = 7，也就是 RPMsg。
3. 声明两个 vring，地址分别是 0x55000000 和 0x55008000。
4. 设置 RSC_VDEV_FEATURE_NS，表示支持 name service announce。
```

resource table 中两个 vring：

```text
{0x55000000, 0x1000, 256, 0, 0}
{0x55008000, 0x1000, 256, 1, 0}
```

其中：

```text
0x1000: Linux 侧要求的 vring alignment
256: RL_BUFFER_COUNT
0/1: notify id
```

### 4.3 `rpmsg_config.h`

路径：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/rpmsg_config.h
```

关键配置：

```c
#define RL_BUFFER_PAYLOAD_SIZE (496U)
#define RL_BUFFER_COUNT (256U)
#define RL_USE_STATIC_API (1)
#define RL_USE_ENVIRONMENT_CONTEXT (0)
#define RL_USE_DCACHE (0)
```

解释：

```text
496 + 16 = 512 字节，这是 Linux RPMsg 常见 buffer 大小。
256 是每个 vring 的 descriptor 数量。
RL_USE_STATIC_API=1 用静态上下文，减少动态内存风险。
RL_USE_DCACHE=0 因为当前没有启用 M7 D-cache/MPU 初始化，避免 cache coherency 复杂化。
```

### 4.4 `armgcc/CMakeLists.txt`

原工程只生成：

```text
robobase_m7_boot_only.elf
```

现在额外生成：

```text
robobase_m7_rpmsg_tty_echo.elf
```

新增 target 直接编译以下源码：

```text
robobase_m7_rpmsg_tty_echo.c
robobase_m7_rsc_table.c
third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/rpmsg_lite.c
third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/rpmsg_ns.c
third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/porting/environment/rpmsg_env_bm.c
third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/porting/platform/imx8mp_m7/rpmsg_platform.c
third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/virtio/virtqueue.c
third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/common/llist.c
fsl_common.c
fsl_common_arm.c
fsl_mu.c
startup_MIMX8ML8_cm7.S
system_MIMX8ML8_cm7.c
```

重要编译宏：

```text
SDK_DEBUGCONSOLE=2
FSL_SDK_DISABLE_DRIVER_CLOCK_CONTROL=1
```

含义：

```text
SDK_DEBUGCONSOLE=2 禁用 debug console，避免引入 UART/serial manager。
FSL_SDK_DISABLE_DRIVER_CLOCK_CONTROL=1 让 fsl_mu.c 不调用 CLOCK_EnableClock()，避免改 Linux 已经管理的 clock tree。
```

---

## 5. 构建方法

设置 toolchain：

```sh
export ARMGCC_DIR=/home/compile/workstation/project/codex/myplatform/third_party/m7/gcc-arm-none-eabi-7-2017-q4-major
```

进入工程：

```sh
cd /home/compile/workstation/project/codex/myplatform/third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc
```

构建：

```sh
./build_debug.sh
```

当前已验证构建成功，输出：

```text
debug/robobase_m7_boot_only.elf
debug/robobase_m7_boot_only.bin
debug/robobase_m7_rpmsg_tty_echo.elf
debug/robobase_m7_rpmsg_tty_echo.bin
```

当前产物大小：

```text
robobase_m7_boot_only.bin:         2.9K
robobase_m7_boot_only.elf:         155K
robobase_m7_rpmsg_tty_echo.bin:    12K
robobase_m7_rpmsg_tty_echo.elf:    249K
```

---

## 6. ELF 检查

检查 `.resource_table`：

```sh
arm-none-eabi-readelf -S debug/robobase_m7_rpmsg_tty_echo.elf | grep resource
```

当前结果：

```text
.resource_table PROGBITS 00000400 ... Size 000058
```

`0x58` 说明不是空表，而是包含 RPMsg vdev 和两个 vring。

检查 program header：

```sh
arm-none-eabi-readelf -l debug/robobase_m7_rpmsg_tty_echo.elf
```

当前入口：

```text
Entry point 0x515
```

检查 channel 字符串：

```sh
strings debug/robobase_m7_rpmsg_tty_echo.elf | grep rpmsg
```

应该看到：

```text
rpmsg-virtual-tty-channel-1
```

检查 resource table 内容：

```sh
arm-none-eabi-objdump -s -j .resource_table debug/robobase_m7_rpmsg_tty_echo.elf
```

关键字段：

```text
version = 1
num = 1
type = RSC_VDEV
id = 7
dfeatures = 1
num_of_vrings = 2
vring0 da = 0x55000000
vring1 da = 0x55008000
```

---

## 7. 部署到板子

从 PC 拷贝到目标板：

```sh
cd /home/compile/workstation/project/codex/myplatform/third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc
scp -O debug/robobase_m7_rpmsg_tty_echo.elf root@192.168.1.8:/lib/firmware/
```

如果 `scp` 报：

```text
/usr/libexec/sftp-server: No such file or directory
```

使用：

```sh
scp -O ...
```

原因是目标板 OpenSSH 环境没有 sftp-server，`-O` 会使用 legacy scp 协议。

---

## 8. 板端验证步骤

必须从干净重启后的板子开始验证。不要在某个 M7 固件 `force stop` 后直接切换另一个固件测试，因为 CM7/ATF/MU 状态可能已经不干净。

### 8.1 确认 remoteproc 初始状态

```sh
R=/sys/class/remoteproc/remoteproc0
cat "$R/name"
cat "$R/state"
cat "$R/firmware"
```

期望：

```text
imx-rproc
offline
```

### 8.2 加载 Linux tty RPMsg driver

```sh
modprobe imx_rpmsg_tty
lsmod | grep -Ei 'rpmsg|imx_rpmsg_tty'
```

如果 `modprobe` 找不到模块，先检查内核和 `/lib/modules` 是否匹配：

```sh
uname -r
ls -ld /lib/modules/$(uname -r)
find /lib/modules/$(uname -r) -name '*rpmsg*'
```

### 8.3 启动 M7 固件

```sh
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_rpmsg_tty_echo.elf > "$R/firmware"
echo start > "$R/state"
cat "$R/state"
```

期望：

```text
running
```

查看日志：

```sh
dmesg | grep -Ei 'remoteproc|virtio_rpmsg|rpmsg|ttyRPMSG|rpmsg-virtual' | tail -120
```

期望至少看到：

```text
virtio_rpmsg_bus virtio0: rpmsg host is online
remote processor imx-rproc is now up
```

### 8.4 检查 RPMsg device

```sh
for d in /sys/bus/rpmsg/devices/*; do
    echo "== $d =="
    [ -e "$d/name" ] && cat "$d/name"
    [ -e "$d/src" ] && cat "$d/src"
    [ -e "$d/dst" ] && cat "$d/dst"
    readlink "$d/driver" 2>/dev/null
done
```

成功时应出现业务通道：

```text
rpmsg-virtual-tty-channel-1
```

检查设备节点：

```sh
ls -l /dev | grep -Ei 'rpmsg|ttyRPMSG'
```

成功时应看到：

```text
/dev/ttyRPMSG0
```

### 8.5 Echo 测试

```sh
TTY=/dev/ttyRPMSG0
stty -F "$TTY" raw -echo -icanon min 0 time 10
cat "$TTY" &
CATPID=$!
printf 'robobase-test\n' > "$TTY"
sleep 1
kill "$CATPID"
```

如果链路正常，`cat` 应该能读回同样的字符串。

---

## 9. 失败排查

### 9.1 只有 `rpmsg_ctrl` 和 `rpmsg_ns`

现象：

```text
/sys/bus/rpmsg/devices/virtio0.rpmsg_ctrl.0.0
/sys/bus/rpmsg/devices/virtio0.rpmsg_ns.53.53
/dev/rpmsg_ctrl0
```

含义：

```text
Linux virtio_rpmsg_bus 已经起来，但 M7 没有 announce tty channel，或者 announce 没被 Linux 捕获。
```

抓取信息：

```sh
cat /sys/class/remoteproc/remoteproc0/state
dmesg | grep -Ei 'remoteproc|virtio_rpmsg|rpmsg|ttyRPMSG|imx-rproc' | tail -200
find /sys/bus/rpmsg -maxdepth 3 -type f -o -type l
```

重点看：

```text
1. remoteproc 是否 running。
2. virtio_rpmsg_bus 是否 online。
3. 是否出现 rpmsg-virtual-tty-channel-1。
4. imx_rpmsg_tty 是否已经 modprobe。
```

### 9.2 `echo start` 后卡死

先不要继续换固件反复试。抓取最近串口日志，确认卡在哪一步。

之前已经验证过的关键结论：

```text
如果卡在 remoteproc load_segments 的 TCM memcpy，优先检查 DTS clocks 是否为 IMX8MP_CLK_M7_CORE。
```

当前最小固件已经避免：

```text
1. UART 初始化。
2. pinmux 初始化。
3. board clock 初始化。
4. RDC 初始化。
5. FreeRTOS。
```

如果它仍卡死，优先怀疑：

```text
1. 仍在使用旧 DTB 或旧 Image。
2. CM7/MU 状态不干净，需要硬重启或远程复位手段。
3. resource table 或 reserved-memory 与实际运行内核不匹配。
4. Linux 模块和 Image 版本不匹配。
```

### 9.3 `modprobe imx_rpmsg_tty` 找不到模块

检查：

```sh
uname -r
ls -l /lib/modules
find /lib/modules/$(uname -r) -name '*rpmsg*'
```

如果 `/lib/modules/$(uname -r)` 不存在，说明当前运行的 `Image` 和 rootfs 里的 modules 不匹配。需要同步部署同一次 Yocto 构建产物里的：

```text
Image
myd-jx8mp-base.dtb
/lib/modules/$(uname -r)
```

---

## 10. 当前状态

主机侧已完成：

```text
1. 最小 RPMsg tty echo 固件源码已添加。
2. armgcc 工程已增加第二个 target。
3. 构建已通过。
4. ELF 已确认包含非空 .resource_table。
5. channel 字符串已确认是 rpmsg-virtual-tty-channel-1。
```

待板端验证：

```text
1. remoteproc 启动 robobase_m7_rpmsg_tty_echo.elf 后是否稳定 running。
2. Linux 是否出现 rpmsg-virtual-tty-channel-1。
3. 是否生成 /dev/ttyRPMSG0。
4. echo 测试是否能收发。
```

如果该固件验证通过，下一步可以在这个最小基线上逐步增加：

```text
1. 自定义协议帧。
2. A53 到 M7 的电机/传感器控制命令。
3. M7 到 A53 的实时状态上报。
4. Yocto recipe，把 M7 固件安装进 /lib/firmware。
```

---

## 11. 建议提交范围

这次 RPMsg 最小固件工作建议提交：

```text
docs/boards/myir_imx8m_plus_minimal_m7_rpmsg_firmware.md
docs/README.md
docs/boards/README.md
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/README.md
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/rpmsg_config.h
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/robobase_m7_rpmsg_tty_echo.c
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/robobase_m7_rsc_table.c
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc/CMakeLists.txt
third_party/m7/.gitignore
third_party/m7/README.md
third_party/m7/rpmsg-lite-minimal/README.md
third_party/m7/rpmsg-lite-minimal/rpmsg-lite/...
third_party/m7/rpmsg-lite-minimal/remoteproc/remoteproc.h
```

是否提交 `debug/*.elf` 和 `debug/*.bin` 取决于仓库策略。一般建议不提交构建产物；如果当前阶段为了远程调试方便，也可以临时提交 `robobase_m7_rpmsg_tty_echo.elf`，但长期应改为用脚本或 Yocto recipe 生成并安装到 `/lib/firmware`。

不建议直接提交整个：

```text
third_party/m7/mcuxpresso-sdk
```

原因是它是完整 west 下载的 SDK，体积很大，适合用下载脚本、manifest 或外部归档管理，而不是直接纳入业务代码提交。当前构建已经改为使用 `third_party/m7/rpmsg-lite-minimal`，因此提交时不需要带上完整 SDK。
