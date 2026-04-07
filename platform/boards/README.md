# boards

这里按板卡组织 BSP 资产。

每块板目录建议至少包含：

- `board.env`
- `scripts/`
- `linux/`
- `uboot/`
- `buildroot/`
- `drivers/`
- `env/`

后续扩板时，优先复用 `platform/common/` 的通用能力，不要直接复制整套脚本。
