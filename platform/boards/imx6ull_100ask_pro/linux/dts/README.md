# dts

这里放 `imx6ull_100ask_pro` 的板级设备树真源。

约束：

- 不直接在 `third_party/linux/.../arch/arm/boot/dts/` 里长期维护板级 DTS
- 板级 DTS 真源统一放在 `platform/boards/imx6ull_100ask_pro/linux/dts/`
- 编译前由根目录 `Makefile` 根据 `model.mk` 的 `MODEL_KERNEL_DTS_*` 配置生成 `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH`
- Buildroot 在 Linux 构建时会把这里的 `.dts/.dtsi` 复制到内核构建目录，并生成对应 `.dtb`

当前主 DTS：

- `100ask_imx6ull-14x14.dts`

如果后续需要拆分板级 `.dtsi` 或新增同板不同型 DTS，也统一放在这个目录，并把文件名追加到 `MODEL_KERNEL_CUSTOM_DTS_FILES`。
