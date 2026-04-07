# imx6ull_100ask_pro Mapping

这个目录现在不是纯占位了，已经开始承接旧 `100ask_imx6ull-sdk` 里的板级配置。

当前映射策略：

- 保留旧 SDK 不动
- 在这里复制一份当前这块板真正使用到的 kernel / Buildroot / U-Boot 配置
- 每次迁移都保留来源关系，避免后续失去追溯

## Legacy To New Mapping

### Kernel

- 旧：
  `100ask_imx6ull-sdk/Linux-4.9.88/arch/arm/configs/100ask_imx6ull_defconfig`
- 新：
  `myplatform/platform/boards/imx6ull_100ask_pro/linux/defconfig`

### U-Boot

- 旧：
  `100ask_imx6ull-sdk/Uboot-2017.03/configs/mx6ull_14x14_evk_defconfig`
- 新：
  `myplatform/platform/boards/imx6ull_100ask_pro/uboot/defconfig`

说明：

- Buildroot 旧配置里使用 `BR2_TARGET_UBOOT_BOARDNAME="mx6ull_14x14_evk"`
- 因此当前先映射到这一份 U-Boot defconfig

### Buildroot Main Defconfig

- 旧：
  `100ask_imx6ull-sdk/Buildroot_2020.02.x/configs/100ask_imx6ull_pro_ddr512m_systemV_core_defconfig`
- 新：
  `myplatform/platform/boards/imx6ull_100ask_pro/buildroot/defconfig`

### Buildroot Included Config Fragments

- `100ask_imx6ull_Kernel.config`
- `100ask_imx6ull_Bootloaders.config`
- `systemV_core.config`
- `Core_systemFilesystem.config`
- `Hostutilities.config`

都已映射到：

- `myplatform/platform/boards/imx6ull_100ask_pro/buildroot/configs/`

### Buildroot Board Resources

- 旧：
  `100ask_imx6ull-sdk/Buildroot_2020.02.x/board/100ask/nxp-imx6ull/genimage.cfg`
- 新：
  `myplatform/platform/boards/imx6ull_100ask_pro/buildroot/board/genimage.cfg`

- 旧：
  `100ask_imx6ull-sdk/Buildroot_2020.02.x/board/100ask/nxp-imx6ull/local.mk`
- 新：
  `myplatform/platform/boards/imx6ull_100ask_pro/buildroot/board/local.mk`

- 旧：
  `100ask_imx6ull-sdk/Buildroot_2020.02.x/board/100ask/nxp-imx6ull/patches/`
- 新：
  `myplatform/platform/boards/imx6ull_100ask_pro/buildroot/board/patches/`

- 旧：
  `100ask_imx6ull-sdk/Buildroot_2020.02.x/board/100ask/nxp-imx6ull/rootfs-overlay/`
- 新：
  `myplatform/platform/boards/imx6ull_100ask_pro/buildroot/board/rootfs-overlay/`

## What Has Been Localized

为了让这份映射不只是“拷贝过来”，已经做了两类本地化调整：

1. `buildroot/defconfig` 里的 include 改成了本地 `configs/...`
2. Buildroot 里原本指向 `board/100ask/nxp-imx6ull/...` 的路径，改成了本地 `board/...`

也就是说，这份 `myplatform` 里的 Buildroot 配置已经在目录关系上脱离了旧 SDK 的板级路径。

## What Is Still Legacy-Backed

当前仍然没有完成的是：

- 没有切到 `third_party/buildroot + BR2_EXTERNAL`
- 没有把 U-Boot 板级代码从旧 SDK 抽离
- 没有把 kernel DTS / patch 体系完整抽成 `myplatform` 主导

所以现在这一步更准确地说是：

- 已完成配置映射
- 尚未完成构建主导权迁移

## Recommended Next Migration Steps

下一步建议按这个顺序继续：

1. 把 `buildroot/board/` 下真正需要的 overlay / local.mk / patch 再整理成“当前产品必需”和“历史杂项”
2. 明确 `imx6ull_100ask_pro` 当前最终使用的是哪一份 U-Boot 变体，如果不是基础 `mx6ull_14x14_evk_defconfig`，补 fragment 或专用 defconfig
3. 给 `myplatform/tools/build.sh` 增加从 `myplatform/platform/boards/imx6ull_100ask_pro/buildroot/defconfig` 发起构建的路径
4. 第二阶段再切 `BR2_EXTERNAL`
