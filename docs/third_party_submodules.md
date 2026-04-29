# Third-Party Submodules

这份说明只覆盖 `myplatform/` 仓库。

## 目标

把下面这些第三方源码目录收成 git 子仓库：

- `myplatform/third_party/buildroot/buildroot-2020.02`
- `myplatform/third_party/linux/imx-linux4.9.88`
- `myplatform/third_party/uboot/imx-uboot2017.03`
- `myplatform/third_party/yocto/yocto_5.10.72`
- `myplatform/third_party/m7`

`toolchain` 不建议做成子仓库，原因：

- 当前 `imx6ull_100ask_pro` 的 Buildroot 配置使用的是 `BR2_TOOLCHAIN_BUILDROOT=y`
- 也就是工具链由 Buildroot 自己生成，不依赖单独维护的预编译工具链仓库
- 二进制工具链作为子仓库通常又大又难维护

## 一次性迁移步骤

先删除占位目录里的空内容，只保留目录本身：

```bash
cd /home/compile/workstation/project/codex/myplatform
```

如果这些版本目录里已经有手工拷贝的文件，先提交或备份，再执行：

```bash
rm -rf third_party/buildroot/buildroot-2020.02 third_party/linux/imx-linux4.9.88 third_party/uboot/imx-uboot2017.03
git submodule add <buildroot_repo_url> third_party/buildroot/buildroot-2020.02
git submodule add <linux_repo_url> third_party/linux/imx-linux4.9.88
git submodule add <uboot_repo_url> third_party/uboot/imx-uboot2017.03
git submodule add <yocto_repo_url> third_party/yocto/yocto_5.10.72
git submodule add <m7_repo_url> third_party/m7
git submodule update --init --recursive
git commit -m "Add third_party source submodules"
```

如果 `third_party/yocto/` 当前已经是一个独立 git 仓库，但 remote 误指向主仓库，
不要直接在主仓库里把整个目录当普通文件提交。应该先在该目录内部修正远端，再由主仓库
以子仓库方式接入。

## 新机器拉取方式

```bash
git clone <myplatform_repo_url>
cd myplatform
git submodule update --init --recursive
```

如果已经 clone 过主仓库：

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## 与构建脚本的关系

主入口：

```bash
./build/build.sh imx6ull_100ask_pro demo_console buildroot
```

脚本优先使用：

- `third_party/buildroot/buildroot-2020.02`
- `third_party/linux/imx-linux4.9.88`
- `third_party/uboot/imx-uboot2017.03`
- `third_party/yocto/yocto_5.10.72`
- `third_party/m7`

如果这些目录不存在，才回退到旧 `100ask_imx6ull-sdk/`。

## 推荐仓库来源

优先给这三个目录分别准备独立远端：

- Buildroot 仓库：你确认过的 `buildroot-2020.02` 主线
- Linux 仓库：你现在实际维护的 `imx-linux4.9.88`
- U-Boot 仓库：你现在实际维护的 `imx-uboot2017.03`
- Yocto 仓库：你现在实际维护的 `yocto_5.10.72`
- M7 仓库：只维护 `SDK_2_10_0_EVK-MIMX8MP` 和抽取后的 `rpmsg-lite-minimal`

不要直接把 `100ask_imx6ull-sdk` 整仓作为一个子仓库挂进 `third_party`，否则还是回到旧的大杂烩结构。

M7 子仓库也不要直接提交完整 `third_party/m7/mcuxpresso-sdk`、本地 Arm GCC 工具链、SDK 压缩包或 `armgcc/debug` 构建产物。当前策略是：

- `SDK_2_10_0_EVK-MIMX8MP` 作为可启动骨架和基础源码依赖。
- `rpmsg-lite-minimal` 作为从新 MCUXpresso SDK 中抽取的最小 RPMsg-Lite 源码副本。
- `mcuxpresso-sdk` 只作为本机上游下载缓存，保留在 `.gitignore` 中。
