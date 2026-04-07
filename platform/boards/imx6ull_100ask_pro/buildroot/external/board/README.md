# external board

这里预留给 `BR2_EXTERNAL` 使用的 board 资源。

后续建议把真正稳定下来的：

- rootfs overlay
- post-build / post-image
- genimage 相关文件

逐步从过渡态的 `buildroot/board/` 迁到这里。
