# Platform Workspace Guide

本目录是按 `PLATFORM_ARCH_DRAFT.md` 落下来的第一版平台骨架。

当前策略：

- 保留现有 `100ask_imx6ull-sdk/` 作为历史兼容层
- 新架构目录用于承接后续 app、驱动、板级配置和统一编译入口
- 第一阶段先统一目录、入口和约束，不直接替换旧 SDK

## Directory Overview

```text
myplatform/
  apps/
  platform/
  third_party/
  build/
  tools/
  docs/
```

## Quick Start

新机器建议按这个顺序开始：

```bash
cd /path/to
git clone <your-myplatform-repo>
cd myplatform
git submodule update --init --recursive
./tools/bootstrap.sh imx6ull_100ask_pro
./build/build.sh imx6ull_100ask_pro demo_console app:app_demo
./build/build.sh imx6ull_100ask_pro demo_console buildroot
```

如果要用容器环境，参考：

- `myplatform/platform/boards/imx6ull_100ask_pro/env/README.md`

## How To Modify App

公共 app 放在：

- `myplatform/apps/public/<app_name>/`

私有 app 放在：

- `myplatform/apps/private/<app_name>/`

一个标准 app 推荐至少包含：

- `src/`
- `include/`
- `CMakeLists.txt`
- `package/buildroot/`

示例可参考：

- `myplatform/apps/public/app_demo/`

如果你要新增一个 C/C++ app，建议直接仿照 `app_demo`：

1. 复制目录结构
2. 修改 `src/` 和 `include/`
3. 修改 `CMakeLists.txt`
4. 修改 `package/buildroot/Config.in`
5. 修改 `package/buildroot/<app>.mk`
6. 在产品清单里把它加入对应产品

## How To Modify Drivers

板级驱动放在：

- `myplatform/platform/boards/<board>/drivers/`

其中分三类：

- `drivers/patches/`
  放需要打进内核源码树的补丁
- `drivers/out-of-tree/`
  放独立内核模块源码
- `drivers/dkms/`
  预留给需要宿主侧独立管理的模块

当前建议：

- 改内核内驱动：优先放 patch 到 `drivers/patches/`
- 新增独立模块：放 `drivers/out-of-tree/`
- 用户态适配：放 `apps/public/libs/libhal/` 或私有库目录

如果是多板可复用的驱动，优先放：

- `myplatform/platform/common/drivers/`

## How To Modify Board BSP

以 `imx6ull_100ask_pro` 为例：

- 内核相关：`platform/boards/imx6ull_100ask_pro/linux/`
- U-Boot 相关：`platform/boards/imx6ull_100ask_pro/uboot/`
- Buildroot 外部层：`platform/boards/imx6ull_100ask_pro/buildroot/external/`
- 板级环境：`platform/boards/imx6ull_100ask_pro/env/`
- 板级脚本：`platform/boards/imx6ull_100ask_pro/scripts/`

这些路径在仓库里的完整前缀是：

- `myplatform/platform/boards/imx6ull_100ask_pro/...`

推荐约束：

- 内核 defconfig / fragment 只放板级内容
- U-Boot defconfig / fragment 只放启动链内容
- rootfs overlay、post-build、post-image 放在 buildroot 目录
- 不再把自己的长期逻辑直接散落到旧 SDK 根目录

## How To Build

统一入口：

```bash
./myplatform/build/build.sh <board> <product> [component]
```

当前已放的示例：

```bash
./myplatform/build/build.sh imx6ull_100ask_pro demo_console all
./myplatform/build/build.sh imx6ull_100ask_pro demo_console app:app_demo
./myplatform/build/build.sh imx6ull_100ask_pro demo_console linux
./myplatform/build/build.sh imx6ull_100ask_pro demo_console uboot
./myplatform/build/build.sh imx6ull_100ask_pro demo_console buildroot
```

说明：

- 主入口已经切到 `myplatform/build/build.sh`
- `myplatform/tools/build.sh` 只是兼容转发
- 当前 `imx6ull_100ask_pro` 会优先使用 `third_party/buildroot/buildroot-2020.02`、`third_party/linux/imx-linux4.9.88`、`third_party/uboot/imx-uboot2017.03`
- 如果 `third_party` 对应源码不存在，会自动回退到旧 `100ask_imx6ull-sdk`
- Buildroot 通过 `BR2_EXTERNAL` 挂接板级外部层，并通过 `*_OVERRIDE_SRCDIR` 指向本地 `third_party` 源码

## Environment Setup

推荐先跑：

```bash
./tools/bootstrap.sh imx6ull_100ask_pro
```

它会检查：

- `git`
- `make`
- `gcc`
- `g++`
- `rsync`
- `python3`
- `sed`
- `awk`

并预创建：

- `build/out`
- `build/downloads`
- `build/ccache`
- `build/logs`

第三方源码同步入口：

```bash
./tools/fetch.sh
```

它现在会同步 git 子模块，而不是再从旧 SDK 拷源码。

## Current Source Of Truth

当前建议优先维护这几个文件：

- `myplatform/platform/manifests/boards.yml`
- `myplatform/platform/manifests/products.yml`
- `myplatform/platform/manifests/sources.lock`

它们分别描述：

- 板卡清单
- 产品清单
- 第三方源码版本锁定

## Migration Rule

现阶段请按下面规则工作：

1. 旧 SDK 继续保留，不删不重命名
2. 新 app、新驱动、新板级逻辑优先落到新骨架
3. 编译入口统一从 `myplatform/tools/build.sh` 进入
4. 旧 SDK 只作为兼容构建实现和历史参考

## Recommended Next Steps

当前最值得继续做的是：

1. 继续把 `buildroot/board` 和 `buildroot/configs` 迁到 `buildroot/external/`
2. 明确 `demo_console` 产品层的 rootfs 装配规则
3. 补 `drivers/out-of-tree` 的标准构建模板
4. 给 `env/` 增加更完整的宿主依赖锁定
