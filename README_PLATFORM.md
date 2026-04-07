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
./myplatform/tools/build.sh <board> <product> [component]
```

当前已放的示例：

```bash
./myplatform/tools/build.sh imx6ull_100ask_pro demo_console all
./myplatform/tools/build.sh imx6ull_100ask_pro demo_console app:app_demo
./myplatform/tools/build.sh imx6ull_100ask_pro demo_console linux
./myplatform/tools/build.sh imx6ull_100ask_pro demo_console uboot
./myplatform/tools/build.sh imx6ull_100ask_pro demo_console buildroot
```

说明：

- 现在的脚本是“统一入口骨架”
- 当前 `imx6ull_100ask_pro` 默认桥接到旧 `100ask_imx6ull-sdk`
- 后面迁移到 `third_party + BR2_EXTERNAL` 时，入口不变，只换脚本内部实现

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

下一步最值得继续做的是：

1. 把 `imx6ull_100ask_pro` 的现有 kernel / uboot / buildroot 关键配置逐步搬到 `myplatform/platform/boards/imx6ull_100ask_pro/`
2. 给 `app_demo` 做一个真正可被 Buildroot 打包的外部 package 接入
3. 把 `tools/fetch.sh` 做成能把第三方源码拉进 `third_party/` 的脚本
4. 第二阶段再切 `BR2_EXTERNAL`
