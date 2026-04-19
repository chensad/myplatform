# MYIR i.MX8MP Yocto Guide

这份文档结合当前 `myplatform/` 的 `myir_imx8m_plus` 板级接入和
`Imx8mp/` 资料目录，说明 Yocto 在这块板上如何构建系统，以及后续怎么定义
自己的层和板级配置。

## 当前板级事实

- 参考资料来自 `Imx8mp/Linux 5.10.9 Distribution V2.0.0`
- 官方 BSP 基于 `Yocto 3.2.1`
- 内核版本是 `Linux 5.10.9`
- 当前平台板级目录是：
  - `platform/boards/myir_imx8m_plus/`
- 当前平台调度入口是：
  - `platform/common/mk/backend-yocto.mk`

当前目标板运行 `free -h` 输出约 `2.9Gi` 可用内存，可判断为 `3G DDR` 版本。
因此当前板级配置显式选择：

```conf
UBOOT_CONFIG = "sd"
UBOOT_CONFIG[sd] = "myd_jx8mp_defconfig,sdcard"
```

该配置通过板级 `local.conf` 片段注入，而不是直接改第三方 vendor 默认值。

## Yocto 构建的基本概念

Yocto 不是单一源码树，也不是单独的 rootfs 生成工具。它本质上是：

- 用多个 layer 组织构建规则
- 用 recipe 描述每个软件包怎么获取、配置、编译、安装
- 用 machine 描述板级硬件
- 用 distro 描述发行版策略
- 用 image recipe 描述最终 rootfs 要包含哪些包
- 用 bitbake 解析依赖并执行整套任务流

在这块板上，关键三元组是：

- `MACHINE=myd-jx8mp`
- `DISTRO=fsl-imx-xwayland`
- `IMAGE=myir-image-full`

## MYIR i.MX8MP 的实际构建流程

官方推荐先初始化构建环境：

```bash
EULA=1 DISTRO=fsl-imx-xwayland MACHINE=myd-jx8mp \
source sources/meta-myir/tools/myir-setup-release.sh -b build-xwayland
```

这一步会：

- 选择板级 machine
- 选择 distro
- 创建构建目录，例如 `build-xwayland`
- 生成 `conf/local.conf` 和 `conf/bblayers.conf`

然后执行：

```bash
bitbake myir-image-full
```

这一步不是直接“编 rootfs 文件”，而是让 bitbake 递归构建 image 所依赖的全部
组件。

## BitBake 是怎么一步步构建文件系统的

以 `bitbake myir-image-full` 为例，典型流程是：

1. `do_fetch`
   拉取源码、补丁、归档包
2. `do_unpack`
   解压源码
3. `do_patch`
   应用补丁
4. `do_configure`
   配置源码
5. `do_compile`
   编译
6. `do_install`
   安装到临时目标目录
7. `do_package`
   生成包元数据
8. `do_rootfs`
   根据 image recipe 选择包并组装 rootfs
9. `do_image`
   生成 ext4、tar、wic 等镜像
10. `do_deploy`
   输出 Image、dtb、imx-boot、sdk 等产物

所以 Yocto 构建文件系统的本质是：

- 先构建包
- 再由 image recipe 决定 rootfs 内容
- 再由镜像类型导出为目标镜像格式

对当前板子，构建产物通常位于：

```bash
build-xwayland/tmp/deploy/images/myd-jx8mp
```

## Layer、Machine、Distro、Image 的关系

### Layer

Layer 是一组 recipe、配置、补丁和扩展规则的集合。常见职责包括：

- 基础构建能力
- SoC/BSP 支持
- 板级 machine 配置
- 自定义 image
- 应用和库的 recipe

### Machine

`machine` 描述具体板卡硬件，例如：

- 用哪套 U-Boot 配置
- 用哪个内核设备树
- 板级功能开关
- 启动链相关配置

当前板子使用：

```bash
MACHINE=myd-jx8mp
```

### Distro

`distro` 描述系统策略，例如：

- 图形栈
- 默认软件包策略
- 一些全局 feature

当前板子使用：

```bash
DISTRO=fsl-imx-xwayland
```

### Image

`image` 决定最终 rootfs 装哪些包，以及导出什么镜像。

当前常用镜像是：

```bash
bitbake myir-image-full
```

一句话概括：

- `machine` 决定硬件
- `distro` 决定系统策略
- `image` 决定最终系统内容

## 当前 myplatform 是怎么调度 Yocto 的

当前 `myplatform` 不是直接替代 vendor layer，而是在外层统一调度 Yocto。

关键入口：

- `platform/boards/myir_imx8m_plus/model.mk`
- `platform/common/mk/backend-yocto.mk`

当前做法是：

- 在平台层定义 `MODEL_YOCTO_MACHINE`、`MODEL_YOCTO_DISTRO`、镜像目标
- 由 backend 创建构建目录
- 执行 `myir-setup-release.sh`
- 写入 `conf/local.conf`
- 调用 `bitbake`

这是一种“平台层统一入口 + 第三方 Yocto 原始层保留”的接法，适合当前阶段。

## 为什么板级 DDR 选择不要直接写死在第三方源码里

MYIR 文档明确支持三种 DDR U-Boot 配置：

- `myd_jx8mp_2g_defconfig`
- `myd_jx8mp_defconfig`，对应 `3G DDR`
- `myd_jx8mp_4g_defconfig`

vendor 的 `myd-jx8mp.conf` 可能随着版本不同默认成 `2G`、`3G` 或 `4G`。但这不一定
匹配你手上的实体板。

因此更稳的做法是：

- vendor 层保持尽量少改
- 在平台自己的板级层显式覆盖 DDR 选择
- 当前已经通过 `platform/boards/myir_imx8m_plus/yocto/local.conf.fragment`
  实现对 `3G DDR` 的覆盖

## 怎么定义你自己的层

如果后续要把 MYIR BSP 适配到你自己的底板，不建议直接把 vendor 层所有内容复制一遍。
更合理的做法是新增自己的 layer，例如：

```text
meta-mycompany/
  conf/
    layer.conf
    machine/
      myboard.conf
  recipes-bsp/
    u-boot/
    imx-boot/
  recipes-kernel/
    linux/
  recipes-core/
    images/
      mycompany-image.bb
```

至少需要三类东西：

1. `conf/layer.conf`
   声明 layer 自己的搜索路径和优先级
2. `conf/machine/<your-board>.conf`
   定义你的板子
3. `recipes-core/images/*.bb`
   定义你自己的镜像

## 建议的定制顺序

对当前项目，更推荐按下面顺序推进：

1. 先复用 vendor 的 `myd-jx8mp`
2. 先把 DDR、下载目录、sstate、镜像目标等板级差异放到平台层覆盖
3. 再根据硬件差异修改设备树
4. 如果 U-Boot 差异明显，再派生自己的 U-Boot defconfig
5. 当差异足够多时，再新建自己的 `machine.conf`

## 后续最可能改的地方

实际做板级适配时，常见落点通常是：

- `conf/machine/<your-board>.conf`
- `recipes-bsp/u-boot/*.bbappend`
- `recipes-kernel/linux/*.bbappend`
- kernel 设备树
- `recipes-core/images/*.bb`
- `IMAGE_INSTALL:append`

## 当前项目的建议

对于 `myplatform` 当前阶段，建议保持下面原则：

- `third_party/yocto/` 作为第三方参考源
- `platform/boards/myir_imx8m_plus/` 作为平台侧板级配置入口
- 不在第三方源码里堆长期业务逻辑
- 优先通过板级 `local.conf` 片段、后续自定义 layer、设备树和 `.bbappend`
  管理差异
