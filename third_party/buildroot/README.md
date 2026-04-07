# third_party buildroot

这里挂载 Buildroot 主源码子模块。

实际源码在：

- `buildroot-2020.02/`

板级定制不要直接改这个目录，优先通过 `BR2_EXTERNAL` 和板级配置实现。
