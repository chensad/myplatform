# MYIR i.MX8MP M7 固件与 RPMsg TTY 开机自动加载

本文记录 RoboBase 在 MYD-JX8MP 上把 M7 固件和 RPMsg TTY 链路纳入 Yocto
镜像与 systemd 开机流程的实现。

## 目标

之前的调试流程需要登录板子后手动执行：

```sh
modprobe imx_rpmsg_tty
echo robobase_m7_rpmsg_tty_echo.elf > /sys/class/remoteproc/remoteproc0/firmware
echo start > /sys/class/remoteproc/remoteproc0/state
```

当前实现改成：

```text
Yocto 镜像安装 M7 ELF 到 /lib/firmware
systemd 开机启动 M7 remoteproc
systemd 自动加载 imx_rpmsg_tty
等待 /dev/ttyRPMSG* 出现
```

## Yocto Recipes

新增固件包：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/
  recipes-robobase/robobase-m7-firmware/robobase-m7-firmware_0.1.bb
```

它安装当前 M7 构建产物：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc/debug/robobase_m7_rpmsg_tty_echo.elf
```

到目标系统：

```text
/lib/firmware/robobase_m7_rpmsg_tty_echo.elf
```

注意：该 ELF 是 Cortex-M7 固件，不是 A53 Linux 用户态程序，因此 recipe 关闭了
strip/debug split，并跳过架构 QA。

新增服务包：

```text
recipes-robobase/robobase-m7-services/robobase-m7-services_0.1.bb
```

它安装：

```text
/usr/bin/robobase-m7-start
/usr/bin/robobase-m7-stop
/usr/bin/robobase-rpmsg-tty-setup
/etc/default/robobase-m7
/lib/systemd/system/robobase-m7.service
/lib/systemd/system/robobase-rpmsg-tty.service
```

并声明：

```bitbake
RDEPENDS_${PN} += "kmod robobase-m7-firmware"
SYSTEMD_AUTO_ENABLE_${PN} = "enable"
```

因此安装服务包会带上固件包，生成镜像后两个 systemd 服务默认 enable。

`robobase-image` 已显式安装：

```bitbake
robobase-m7-firmware robobase-m7-services
```

## 开机链路

```text
Linux systemd
  -> robobase-m7.service
     -> /usr/bin/robobase-m7-start
        -> 自动寻找 /sys/class/remoteproc/remoteproc*
        -> 写 firmware
        -> 写 state=start
        -> 等待 state=running/attached
  -> robobase-rpmsg-tty.service
     -> /usr/bin/robobase-rpmsg-tty-setup
        -> modprobe imx_rpmsg_tty
        -> 等待 /dev/ttyRPMSG*
```

`robobase-m7-start` 不写死 `remoteproc0`。它会读取每个 remoteproc 的 `name`，
优先匹配 `cm7`、`m7`、`m4`、`imx-rproc`，以适配不同内核枚举顺序。

默认配置在：

```text
/etc/default/robobase-m7
```

可覆盖：

```text
ROBOBASE_M7_FIRMWARE=robobase_m7_rpmsg_tty_echo.elf
ROBOBASE_M7_REMOTEPROC=
ROBOBASE_M7_START_TIMEOUT=10
ROBOBASE_RPMSG_TTY_GLOB=/dev/ttyRPMSG*
ROBOBASE_RPMSG_TTY_TIMEOUT=20
```

## 构建

先构建 M7 固件：

```sh
cd /home/compile/workstation/project/codex/myplatform/third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc
ARMGCC_DIR=/home/compile/workstation/project/codex/myplatform/third_party/m7/gcc-arm-none-eabi-7-2017-q4-major ./build_debug.sh
```

再构建 Yocto 包或镜像：

```sh
cd /home/compile/workstation/project/codex/myplatform/third_party/yocto/yocto_5.10.72
source setup-environment ../../../build/out/myir_imx8m_plus/xwayland/yocto

bitbake robobase-m7-firmware
bitbake robobase-m7-services
bitbake robobase-image
```

## 验证

板上检查固件：

```sh
ls -lh /lib/firmware/robobase_m7_rpmsg_tty_echo.elf
```

检查 systemd：

```sh
systemctl status robobase-m7.service
systemctl status robobase-rpmsg-tty.service
systemctl is-enabled robobase-m7.service
systemctl is-enabled robobase-rpmsg-tty.service
```

检查 remoteproc 和 RPMsg TTY：

```sh
cat /sys/class/remoteproc/remoteproc*/name
cat /sys/class/remoteproc/remoteproc*/state
ls /dev/ttyRPMSG*
```

检查 safety 协议：

```sh
robobase-rpmsg-test --query-status -d /dev/ttyRPMSG30
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 -n 3
```

## 已验证结论

截至 2026-05-14：

- `bitbake robobase-m7-firmware` 成功。
- `bitbake robobase-m7-services -n` 成功。
- `robobase-image` 烧录后，板上已验证自动加载链路 OK。
- `/lib/firmware/robobase_m7_rpmsg_tty_echo.elf` 能被安装进系统。
- systemd 能启动 M7 remoteproc，并加载 RPMsg TTY 设备。

## 当前边界

- `robobase-m7-firmware` 当前打包的是预编译 M7 ELF。构建 Yocto 镜像前，需要先
  运行 M7 `build_debug.sh`，确保 ELF 是最新的。
- 后续可以把 M7 编译过程进一步纳入 Yocto task，但这会引入 ARMGCC 工具链路径、
  MCUXpresso SDK 构建系统和 Yocto 任务依赖的额外复杂度。
