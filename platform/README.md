# platform

这里是平台层真源目录。

主要内容：

- `boards/` 板卡级资产
- `products/` 产品组合与装配策略
- `common/` 多板共用脚本和模板
- `manifests/` 板卡、产品、第三方版本清单

原则：

- 板级问题优先落在 `boards/`
- 多板共享逻辑优先上收 `common/`
- 不把第三方源码直接塞进这里
