# MYIR i.MX8MP Yocto Layer 与 Remoteproc/RPMsg 联调笔记

这份文档记录截至当前已经学习和验证过的内容，重点覆盖：

- 怎么构建自己的 Yocto layer
- 怎么定义自己的 image
- BitBake 怎么找到 recipe、image target 和内核补丁
- 怎么把程序打进 rootfs
- 怎么把 DTS 改动做成 Yocto patch
- i.MX8MP CM7 `remoteproc` / `rpmsg` 的基本概念和当前状态
- 当前 M7 demo 固件启动后导致 SSH/串口卡死的排查结论

适用工程：

```text
/home/compile/workstation/project/codex/myplatform
```

适用板卡：

```text
MYIR MYD-JX8MP
MACHINE = myd-jx8mp
DISTRO = fsl-imx-xwayland
```

---

## 1. 当前 Yocto 构建基线

当前 Yocto 构建已经跑通，建议统一从 Docker 环境进入，不直接依赖宿主机环境。

工程根目录：

```bash
cd /home/compile/workstation/project/codex/myplatform
```

进入 Docker：

```bash
./platform/boards/myir_imx8m_plus/scripts/enter-env.sh --docker
```

进入 Yocto 构建环境：

```bash
cd /home/compile/workstation/project/codex/myplatform/third_party/yocto/yocto_5.10.72
export EULA=1
export DISTRO=fsl-imx-xwayland
export MACHINE=myd-jx8mp
source setup-environment ../../../build/out/myir_imx8m_plus/xwayland/yocto
```

当前主要输出目录：

```bash
/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
```

常见产物：

```text
Image
myd-jx8mp-base.dtb
imx-boot
myir-image-full-myd-jx8mp.wic.bz2
robobase-image-myd-jx8mp.wic.bz2
```

---

## 2. Docker 和 BitBake 入门问题

### 2.1 为什么 `docker attach` 会卡住

`docker attach <container>` 不是新开一个 shell，而是把当前终端附着到容器的主进程。

如果容器主进程不是交互 shell，或者当前没有可交互输入输出，看起来就像“卡住”。

更稳的方式是：

```bash
docker exec -it afc79328bad6 bash
```

但当前工程更推荐用封装脚本：

```bash
./platform/boards/myir_imx8m_plus/scripts/enter-env.sh --docker
```

### 2.2 WSLv2 VHDX warning

BitBake 提示：

```text
WARNING: You are running bitbake under WSLv2
```

这不是构建失败原因，只是提醒 WSL2 的虚拟磁盘可能持续膨胀。后续可以优化 VHDX，但不影响当前 Yocto 学习主线。

### 2.3 `BBMASK` 以 `|` 开头的 warning

之前出现过：

```text
WARNING: BBMASK contains regular expression beginning with '|'
```

原因是配置写成了类似：

```conf
BBMASK += "|.*/linux-yocto(_rt)?_.*\\.bb$"
```

正则开头的 `|` 没有意义，会被 BitBake 修正。当前应写成：

```conf
BBMASK += ".*/linux-yocto(_rt)?_.*\\.bb$"
```

---

## 3. 自定义 Yocto Layer

当前自定义 layer 是：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase
```

当前结构：

```text
meta-robobase/
  conf/
    layer.conf
  recipes-core/
    images/
      robobase-image.bb
  recipes-robobase/
    robobase-demo/
      test-yocto_0.1.bb
      files/
        test-yocto.c
  recipes-kernel/
    linux/
      linux-imx_%.bbappend
      files/
        0001-myir-imx8mp-enable-cm7-remoteproc.patch
```

### 3.1 `layer.conf` 的作用

`conf/layer.conf` 告诉 BitBake：

- 这个 layer 里有哪些 recipe 搜索路径
- 这个 layer 的 collection 名称是什么
- 这个 layer 的优先级是多少
- 这个 layer 兼容哪些 Yocto release

没有 `layer.conf`，BitBake 不会把这个目录当作 layer。

### 3.2 把 layer 加入构建

进入 Yocto build 环境后执行：

```bash
bitbake-layers add-layer /home/compile/workstation/project/codex/myplatform/platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase
bitbake-layers show-layers
```

如果能看到：

```text
meta-robobase
```

说明 layer 已经被 BitBake 纳入解析。

---

## 4. Recipe、PN、PV 和 BitBake Target

### 4.1 为什么是 `bitbake test-yocto`，不是 `bitbake test-yocto_0.1`

recipe 文件名：

```text
test-yocto_0.1.bb
```

Yocto 会按文件名拆成：

```text
PN = test-yocto
PV = 0.1
```

所以构建这个包时 target 是 `PN`：

```bash
bitbake test-yocto
```

不是：

```bash
bitbake test-yocto_0.1
```

`0.1` 是版本号，不是 target 名称。

### 4.2 recipe 解析错误：行首不能乱缩进

之前遇到过：

```text
ParseError ... unparsed line: '  SUMMARY = "RoboBase demo application"'
```

原因是 `.bb` 文件第一行前面有多余空格：

```bitbake
  SUMMARY = "RoboBase demo application"
```

BitBake 语法里顶层变量赋值不能随便缩进。应写成：

```bitbake
SUMMARY = "RoboBase demo application"
```

### 4.3 当前 `test-yocto` recipe

当前测试 recipe：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-robobase/robobase-demo/test-yocto_0.1.bb
```

作用：

- 从 `files/test-yocto.c` 取源码
- 用 `${CC}` 编译
- 安装到 `${bindir}`

`${bindir}` 在目标系统里通常就是：

```text
/usr/bin
```

所以程序最终应该出现在：

```text
/usr/bin/test-yocto
```

---

## 5. 自定义 Image

当前自定义 image：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-core/images/robobase-image.bb
```

核心内容：

```bitbake
require ${BSPDIR}/sources/meta-myir/meta-sdk/recipes-fsl/images/myir-image-full.bb

IMAGE_INSTALL_append = " test-yocto"
```

### 5.1 `require` 的作用

这行：

```bitbake
require ${BSPDIR}/sources/meta-myir/meta-sdk/recipes-fsl/images/myir-image-full.bb
```

不是“执行一个命令”，而是把 MYIR 官方的 `myir-image-full.bb` 内容直接包含进来。

效果是：

- 继承官方 full image 的 rootfs 内容
- 继承官方 image feature 和镜像格式
- 在这个基础上追加自己的内容

也就是说，`robobase-image` 不是从零开始造 rootfs，而是基于 `myir-image-full` 派生。

### 5.2 为什么能 `bitbake robobase-image`

BitBake 会扫描所有 layer 里的：

```text
recipes-*/*/*.bb
```

当它看到：

```text
recipes-core/images/robobase-image.bb
```

就得到：

```text
PN = robobase-image
```

所以 image target 是：

```bash
bitbake robobase-image
```

### 5.3 为什么烧录后 `/usr/bin` 里没有 `test-yocto`

常见原因只有几类：

1. 烧的是 `myir-image-full`，不是 `robobase-image`
2. `robobase-image` 没有真正把 `test-yocto` 加入 `IMAGE_INSTALL`
3. 镜像构建的是旧产物，没有重新生成 rootfs
4. 烧录的是 `.ext4` 或旧 `.wic`，不是最新完整 `.wic`
5. 板子实际启动的是 eMMC 旧系统，不是刚烧的系统

构建后先看 manifest：

```bash
grep test-yocto tmp/deploy/images/myd-jx8mp/robobase-image-myd-jx8mp.manifest
```

也可以检查 rootfs：

```bash
find tmp/work/myd_jx8mp-poky-linux/robobase-image -path '*test-yocto*'
```

如果 manifest 里没有 `test-yocto`，说明 image 没把包装进去。

如果 manifest 有，但板上没有，说明烧录/启动的不是这份镜像。

---

## 6. 镜像烧录和 DTB 替换

### 6.1 完整系统镜像用 `.wic`

完整磁盘镜像应该用：

```text
robobase-image-myd-jx8mp.wic
```

或压缩版本：

```text
robobase-image-myd-jx8mp.wic.bz2
```

不要把 `.ext4` 当完整磁盘镜像烧录。`.ext4` 只是 rootfs 分区镜像。

### 6.2 解压 `.wic.bz2`

```bash
cd /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
bzcat robobase-image-myd-jx8mp.wic.bz2 > robobase-image-myd-jx8mp.wic
```

### 6.3 如果只替换 DTB

复制到板子：

```bash
scp -O myd-jx8mp-base.dtb root@192.168.1.8:/tmp/
```

如果遇到：

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED
```

一般是因为板子重刷系统后 SSH host key 变了，或者这个 IP 之前给过别的设备。确认当前设备就是你的板子后，清理旧 key：

```bash
ssh-keygen -f /home/compile/.ssh/known_hosts -R 192.168.1.8
```

板上替换 boot 分区 DTB：

```bash
cp /run/media/mmcblk2p1/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb.bak
cp /tmp/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb
sync
reboot
```

---

## 7. 内核和 DTS 改动怎么做成 Yocto 补丁

当前内核 bbappend：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-kernel/linux/linux-imx_%.bbappend
```

内容：

```bitbake
FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append = " \
    file://0001-myir-imx8mp-enable-cm7-remoteproc.patch \
"
```

### 7.1 为什么 BitBake 知道这是打给 Linux 源码的补丁

关键是文件名：

```text
linux-imx_%.bbappend
```

它会匹配原始 recipe：

```text
linux-imx_*.bb
```

BitBake 解析 `linux-imx` recipe 时，会自动把同名 `.bbappend` 合并进去。

然后这行：

```bitbake
SRC_URI_append = " file://0001-myir-imx8mp-enable-cm7-remoteproc.patch "
```

把补丁加入 `linux-imx` 的 `SRC_URI`。

因此在内核 recipe 的 `do_patch` 阶段，Yocto 会自动把这个 patch 打到内核源码树上。

### 7.2 `FILESEXTRAPATHS_prepend` 的作用

```bitbake
FILESEXTRAPATHS_prepend := "${THISDIR}/files:"
```

告诉 BitBake：

- 当 `SRC_URI` 里出现 `file://xxx.patch`
- 先去当前 `.bbappend` 所在目录下的 `files/` 里找

所以 patch 应该放在：

```text
recipes-kernel/linux/files/
```

### 7.3 修改 patch 后怎么重新验证

修改 patch 后，不要只执行 `bitbake virtual/kernel`，因为旧的 patch 状态可能还留在 `tmp/work-shared` 里。

推荐：

```bash
bitbake -c clean virtual/kernel
bitbake -f -c patch virtual/kernel
bitbake -f -c compile virtual/kernel
bitbake -f -c deploy virtual/kernel
```

如果状态很脏，再用更重的：

```bash
bitbake -c cleansstate virtual/kernel
bitbake virtual/kernel
```

### 7.4 DTC 语法错误怎么定位

之前遇到过：

```text
DTC arch/arm64/boot/dts/myir/myd-jx8mp-base.dtb
syntax error
```

根因是 patch 里意外混入了无效文本 `hao`，最终进了 `.dts`。

定位方法：

```bash
nl -ba /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp-base.dts | sed -n '40,60p'
```

如果旧错误仍然存在，说明当前 `kernel-source` 还停留在旧 patch 状态，需要 clean 后重新 `do_patch`。

---

## 8. 当前 CM7 Remoteproc 设备树改动

当前 patch 加了一个 CM7 remoteproc 节点：

```dts
imx8mp-cm7 {
	compatible = "fsl,imx8mp-cm7";
	rsc-da = <0x55000000>;
	clocks = <&clk IMX8MP_CLK_M7_CORE>;
	mbox-names = "tx", "rx", "rxdb";
	mboxes = <&mu 0 1
		  &mu 1 1
		  &mu 3 1>;
	memory-region = <&vdevbuffer>, <&vdev0vring0>,
			<&vdev0vring1>, <&rsc_table>;
	status = "okay";
};
```

也加了 M7/rpmsg 共享内存窗口：

```dts
m7_reserved: m7@80000000 {
	no-map;
	reg = <0 0x80000000 0 0x1000000>;
};

vdev0vring0: vdev0vring0@55000000 {
	reg = <0 0x55000000 0 0x8000>;
	no-map;
};

vdev0vring1: vdev0vring1@55008000 {
	reg = <0 0x55008000 0 0x8000>;
	no-map;
};

vdevbuffer: vdevbuffer@55400000 {
	compatible = "shared-dma-pool";
	reg = <0 0x55400000 0 0x100000>;
	no-map;
};

rsc_table: rsc_table@550ff000 {
	reg = <0 0x550ff000 0 0x1000>;
	no-map;
};
```

### 8.1 `compatible`

```dts
compatible = "fsl,imx8mp-cm7";
```

用来匹配 Linux 内核里的 `imx_rproc` 驱动。

当前内核支持：

```c
{ .compatible = "fsl,imx8mp-cm7", .data = &imx_rproc_cfg_imx8mn },
```

所以这个节点会绑定到 `imx-rproc`。

### 8.2 `clocks = <&clk IMX8MP_CLK_M7_CORE>`

`IMX8MP_CLK_M7_CORE` 是当前 linux-imx 5.10.72 的 i.MX8MP clock driver 中真实注册的 CM7 core clock，对应 `clk_summary` 里的 `m7_core`。

`&clk` 是 SoC 的 clock provider。

这行告诉 `imx-rproc`：启动 M7 时需要持有并 enable `m7_core`。如果这里仍使用旧的 `IMX8MP_CLK_M7_DIV`，当前 clock driver 里没有对应 real clock，Linux late init 可能把 `m7_core` 当作 unused clock 关闭，导致 remoteproc 写 CM7 TCM 时卡死。

### 8.3 mailbox 配置

```dts
mbox-names = "tx", "rx", "rxdb";
mboxes = <&mu 0 1
	  &mu 1 1
	  &mu 3 1>;
```

含义：

- `tx`
  Linux 给 M7 发送通知
- `rx`
  Linux 接收 M7 的普通通知
- `rxdb`
  Linux 接收 M7 ready/doorbell 通知

`&mu` 是 Messaging Unit，也就是 i.MX 里的硬件 mailbox。

每一项 `<&mu x y>` 里的 `x/y` 由 i.MX mailbox 驱动解释，不是 rpmsg 消息内容本身。

启动日志里出现过：

```text
mbox_request_channel_byname() could not locate channel named "txdb"
No txdb, ret -22
```

这不是当前致命错误，因为驱动里 `txdb` 是 optional。只要后面出现：

```text
remoteproc remoteproc0: imx-rproc is available
```

说明驱动仍然可用。

### 8.4 `memory-region`

```dts
memory-region = <&vdevbuffer>, <&vdev0vring0>,
		<&vdev0vring1>, <&rsc_table>;
```

这些 region 给 remoteproc/rpmsg 使用：

- `vdevbuffer`
  rpmsg 数据 buffer
- `vdev0vring0`
  一个方向的 virtqueue ring
- `vdev0vring1`
  另一个方向的 virtqueue ring
- `rsc_table`
  resource table 所在共享内存

这些地址来自 NXP `imx8mp-evk-rpmsg.dts` 参考设计。

---

## 9. Remoteproc/RPMsg 基础概念

### 9.1 virtqueue ring 是什么

virtqueue ring 是 virtio 使用的环形队列。

在这里可以理解成：

- Linux 和 M7 共享一块内存
- 双方通过 ring 结构描述“哪里有消息”
- 真正数据放在共享 buffer 里
- mailbox/MU 只负责提醒对方“你该来看 ring 了”

当前两个 ring：

```text
vdev0vring0@55000000
vdev0vring1@55008000
```

通常分别对应两个通信方向。

### 9.2 rpmsg 是什么

rpmsg 是 Linux 里用于异构核通信的软件框架。

它解决的是：

- Linux A53 和 M7 之间怎么抽象成 channel
- 怎么按 channel name 匹配驱动
- 怎么收发短消息
- 怎么给用户态暴露 `/dev/ttyRPMSG*` 或 `/dev/rpmsg*`

rpmsg 不是硬件。它底层通常依赖：

- shared memory
- virtqueue
- mailbox/MU

### 9.3 resource table 是干什么的

resource table 是 M7 固件里的资源描述表。

它告诉 Linux remoteproc：

- 这个固件需要几个 vdev
- vdev 类型是不是 rpmsg
- vring 数量、大小、对齐
- notify id 怎么分配
- 共享内存地址怎么协商

如果固件没有正确 resource table，Linux 可能只能启动 M7，不能创建 rpmsg channel。

### 9.4 MU mailbox 和 rpmsg 的区别

MU mailbox 是硬件通知机制。

rpmsg 是软件消息协议。

关系可以这样理解：

```text
rpmsg message
  -> virtqueue ring 描述消息
  -> shared memory 保存数据
  -> MU mailbox 通知对方
```

所以：

- MU 只负责“敲门”
- rpmsg 负责“消息格式、channel、收发语义”

---

## 10. 当前板上 remoteproc 状态

替换 DTB 后，板上已经看到：

```text
/sys/class/remoteproc/remoteproc0
imx-rproc
offline

/sys/class/remoteproc/remoteproc1
imx-dsp-rproc
offline
```

这说明：

- `imx8mp-cm7` DTS 节点已经生效
- Linux 已经绑定 `imx-rproc`
- M7 remoteproc 设备已经创建
- `offline` 表示还没有启动 M7 固件，这是正常状态

常用查看命令：

```sh
dmesg | grep -Ei 'remoteproc|rpmsg|cm7|m7|imx-rproc'

for r in /sys/class/remoteproc/remoteproc*; do
  echo "$r"
  cat "$r/name"
  cat "$r/state"
done
```

注意 shell 里的 `>` 是续行提示符。比如输入了：

```sh
for r in /sys/class/remoteproc/remoteproc*; do
```

但没写 `done`，shell 就会继续等输入，并显示 `>`。

---

## 11. 当前 M7 固件位置

板上固件目录：

```sh
/lib/firmware
```

已看到：

```text
imx8mp_m7_TCM_hello_world.elf
imx8mp_m7_TCM_rpmsg_lite_pingpong_rtos_linux_remote.elf
imx8mp_m7_TCM_rpmsg_lite_str_echo_rtos.elf
imx8mp_m7_TCM_sai_low_power_audio.elf
```

Linux firmware loader 默认会从 `/lib/firmware` 查找，所以写 sysfs 时只需要写文件名：

```sh
echo imx8mp_m7_TCM_rpmsg_lite_str_echo_rtos.elf > /sys/class/remoteproc/remoteproc0/firmware
```

宿主机里对应 ELF 在：

```text
build/out/myir_imx8m_plus/xwayland/yocto/tmp/work/cortexa53-crypto-mx8mp-poky-linux/imx-m7-demos/2.10.0-r0/imx8mp-m7-demo-2.10.0/
```

注意：

- `tmp/deploy/images/myd-jx8mp/` 里主要有 `.bin`
- remoteproc/rpmsg 当前更适合用 `/lib/firmware` 里的 `.elf`

---

## 12. RPMsg demo 固件的 channel

通过查看 ELF 字符串，当前两个 rpmsg demo 的 channel 是：

### 12.1 str echo

固件：

```text
imx8mp_m7_TCM_rpmsg_lite_str_echo_rtos.elf
```

channel：

```text
rpmsg-virtual-tty-channel-1
```

Linux 侧通常由 `imx_rpmsg_tty` 匹配，并创建：

```text
/dev/ttyRPMSG*
```

### 12.2 pingpong

固件：

```text
imx8mp_m7_TCM_rpmsg_lite_pingpong_rtos_linux_remote.elf
```

channel：

```text
rpmsg-openamp-demo-channel
```

Linux 侧通常由 `imx_rpmsg_pingpong` 匹配。

---

## 13. 当前严重问题：`echo start > state` 后 SSH 和串口都卡死

当前现象：

```sh
echo imx8mp_m7_TCM_rpmsg_lite_str_echo_rtos.elf > /sys/class/remoteproc/remoteproc0/firmware
echo start > /sys/class/remoteproc/remoteproc0/state
```

执行后：

- 串口卡死
- SSH 也卡死
- 说明不是单纯“串口被抢”
- 更像是 M7 启动后破坏了 Linux 依赖的系统资源

### 13.1 排查到的证据

NXP 官方参考 DTS `imx8mp-evk-rpmsg.dts` 里有明确注释：

```text
M7 may use IPs like below
ECSPI0/ECSPI2, FLEXCAN, GPIO1/GPIO5, GPT1, I2C3, I2S3, UART4,
PWM4, SDMA1/SDMA2
```

官方参考 DTS 在启用 M7 demo 时，会禁用一批 Linux 外设，例如：

```text
ecspi2
flexcan1
flexspi
i2c3
pwm4
sai3
micfil
sdma3
uart4
```

而当前 MYIR 普通 DTS 里，很多外设仍由 Linux 管理。

此外，`rpmsg_lite_str_echo_rtos.elf` 里能看到：

```text
BOARD_BootClockRUN
BOARD_RdcInit
BOARD_InitPins
BOARD_InitDebugConsole
CLOCK_*
RDC_*
UART1/2/3/4 handler
```

这说明这个预编译 M7 demo 不是“只做 rpmsg”，它会初始化板级 clock、RDC、pinmux、debug console。

如果它是按 NXP EVK 写的，就可能和 MYIR 板的 Linux DTS 冲突。

### 13.2 历史判断

当时最大嫌疑：

```text
Linux A53 和 M7 demo 固件同时控制同一批外设、clock、RDC 或 pinmux。
```

这会导致：

- UART/网口失效
- Linux 驱动访问外设寄存器卡住
- 系统总线或中断异常
- SSH 和串口同时失去响应

后续通过极简 `robobase_m7_boot_only_wfi.elf` 和内核 remoteproc 调试日志进一步定位，真正导致 `echo start > state` 卡死的第一问题不是 M7 固件运行后的外设冲突，而是 Linux remoteproc 在加载 ELF 阶段写 CM7 ITCM `0x007e0000` 时卡死。

最终修复点是 CM7 remoteproc 节点的 clock：

```dts
clocks = <&clk IMX8MP_CLK_M7_CORE>;
```

旧写法 `IMX8MP_CLK_M7_DIV` 在当前 linux-imx 5.10.72 的 `clk-imx8mp.c` 中没有对应 real clock 注册，导致 `imx-rproc` 没有真正持有 `m7_core`。Linux late init 关闭 unused clocks 后，remoteproc 再写 CM7 TCM 就会总线卡死。

---

## 14. 当前补丁已改成安全 bring-up 版

当前 remoteproc patch 已调整为：

- 保留 CM7 remoteproc 节点
- 保留 rpmsg reserved-memory
- 临时让 Linux 关闭 NXP M7 demo 可能使用的外设

临时禁用：

```text
sound-wm8960
sound-micfil
ecspi2
flexcan1
flexspi
i2c3
pwm4
sai3
sdma3
uart4
```

目的不是最终产品永久禁用这些外设，而是先验证：

```text
系统挂死是不是由 Linux/M7 外设所有权冲突导致。
```

补丁文件：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-kernel/linux/files/0001-myir-imx8mp-enable-cm7-remoteproc.patch
```

---

## 15. 已验证的正式修复步骤

### 15.1 重新编译内核和 DTB

进入 Yocto build 环境后：

```bash
bitbake -c clean virtual/kernel
bitbake -f -c patch virtual/kernel
bitbake -f -c compile virtual/kernel
bitbake -f -c deploy virtual/kernel
```

### 15.2 替换板上 DTB

```bash
cd /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
scp -O myd-jx8mp-base.dtb root@192.168.1.8:/tmp/
```

板上：

```sh
cp /run/media/mmcblk2p1/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb.bak
cp /tmp/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb
sync
reboot
```

### 15.3 确认新 DTB 生效

重启后不要再加 `clk_ignore_unused`，先确认命令行：

```sh
cat /proc/cmdline
```

再确认运行中设备树的 CM7 clock cell：

```sh
hexdump -Cv /proc/device-tree/imx8mp-cm7/clocks
```

新 DTB 应该看到：

```text
00 00 00 02 00 00 01 31
```

其中：

```text
0x131 = 305 = IMX8MP_CLK_M7_CORE
```

如果看到 `00 00 00 55`，说明仍是旧的 `IMX8MP_CLK_M7_DIV`。

### 15.4 启动前确认 remoteproc

```sh
R=/sys/class/remoteproc/remoteproc0
cat $R/name
cat $R/state
dmesg | grep -Ei 'remoteproc|rpmsg|cm7|m7|imx-rproc'
```

### 15.5 先用极简 WFI 固件验证 remoteproc

先不要上复杂 rpmsg demo，优先用极简 WFI 固件验证基础启动链路：

```sh
R=/sys/class/remoteproc/remoteproc0

echo robobase_m7_boot_only_wfi.elf > $R/firmware
echo start > $R/state
cat $R/state
dmesg | tail -120
```

如果出现：

```text
running
```

并且系统不挂，说明 `m7_core` clock 修复生效。

当前已验证：替换为 `IMX8MP_CLK_M7_CORE` 后，不依赖 `clk_ignore_unused`，remoteproc 可以启动成功。

### 15.6 再验证 rpmsg demo

基础 remoteproc 启动稳定后，再尝试 rpmsg 固件：

```sh
R=/sys/class/remoteproc/remoteproc0

echo stop > $R/state
echo imx8mp_m7_TCM_rpmsg_lite_str_echo_rtos.elf > $R/firmware
echo start > $R/state
cat $R/state
dmesg | grep -Ei 'remoteproc|rpmsg|virtio|imx-rproc|ttyRPMSG'
```

---

## 16. 如果预编译 M7 demo 仍然导致挂死

如果安全 bring-up DTB 后仍然挂死，下一步不要继续盲试这些 `.elf`。

应转向自己构建最小 M7 固件：

1. 基于 i.MX8MP MCUXpresso SDK 建工程
2. 先不要初始化 debug UART
3. 先不要完整执行 EVK 的 `BOARD_BootClockRUN`
4. 先不要执行会重分配外设权限的 `BOARD_RdcInit`
5. 只保留 M7 启动必需的最小 clock
6. 只初始化 MU/rpmsg-lite 必需资源
7. 使用和 Linux DTS 一致的 vring/resource table 地址
8. 等 remoteproc 启动稳定后，再逐个打开外设

目标不是一开始跑复杂 demo，而是先做一个最小固件：

```text
M7 boot -> rpmsg channel announce -> Linux 看到 channel -> 不影响 Linux 存活
```

---

## 17. 当前阶段结论

截至目前已经完成：

- Yocto 构建环境跑通
- 自定义 `meta-robobase` layer 建立
- 自定义 `test-yocto` recipe 跑通
- 自定义 `robobase-image` 建立
- 理解 `bitbake <PN>` 和 image target 的关系
- 理解 image recipe 里 `require` vendor image 的作用
- 能通过 `.bbappend + patch` 给 `linux-imx` 打 DTS 补丁
- `imx8mp-cm7` remoteproc 节点已经能让 Linux 创建 `imx-rproc`
- remoteproc 写 CM7 TCM 卡死问题已通过 `IMX8MP_CLK_M7_CORE` 修复
- 不再需要依赖 `clk_ignore_unused` 启动极简 WFI M7 固件

下一步优先级：

1. 验证 remoteproc stop/start 是否稳定
2. 验证 rpmsg-lite demo 是否能创建 Linux rpmsg channel
3. 如果预编译 rpmsg demo 仍有板级冲突，切换到自己的最小 M7 rpmsg 固件
4. 最后再逐步把 M7 安全状态机接入机器人项目
