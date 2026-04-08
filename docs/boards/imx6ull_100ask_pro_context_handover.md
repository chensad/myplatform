# imx6ull_100ask_pro Context Handover

这份文档用于后续继续 `myplatform` 迁移和构建工作时快速恢复上下文。

更新时间：

- 2026-04-08

当前工作分支和提交：

- branch: `feat/imx6ull-buildroot-compare-readmes`
- commit: `a6c0d86`

## 当前结论

`myplatform` 已经可以从统一入口完整编译 `imx6ull_100ask_pro` 的：

- Buildroot
- Linux
- U-Boot
- rootfs
- 最终 SD 卡镜像

当前完整构建命令：

```bash
./build/build.sh imx6ull_100ask_pro demo_console buildroot
```

最终产物目录：

- `myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/images`

关键产物包括：

- `100ask-imx6ull-pro-512d-systemv-v1.img`
- `u-boot-dtb.imx`
- `zImage`
- `100ask_imx6ull-14x14.dtb`
- `rootfs.ext2`
- `rootfs.tar`

## 已完成的关键修复

### 1. 板级路径修复

文件：

- `platform/boards/imx6ull_100ask_pro/board.env`

修复点：

- 修正 `third_party` 与 legacy SDK 路径
- 明确 `THIRD_PARTY_*` 和 `LEGACY_*` 路径边界
- 明确 `BUILD_OUTPUT_BASE=build/out`

### 2. Buildroot 外部层 app 路径修复

文件：

- `platform/boards/imx6ull_100ask_pro/buildroot/external/Config.in`
- `platform/boards/imx6ull_100ask_pro/buildroot/external/external.mk`

修复点：

- 修正 app_demo 的相对路径

### 3. Buildroot 主调度脚本修复

文件：

- `platform/boards/imx6ull_100ask_pro/scripts/build-buildroot.sh`

关键修复：

- 建立 `board` 和 `local.mk` 到输出目录的软链接
- 增加 `emit_config()`，把 defconfig 里的 `#include` 片段递归展开成 `merged_defconfig`
- `make defconfig` 改为使用 `merged_defconfig`
- 编译时传入：
  - `LINUX_OVERRIDE_SRCDIR`
  - `LINUX_HEADERS_OVERRIDE_SRCDIR`
  - `UBOOT_OVERRIDE_SRCDIR`
- 优先使用本地下载缓存

### 4. Buildroot 配置修复

文件：

- `platform/boards/imx6ull_100ask_pro/buildroot/defconfig`
- `platform/boards/imx6ull_100ask_pro/buildroot/configs/100ask_imx6ull_Kernel.config`

关键修复：

- `BR2_PACKAGE_OVERRIDE_FILE="$(CONFIG_DIR)/local.mk"`
- board 路径改成本地相对路径
- 开启 `BR2_PACKAGE_HOST_GENIMAGE=y`
- 内核 patch 路径改成本地 board 相对路径

### 5. host-m4 构建失败修复

现象：

- `SIGSTKSZ` 相关编译错误

结论：

- 根因不是第三方源码要打补丁，而是 `local.mk` override 没有真正生效
- 修复后，`host-m4` 问题已经解决

### 6. linux-headers 源码来源修复

现象：

- Buildroot 试图下载 `linux-origin_master.tar.gz`

修复：

- 通过 `LINUX_HEADERS_OVERRIDE_SRCDIR` 强制走本地 `third_party/linux`

### 7. util-linux / libglib2 链路修复

现象：

- `libglib2` 找不到 `mount`

根因：

- `util-linux` 构建目录残留旧配置，实际禁用了 `libmount`

处理：

- 对 `util-linux` 和 `libglib2` 做 `dirclean`
- 重编后 `mount.pc`、`libmount.so` 正常出现

### 8. genimage 告警修复

文件：

- `platform/boards/imx6ull_100ask_pro/buildroot/board/genimage.cfg`

修复：

- 增加空的 `config {}` 段

结果：

- 清掉 `no sub-section title/index for 'config'` 告警
- 镜像输出不受影响

## 当前第三方源码状态

子模块：

- `third_party/buildroot/buildroot-2020.02`
- `third_party/linux/imx-linux4.9.88`
- `third_party/uboot/imx-uboot2017.03`

当前锁定提交：

- buildroot: `b486b7e`
- linux: `c00bf897`
- uboot: `8ba4c5bb`

结论：

- 这轮把 Buildroot 编通的修复主要都在 `myplatform` 平台层
- 当前没有额外需要再往 `third_party` 三个源码仓推送的“编译修复”

## SDK 对比结论

详细文档：

- `docs/boards/imx6ull_100ask_pro_artifact_compare.md`

结论摘要：

- `myplatform` 已能完整出镜像
- 但和 SDK 现有输出还不一致

关键差异：

- `u-boot-dtb.imx` hash 不同
- `zImage` hash 不同
- `100ask_imx6ull-14x14.dtb` hash 不同
- `rootfs.ext2` 大小不同
  - SDK: `700M`
  - myplatform: `500M`

目标 rootfs 目录树对比结果：

- `only in sdk: 2245`
- `only in myplatform: 150`
- `files differ: 1235`

SDK 侧典型独有项：

- `NetworkManager`
- `dnsmasq`
- `ntp`
- `hostapd`
- `usbmount`
- `lib/firmware/imx`
- `lib/firmware/rtlwifi`
- `lib/firmware/sdma`
- `lib/firmware/vpu`
- `S05lvgl`
- `S99myirhmi2`

## README 与目录整理状态

已完成：

- `myplatform` 根目录 README
- `apps/`、`platform/`、`third_party/`、`build/`、`tools/`、`docs/` 主层 README
- `imx6ull_100ask_pro` 常改目录 README
- `.gitignore` 已排除构建输出和缓存

## 下次继续时建议优先顺序

### 如果目标是“功能兼容 SDK”

1. 对齐 `rootfs.ext2` 大小
2. 明确是否保留 SDK 里的网络和演示服务
3. 补齐缺失固件目录
4. 对比 Buildroot 配置差异

### 如果目标是“继续做平台化整理”

1. 把 `buildroot/board` 和 `buildroot/configs` 继续往 `buildroot/external` 收
2. 抽公共脚本到 `platform/common/scripts`
3. 给 `demo_console` 明确产品层装配清单
4. 给 `drivers/out-of-tree` 补标准模板

## 常用命令

同步子模块：

```bash
git submodule update --init --recursive
```

宿主机环境初始化：

```bash
./tools/bootstrap.sh imx6ull_100ask_pro
```

完整编 Buildroot：

```bash
./build/build.sh imx6ull_100ask_pro demo_console buildroot
```

对比 SDK 与 myplatform 产物：

```bash
./tools/compare-sdk-artifacts.sh
```

