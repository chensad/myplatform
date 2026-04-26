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

## MYIR i.MX8MP Yocto

`myir_imx8m_plus` 当前已经验证可在 Docker 里的 `Ubuntu 18.04` 环境完成
`myir-image-full` 构建。推荐直接走容器，不要再用宿主机 `Ubuntu 24.04`
直接编这套旧 Yocto。

首次准备：

```bash
git submodule update --init --recursive
cd /home/compile/workstation/project/codex/myplatform
./platform/boards/myir_imx8m_plus/env/build-image.sh
```

如果已经有导出的环境包，也可以直接恢复：

```bash
cd /home/compile/workstation/project/codex/myplatform
./platform/boards/myir_imx8m_plus/env/load-image.sh
```

进入容器：

```bash
./platform/boards/myir_imx8m_plus/scripts/enter-env.sh --docker
```

直接编完整 Yocto 镜像：

```bash
./platform/boards/myir_imx8m_plus/env/run-yocto.sh
```

或者进入容器后继续统一入口：

```bash
make BOARD=myir_imx8m_plus yocto
```

当前验证通过的产物目录：

```bash
build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
```

常用镜像文件：

- `myir-image-full-myd-jx8mp.ext4`
- `myir-image-full-myd-jx8mp.wic.bz2`
- `myir-image-full-myd-jx8mp.tar.bz2`
- `imx-boot`
- `Image-myd-jx8mp.bin`
- `myd-jx8mp-base.dtb`

补充说明见：

- `platform/boards/myir_imx8m_plus/env/README.md`
- `docs/yocto_myir_imx8mp_guide.md`

### 自定义 RoboBase Yocto Layer

当前已经增加自定义 layer：

```bash
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase
```

该 layer 目前包含：

- `robobase-image`：基于 MYIR `myir-image-full` 的自定义镜像
- `test-yocto`：用于验证自定义 recipe 和镜像安装链路的用户态测试程序

进入 Yocto 构建环境后，先确认 layer 已加入：

```bash
bitbake-layers show-layers | grep meta-robobase
```

单独构建测试程序：

```bash
bitbake test-yocto
```

构建自定义镜像：

```bash
bitbake robobase-image
```

构建成功后，产物位于：

```bash
build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
```

常用自定义镜像文件：

- `robobase-image-myd-jx8mp.wic.bz2`
- `robobase-image-myd-jx8mp.wic`
- `robobase-image-myd-jx8mp.ext4`
- `robobase-image-myd-jx8mp.manifest`

烧录前建议先确认 `test-yocto` 已进入镜像：

```bash
grep test-yocto build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp/robobase-image-myd-jx8mp.manifest
```
