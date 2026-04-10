# Build Guide

这份文档只讲日常编译怎么用，不讨论架构草案。

## Prerequisites

第一次使用建议先执行：

```bash
cd /path/to/myplatform
git submodule update --init --recursive
./tools/bootstrap.sh imx6ull_100ask_pro
./tools/fetch.sh
```

如果要用 Docker 环境，先看：

- `platform/boards/imx6ull_100ask_pro/env/README.md`

## Main Entry

当前统一入口是仓库根目录 `Makefile`：

```bash
make BOARD=<board> [target]
```

`imx6ull_100ask_pro` 常用命令：

```bash
make BOARD=imx6ull_100ask_pro vars
make BOARD=imx6ull_100ask_pro app APP=app_demo
make BOARD=imx6ull_100ask_pro linux
make BOARD=imx6ull_100ask_pro uboot
make BOARD=imx6ull_100ask_pro busybox
make BOARD=imx6ull_100ask_pro buildroot
```

兼容入口仍保留，但只是转发到 `make`：

```bash
./build/build.sh imx6ull_100ask_pro app:app_demo
./build/build.sh imx6ull_100ask_pro linux
./build/build.sh imx6ull_100ask_pro uboot
./build/build.sh imx6ull_100ask_pro busybox
./build/build.sh imx6ull_100ask_pro buildroot
```

## What Each Target Does

`vars`

- 打印当前板级和机型配置解析结果
- 用来确认 third_party 路径、输出目录、app 宏是否正确

`app`

- 只编一个用户态 app
- 会把 `model.mk` 中的 `MODEL_APP_CPPFLAGS` 传给 app 的 Makefile

`linux`

- 通过 Buildroot 输出树重编 Linux
- 产物仍放在 Buildroot 的 `images/` 目录

`uboot`

- 通过 Buildroot 输出树重编 U-Boot
- 产物仍放在 Buildroot 的 `images/` 目录

`busybox`

- 通过 Buildroot 输出树执行 `busybox-rebuild`
- 适合在已有输出树上单独重编 BusyBox，而不触发整套镜像全量重建

`buildroot`

- 完整执行 Buildroot
- 会准备输出目录、生成 `merged_defconfig`、调用 Buildroot 完整构建镜像

## Output Paths

当前 `imx6ull_100ask_pro` 默认输出标签是 `demo_console`，所以输出根目录是：

- `build/out/imx6ull_100ask_pro/demo_console/`

Buildroot 输出目录：

- `build/out/imx6ull_100ask_pro/demo_console/buildroot/`

完整镜像和内核产物：

- `build/out/imx6ull_100ask_pro/demo_console/buildroot/images/`

常见文件：

- `zImage`
- `*.dtb`
- `u-boot-dtb.imx`
- `rootfs.ext2`
- `rootfs.tar`
- `100ask-imx6ull-pro-512d-systemv-v1.img`

如果只编 app，以 `app_demo` 为例，当前产物在 app 自己目录下：

- `apps/public/app_demo/app_demo`

当前还没有把单独编 app 的产物统一收口到 `build/out/`。

## Config Source

当前构建依赖两份核心配置：

- `platform/boards/<board>/board.mk`
- `platform/boards/<board>/model.mk`

职责区分：

`board.mk`

- 板级路径
- 默认输出目录
- Buildroot board/external/defconfig 路径
- legacy SDK 回退路径

`model.mk`

- third_party 源码选择
- 机型功能开关
- app 宏定义
- 追加 Buildroot 配置片段

如果要改机型宏、切换 third_party 源码、控制 app 编译宏，优先改 `model.mk`。

## Rebuild And Clean

当前还没有统一的 `make clean` 目标，所以重编要按对象分别处理。

只清 app：

```bash
make -C apps/public/app_demo clean
make BOARD=imx6ull_100ask_pro app APP=app_demo
```

彻底清 Buildroot 输出树：

```bash
rm -rf build/out/imx6ull_100ask_pro/demo_console/buildroot
make BOARD=imx6ull_100ask_pro buildroot
```

如果只是想重编 Linux 或 U-Boot：

```bash
make BOARD=imx6ull_100ask_pro linux
make BOARD=imx6ull_100ask_pro uboot
```

这两个目标默认是基于现有 Buildroot 输出树做重编，不会自动先清空。

如果只是想单独重编 BusyBox：

```bash
make BOARD=imx6ull_100ask_pro busybox
```

它同样基于现有 Buildroot 输出树执行，不会自动先清空。

## Current Notes

- `make` 是主入口，shell 脚本是兼容层
- `linux` 和 `uboot` 当前仍通过 Buildroot 输出树构建，不是单独裸编
- `busybox` 当前通过 Buildroot 输出树执行 `busybox-rebuild`
- 机型功能宏当前已经接到 app 编译和 Buildroot 额外配置片段
- 后续还会继续把 `MODEL_FEATURE_*` 接到 Buildroot fragment、overlay 和驱动选择
