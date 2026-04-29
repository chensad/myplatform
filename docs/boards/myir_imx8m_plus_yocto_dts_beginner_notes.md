# MYIR i.MX8MP Yocto 与 DTS 入门实操笔记

这份文档只记录一件事：

- 针对当前 `myplatform` 里的 `myir_imx8m_plus` 板级，
- 作为初学者，怎么一步一步确认 Yocto 入口、找到真正生效的 DTS、
- 临时修改 DTS、重新生成 dtb、替换到板子上并验证改动生效。

本文只覆盖当前已经走通和确认过的路径，不展开到完整 Yocto layer 定制、正式 patch 管理和产品化流程。

---

## 1. 当前工程的事实

当前这块板通过 `myplatform` 进入 Yocto，核心入口如下：

- 顶层入口：
  - `myplatform/Makefile`
- 板级模型：
  - `platform/boards/myir_imx8m_plus/model.mk`
- Yocto 后端：
  - `platform/common/mk/backend-yocto.mk`
- 当前 machine：
  - `myd-jx8mp`
- 当前 distro：
  - `fsl-imx-xwayland`
- 当前 image：
  - `myir-image-full`

当前板级模型配置可直接在这里看到：

- [model.mk](/home/compile/workstation/project/codex/myplatform/platform/boards/myir_imx8m_plus/model.mk:1)

当前 `local.conf` 注入片段在这里：

- [local.conf.fragment](/home/compile/workstation/project/codex/myplatform/platform/boards/myir_imx8m_plus/yocto/local.conf.fragment:1)

当前这块板按实际内存判断是 `3G DDR`，因此显式选择：

```conf
UBOOT_CONFIG = "sd"
UBOOT_CONFIG[sd] = "myd_jx8mp_defconfig,sdcard"
```

---

## 2. 当前真正编译的 dtb 是哪个

这块板最终走的是 `myd-jx8mp` 这套 machine 配置：

- [myd-jx8mp.conf](/home/compile/workstation/project/codex/myplatform/third_party/yocto/yocto_5.10.72/sources/meta-myir/meta-bsp/conf/machine/myd-jx8mp.conf:27)
- [myd-jx8mp.inc](/home/compile/workstation/project/codex/myplatform/third_party/yocto/yocto_5.10.72/sources/meta-myir/meta-bsp/conf/machine/include/myd-jx8mp.inc:15)

它最终指定的设备树是：

```text
myir/${KERNEL_DEVICETREE_BASENAME}.dtb
```

而 `KERNEL_DEVICETREE_BASENAME` 当前是：

```text
myd-jx8mp-base
```

所以当前真正编译并部署的 dtb 是：

```text
myd-jx8mp-base.dtb
```

源码 DTS 路径是：

- [myd-jx8mp-base.dts](/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp-base.dts:1)
- [myd-jx8mp.dtsi](/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp.dtsi:1)

其中 `myd-jx8mp-base.dts` 会包含 `myd-jx8mp.dtsi`。

---

## 3. 当前产物目录

当前 Yocto 产物目录是：

```bash
/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
```

常用产物包括：

- `Image`
- `myd-jx8mp-base.dtb`
- `imx-boot`
- `myir-image-full-myd-jx8mp.wic.bz2`

可直接查看：

```bash
cd /home/compile/workstation/project/codex/myplatform
make BOARD=myir_imx8m_plus vars
ls -l build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
```

---

## 4. 这块板怎么烧录

当前这块板常用的烧录/启动方式有两条：

1. 用 `TF 卡` 写入镜像后直接启动
2. 用 `UUU` 直接刷 `eMMC`

这里的 `TF 卡` 就是 `microSD` 卡。

### 4.1 板上关键接口

当前已经确认：

- `SW1`
  - 启动拨码
- `J3`
  - `TF / microSD` 卡槽
- `J4`
  - 调试串口 `Type-C`
- `J11`
  - `USB DRP/OTG Type-C`
  - `UUU` 烧录时要接这个口

### 4.2 常用拨码

按当前资料和实板确认，`SW1(1/2/3/4)` 常用模式：

- `TF Card`
  - `OFF / OFF / ON / ON`
- `eMMC`
  - `OFF / OFF / ON / OFF`
- `USB Download`
  - `OFF / OFF / OFF / ON`

实际操作时，不要用 `0010` 这种记法，直接按板上 `ON` 的方向拨。

### 4.3 方法一：TF 卡写镜像启动

适合场景：

- 先快速验证镜像能不能启动
- 不想先改动 eMMC

主机上把 `.wic` 写进 TF 卡：

```bash
cd /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
bzcat myir-image-full-myd-jx8mp.wic.bz2 > myir-image-full-myd-jx8mp.wic
sudo dd if=myir-image-full-myd-jx8mp.wic of=/dev/sdX bs=4M status=progress conv=fsync
```

注意：

- `/dev/sdX` 是整张 TF 卡，不是分区
- 不要写成 `/dev/sdX1`

然后：

1. `SW1` 拨到 `TF Card`
2. 把 TF 卡插到 `J3`
3. 上电
4. 串口观察启动日志

### 4.4 方法二：UUU 直刷 eMMC

适合场景：

- 不需要 TF 卡
- 直接把镜像刷进 eMMC

当前确认可用的 UUU 工具目录来自：

```text
Imx8mp/Linux 5.10.9 Distribution V2.0.0/03-Tools/03-Tools/tools/MYD_JX8MP_UUU.zip
```

它里面的脚本会刷两样东西：

- `myir-image-full-myd-jx8mp.wic`
- `8E3D/imx-boot` 或对应 DDR 目录下的 `imx-boot`

当前这块板实际更像 `3G DDR`，所以本轮实际使用的是 `8E3D`。

### 4.5 当前更稳的实操建议

如果你只是想验证自己编出来的系统镜像，当前更稳的组合是：

- `myir-image-full-myd-jx8mp.wic`
  - 用你自己编出来的
- `imx-boot`
  - 先保留官方 `8E3D/imx-boot`

原因：

- 当前自编 `imx-boot` 已经确认是正确生成的 `flash.bin`
- 但它和官方 `imx-boot` 的布局明显不同
- 在没有单独验证 bootloader 链路前，先用官方 `imx-boot` 更稳

所以最适合初学者的顺序是：

1. 先验证自己编出来的 `.wic`
2. 再单独研究自己的 `imx-boot`

### 4.6 Yocto 产物里怎么得到 `.wic`

部署目录里的 `.wic.bz2` 常常是链接文件或多链接文件，`bunzip2` 可能会拒绝。

当前更稳的做法是直接流式解压：

```bash
cd /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
bzcat myir-image-full-myd-jx8mp.wic.bz2 > myir-image-full-myd-jx8mp.wic
```

如果你要复制 `imx-boot`，当前目录里的 `imx-boot` 是符号链接到 `imx-boot-tagged`。

因此复制时建议用：

```bash
cp -L imx-boot /目标路径/imx-boot
```

### 4.7 用 UUU 刷 eMMC 的步骤

1. 板子断电
2. `SW1` 拨到 `USB Download`
3. Type-C 数据线接 `J11`
4. 接上 12V 电源
5. 在主机上运行：

```text
uuu.exe uuu_8E3D.auto
```

刷完后：

1. 断电
2. `SW1` 拨回 `eMMC`
3. 重新上电

### 4.8 当前仓库里实际准备 UUU 目录的方法

因为原始工具目录权限不可写，当前实际做法是：

- 先把官方 UUU 包复制到可写目录
- 再替换里面的 `.wic`

当前可写工作目录是：

```text
/home/compile/workstation/project/codex/tmp_uuu/MYD_JX8MP_UUU
```

后续如果继续沿用当前方法，建议保持：

- `myir-image-full-myd-jx8mp.wic`
  - 用你当前构建出的版本
- `8E3D/imx-boot`
  - 先保留官方版本

### 4.9 烧录成功后怎么确认跑的是自己的镜像

不要只看内核版本字符串里的 build 时间。

因为当前已经确认：

- `.wic` 的生成时间和
- 内核版本字符串里的内嵌时间

可以不一致。

更可靠的判断方式是：

- 查你自己改过的 rootfs 内容是否存在
- 查你替换过的 dtb 是否真的生效
- 查运行时的 `model`、服务、配置文件是否符合当前镜像

---

## 5. 初学者先怎么改 DTS

### 4.1 先做临时验证，不要一开始就做正式 patch

对于初学者，先做这件事最合适：

- 直接改 `tmp/work-shared/.../kernel-source` 里的 DTS
- 目的只是验证：
  - 自己找对了文件
  - 改动会进入 dtb
  - 板子启动后能读到新内容

这个目录适合：

- 临时实验
- 快速学习

这个目录不适合：

- 长期维护
- 提交到仓库

原因很简单：

- `tmp/work-shared` 是 BitBake 的工作目录
- 后续 clean、rebuild、换环境，都可能把这里的改动覆盖掉

等这条路径走通后，再把改动做成正式 Yocto patch。

### 4.2 第一个最安全的实验

建议第一次只改 `model` 字符串。

当前文件：

- [myd-jx8mp-base.dts](/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp-base.dts:12)

把：

```dts
model = "MYIR i.MX8MP LPDDR4 EVK board";
```

临时改成：

```dts
model = "MYIR i.MX8MP LPDDR4 EVK board test1";
```

这样风险最低，验证最直观。

---

## 6. 改完 DTS 后，怎么强制重新生成 dtb

### 5.1 先确认源码里真的改进去了

```bash
grep -n 'model = ' \
  /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp-base.dts
```

如果这里没有看到 `test1`，说明不是 BitBake 的问题，而是源码没改进去。

### 5.2 不要直接把绝对路径传给 `setup-environment`

`setup-environment` 这里要用相对路径。

错误示例：

```bash
source setup-environment /home/compile/workstation/project/codex/myplatform/build/out/...
```

正确示例：

```bash
cd /home/compile/workstation/project/codex/myplatform/third_party/yocto/yocto_5.10.72
export EULA=1 DISTRO=fsl-imx-xwayland MACHINE=myd-jx8mp
source setup-environment ../../../build/out/myir_imx8m_plus/xwayland/yocto
```

### 5.3 强制重编内核并重新 deploy

只改了工作目录里的 DTS 时，普通 `bitbake virtual/kernel` 可能会复用旧结果。

因此推荐强制执行：

```bash
bitbake -f -c compile virtual/kernel
bitbake -f -c deploy virtual/kernel
```

### 5.4 检查 deploy 目录里的 dtb 是否真的变了

```bash
strings /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp/myd-jx8mp-base.dtb | grep test1
```

如果这里能搜到 `test1`，说明新 dtb 已经真正生成。

也可以顺手确认它指向的真实文件：

```bash
readlink -f /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp/myd-jx8mp-base.dtb
```

---

## 7. 怎么把新 dtb 放到板子上

### 7.1 先用 `scp -O`

当前板子没有 `sftp-server`，所以普通 `scp` 会失败：

```text
sh: line 1: /usr/libexec/sftp-server: No such file or directory
```

因此需要强制走旧的 SCP 协议：

```bash
scp -O /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp/myd-jx8mp-base.dtb root@192.168.1.8:/tmp/
```

第一次连接出现主机指纹确认是正常现象。

### 7.2 在板子上看 boot 分区挂载点

在当前板子上执行：

```bash
findmnt /boot
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
blkid
```

当前实际结果是：

- `root` 分区在 `/`
- `boot` 分区是 `mmcblk2p1`
- 它没有挂在 `/boot`
- 它挂在：

```text
/run/media/mmcblk2p1
```

因此当前直接操作：

```text
/run/media/mmcblk2p1
```

就行，不需要额外挂到 `/mnt/bootpart`。

### 7.3 先确认传到板上的新 dtb 里有 `test1`

板子上执行：

```bash
strings /tmp/myd-jx8mp-base.dtb | grep test1
```

### 7.4 备份旧 dtb，再覆盖新 dtb

板子上执行：

```bash
cp /run/media/mmcblk2p1/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb.bak
cp /tmp/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb
sync
strings /run/media/mmcblk2p1/myd-jx8mp-base.dtb | grep test1
```

如果最后一条命令能搜到 `test1`，说明 boot 分区里的 dtb 已经被正确替换。

---

## 8. 怎么验证板子运行时真的加载了新 dtb

重启板子：

```bash
reboot
```

板子起来后执行：

```bash
cat /proc/device-tree/model; echo
```

如果前面的替换成功并且启动链实际使用了这个 dtb，应该看到：

```text
MYIR i.MX8MP LPDDR4 EVK board test1
```

这一步已经验证通过，说明：

- 当前找到的 DTS 是对的
- 当前生成的 dtb 是对的
- 当前 boot 分区里的 `myd-jx8mp-base.dtb` 会被启动链实际加载

---

## 9. 今天顺手确认的 M7 现状

当前系统里：

- 看到了 DSP remoteproc
- 没看到 M7 remoteproc

运行时 `remoteproc` 的表现是：

- `/sys/class/remoteproc/remoteproc0`
- 名字是 `imx-dsp-rproc`
- 状态是 `offline`

内核配置已经包含：

- `CONFIG_REMOTEPROC=y`
- `CONFIG_IMX_REMOTEPROC=y`
- `CONFIG_RPMSG=y`

所以当前问题不在内核配置，而在当前 dtb。

源码里可以确认：

- 普通 MYIR 板级 DTS：
  - [myd-jx8mp-base.dts](/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp-base.dts:8)
  - 走的是普通板级线
- 当前 `myd-jx8mp.dtsi` 里只有 DSP 相关 `vdev0*` 预留内存：
  - [myd-jx8mp.dtsi](/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp.dtsi:202)
- 真正把 M7 打开的，是另一个 DTS：
  - [imx8mp-evk-rpmsg.dts](/home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/freescale/imx8mp-evk-rpmsg.dts:113)

也就是说：

- 当前板子跑的是普通 MYIR 板级 dtb
- 不是 rpmsg/M7 那个 dtb
- 后续如果要让 Linux 侧看到 M7，需要把 `imx8mp-evk-rpmsg.dts` 里的 M7/rpmsg 节点移植到 MYIR 板级 DTS

---

## 9.1 后续更新：M7 remoteproc 已进入联调阶段

后续已经通过 `meta-robobase` 的 `linux-imx_%.bbappend` 给 MYIR 当前 DTS 加入了
`imx8mp-cm7` 节点和 M7/rpmsg 共享内存窗口。

运行时已经看到：

```text
/sys/class/remoteproc/remoteproc0
imx-rproc
offline
```

这说明：

- 设备树里的 CM7 节点已经生效
- Linux 已经绑定到 `imx-rproc`
- M7 remoteproc 设备已经创建

当前新的问题不是“Linux 看不到 M7”，而是：

```text
echo start > /sys/class/remoteproc/remoteproc0/state
```

之后 SSH 和串口都会卡死。当前判断是 NXP 预编译 M7 demo 固件会初始化 EVK 板级
clock、RDC、pinmux 和外设，和 MYIR 当前 Linux DTS 存在资源冲突。

详细记录见：

```text
docs/boards/myir_imx8m_plus_yocto_layer_remoteproc_rpmsg_notes.md
```

---

## 10. 作为初学者，下一步建议怎么走

建议按这个顺序继续：

1. 再做 1 到 2 个低风险 DTS 改动
   - 例如加一个简单 GPIO 节点、改一个 `status`
2. 学会只重编内核并替换 dtb
3. 学会在板子上验证节点是否生效
4. 再开始学“正式做法”
   - 不改 `tmp/work-shared`
   - 改成 `Yocto patch + bbappend`

当前最重要的不是立刻追求“优雅”，而是先把下面这个闭环反复做熟：

- 找到真实 DTS
- 改一个最小改动
- 强制编译
- 确认新 dtb 生成
- 复制到 boot 分区
- 重启验证运行时生效

这个闭环走熟之后，再进入正式 patch 管理会容易很多。

---

## 11. 今日命令清单

### 查看当前 Yocto 变量

```bash
cd /home/compile/workstation/project/codex/myplatform
make BOARD=myir_imx8m_plus vars
```

### 检查当前 DTS 是否改进去了

```bash
grep -n 'model = ' \
  /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source/arch/arm64/boot/dts/myir/myd-jx8mp-base.dts
```

### 进入 Yocto 环境并强制重编内核

```bash
cd /home/compile/workstation/project/codex/myplatform/third_party/yocto/yocto_5.10.72
export EULA=1 DISTRO=fsl-imx-xwayland MACHINE=myd-jx8mp
source setup-environment ../../../build/out/myir_imx8m_plus/xwayland/yocto
bitbake -f -c compile virtual/kernel
bitbake -f -c deploy virtual/kernel
```

### 检查新 dtb 是否生成

```bash
strings /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp/myd-jx8mp-base.dtb | grep test1
```

### 生成 `.wic`

```bash
cd /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp
bzcat myir-image-full-myd-jx8mp.wic.bz2 > myir-image-full-myd-jx8mp.wic
```

### 用 UUU 刷 eMMC

```text
SW1 -> USB Download
J11 -> Type-C 数据线
12V 上电
uuu.exe uuu_8E3D.auto
刷完后 SW1 -> eMMC
```

### 复制 dtb 到板子

```bash
scp -O /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/deploy/images/myd-jx8mp/myd-jx8mp-base.dtb root@192.168.1.8:/tmp/
```

### 板子上替换 boot 分区里的 dtb

```bash
strings /tmp/myd-jx8mp-base.dtb | grep test1
cp /run/media/mmcblk2p1/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb.bak
cp /tmp/myd-jx8mp-base.dtb /run/media/mmcblk2p1/myd-jx8mp-base.dtb
sync
strings /run/media/mmcblk2p1/myd-jx8mp-base.dtb | grep test1
reboot
```

### 板子启动后验证

```bash
cat /proc/device-tree/model; echo
```
