# external package

这里放这块板通过 `BR2_EXTERNAL` 注入的自定义包。

一个标准自定义包通常包含：

- `Config.in`
- `<pkg>.mk`
- 需要时附带 patch、脚本或安装规则
