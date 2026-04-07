# tools

这里放仓库级通用脚本。

当前关键脚本：

- `bootstrap.sh` 宿主环境检查
- `fetch.sh` 同步第三方子模块
- `build.sh` 兼容入口，转发到 `build/build.sh`
- `compare-sdk-artifacts.sh` 对比 SDK 与 `myplatform` 产物

原则：

- 仓库级通用脚本放这里
- 强板级耦合脚本放对应 `platform/boards/<board>/scripts/`
