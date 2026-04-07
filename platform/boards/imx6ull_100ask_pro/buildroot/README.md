# buildroot

这里放这块板对应的 Buildroot 资产。

内容包括：

- `defconfig` 板级 Buildroot 主配置
- `configs/` 被主配置合并进来的配置片段
- `board/` overlay、patch、genimage、local.mk
- `external/` `BR2_EXTERNAL` 外部层

当前编译链中，Buildroot 会读取这里的主配置，并通过脚本合并配置片段，再使用本地 `third_party` 里的 Linux 和 U-Boot 源码。
