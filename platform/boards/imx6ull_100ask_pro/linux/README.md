# linux

这里放内核相关板级资产。

包含：

- `defconfig`
- `dts/`
- `fragments/`
- `patches/`

来源是旧 SDK 的 Linux 4.9.88 配置和定制补丁，但现在由 `myplatform` 板级脚本统一调度。

约定：

- 板级 DTS 真源放在 `linux/dts/`
- 编译前由根目录 `Makefile` 生成 Buildroot 的 `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH`
- Buildroot 在 Linux 构建阶段把这些板级 `.dts/.dtsi` 复制到内核构建目录
- `model.mk` 负责声明主 DTS 名称、保留的内核树内 DTS 名称和自定义 DTS 文件列表
