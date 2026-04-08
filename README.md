# myplatform

`myplatform` 是新的平台仓库根目录。

这里承接三类长期维护内容：

- 平台源码组织和板级资产
- 第三方源码入口和版本锁定
- 统一编译、环境初始化、产物对比脚本

目录分工：

- `apps/` 放用户态应用和公共库
- `platform/` 放板卡、机型配置、清单和公共平台逻辑
- `third_party/` 放 Buildroot、Linux、U-Boot 等外部源码入口
- `build/` 放本地构建工作区
- `tools/` 放初始化、同步、打包、对比等通用脚本
- `docs/` 放架构、板卡、发布相关文档

快速开始：

```bash
git submodule update --init --recursive
./tools/bootstrap.sh imx6ull_100ask_pro
./tools/fetch.sh
make BOARD=imx6ull_100ask_pro buildroot
```

兼容入口仍保留：

```bash
./build/build.sh imx6ull_100ask_pro buildroot
```

详细使用说明见 `README_PLATFORM.md`。
