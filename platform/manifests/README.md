# manifests

这里放平台真源清单。

当前关键文件：

- `boards.yml` 板卡清单
- `products.yml` 产品清单
- `sources.lock` 第三方源码版本锁定

修改原则：

- 新增板卡先改 `boards.yml`
- 新增产品先改 `products.yml`
- 变更 submodule 对应版本后更新 `sources.lock`
