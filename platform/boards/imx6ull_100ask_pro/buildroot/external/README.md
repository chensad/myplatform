# buildroot external

这里是这块板的 `BR2_EXTERNAL` 层。

长期目标：

- 自定义包尽量都从这里挂进 Buildroot
- 板级 board 资源最终也优先收敛到这里
- 保持 `third_party/buildroot` 主树尽量原始

当前已接入：

- 示例 app 包接入
- `Config.in`
- `external.mk`
