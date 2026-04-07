# Buildroot Board Cleanup

这个目录承接的是旧 `100ask_imx6ull-sdk/Buildroot_2020.02.x/board/100ask/nxp-imx6ull/`
里的板级资源，但已经开始按“当前必需”和“历史遗留”做拆分。

## Current Required

### `genimage.cfg`

当前镜像装配仍然使用它。

### `patches/linux/0001-scripts-dtc-pass-fcommon-for-yylloc-with-newer-gcc.patch`

这是当前 host / toolchain 环境下继续编旧内核所需的兼容 patch。

### `rootfs-overlay/current-systemV/`

这是当前 `100ask_imx6ull_pro_ddr512m_systemV_core_defconfig` 主线实际引用的 overlay。

它保留的内容主要是：

- `etc/init.d/` 下的 systemV 启动脚本
- 网络、ssh、samba、pulse、bluetooth、swupdate 等运行时配置
- `fw_env.config`、`fstab`、`hwrevision` 等板级系统文件
- `lib/firmware/rtl_bt/` 蓝牙固件
- `usr/bin/rs485_read`

## Legacy / Not In Current Mainline Path

### `rootfs-overlay/legacy-systemD/`

旧 SDK 的 systemD 变体资源。

当前主线 defconfig 走的是 `systemV_core`，因此这部分不再进入默认 overlay。

### `rootfs-overlay/legacy-misc/`

只保留了一个历史测试文件：

- `test.txt`

这类文件不应该再进入当前镜像。

### `rootfs-overlay/legacy-demo-lvgl/`

这是 100ask 的 LVGL 演示程序和配套素材，包含：

- `etc/init.d/S05lvgl`
- `usr/share/lvgl/lvgl_100ask_demo`
- 大量图片和字体资源

这部分体积较大，而且更接近“演示内容”而不是“板级系统必需项”。
因此已从当前默认 overlay 剥离。

如果以后你明确要保留这个 demo，再显式把它作为产品 overlay 重新引入，而不是默认绑在板级 BSP 上。

## local.mk Classification

`local.mk` 当前全部归类为：

- 当前 host 兼容所需

它做的事情包括：

- 修 `host-m4`
- 修 `host-fakeroot`
- 禁掉 `host-libglib2` 的 `libelf` 探测
- 给 `host-gdb` 加 `--disable-sim`

这些都不是目标板功能本身，而是“旧 Buildroot 在新宿主机上继续能编”的修补。

## Recommended Rule Going Forward

后续继续整理时，建议用这个标准：

1. 板子启动和基础系统运行必需：留在 `current-systemV/`
2. 只是某个 demo / UI / 课程示例：移到 `legacy-*` 或产品 overlay
3. 只为旧宿主兼容服务的构建修补：留在 `local.mk`，但明确标注为 host workaround
