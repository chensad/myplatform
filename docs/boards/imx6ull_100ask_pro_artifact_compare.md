# imx6ull_100ask_pro Artifact Compare

对比对象：

- SDK: `100ask_imx6ull-sdk/Buildroot_2020.02.x/output`
- myplatform: `myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot`

对比时间：

- 基于 `2026-04-08` 本地构建结果

## 结论

当前 `myplatform` 已经能够完整产出镜像，但产物和旧 SDK 现有输出并不一致，还不能宣称二者完全等价。

## 关键差异

### 核心镜像文件

- `u-boot-dtb.imx` 大小相同，但 hash 不同
- `zImage` 大小接近，但 hash 不同
- `100ask_imx6ull-14x14.dtb` 大小接近，但 hash 不同
- `rootfs.ext2` 明显不同
  - SDK: `700M`
  - myplatform: `500M`

### 目标 rootfs 目录树

对比脚本结果：

- `only in sdk: 2245`
- `only in myplatform: 150`
- `files differ: 1235`

### 典型差异项

SDK 侧独有内容较多，主要集中在：

- `NetworkManager`
- `dnsmasq`
- `ntp`
- `hostapd`
- `usbmount`
- 多媒体或固件目录，如 `lib/firmware/imx`、`rtlwifi`、`sdma`、`vpu`
- 历史产品自启动脚本，如 `S05lvgl`、`S99myirhmi2`

myplatform 当前主线独有内容较少，主要来自：

- 更干净的 `current-systemV` overlay
- 额外的 `request-key.conf` / `request-key.d`
- 一些由当前配置组合生成的新链接或工具项

## 原因判断

当前差异不是单一点导致，而是配置与产品装配都还没有完全对齐：

1. `myplatform` 当前默认 overlay 已经切到更干净的 `current-systemV`
2. SDK 历史输出里包含更多产品功能和演示内容
3. 根文件系统大小配置不同
4. 内核、U-Boot、dtb 实际构建输入虽同源，但当前并非逐字节复现旧 SDK 输出

## 当前状态

已确认：

- `myplatform` 能从统一入口完整编译出 Buildroot、Linux、U-Boot 和最终镜像
- `genimage.cfg` 告警已清除

未确认：

- 与 SDK 产物逐字节一致
- 与 SDK 功能集合完全一致

## 下一步建议

如果目标是“功能兼容”：

- 继续按产品需求整理 `rootfs-overlay`
- 明确保留哪些旧 SDK 服务和演示项

如果目标是“产物尽量一致”：

- 对齐 rootfs 大小
- 对齐 SDK 侧保留的网络、固件、服务包
- 逐项比对 Buildroot 配置差异
