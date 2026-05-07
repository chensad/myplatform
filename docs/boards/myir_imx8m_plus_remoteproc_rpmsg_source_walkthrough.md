# MYIR i.MX8MP Remoteproc/RPMsg 源码走读

本文面向内核基础较薄弱的阶段，目标不是一次性读懂 Linux 内核所有细节，而是把当前 MYD-JX8MP 项目里已经跑通的 `remoteproc + RPMsg tty echo` 链路拆成可以逐段阅读的代码路径。

适用对象：

```text
Board: MYIR MYD-JX8MP
SoC: NXP i.MX8M Plus
Linux: linux-imx 5.10.72
Remote core: Cortex-M7 / CM7
Linux remoteproc driver: imx-rproc
Linux RPMsg transport: virtio_rpmsg_bus
Linux RPMsg tty driver: imx_rpmsg_tty
M7 firmware: robobase_m7_rpmsg_tty_echo.elf
```

工程根目录：

```text
/home/compile/workstation/project/codex/myplatform
```

当前内核源码目录：

```text
build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source
```

当前 M7 固件源码目录：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only
```

说明：本文中的行号可能会随着补丁和源码变更而变化。真正可靠的是文件名、函数名和调用关系。

---

## 1. 先建立整体模型

当前系统里有两个处理器世界：

```text
A53/Linux 世界：
    跑 Linux。
    有进程、文件系统、驱动、sysfs、/dev/ttyRPMSG30。
    负责加载 M7 固件、启动 M7、创建 RPMsg 设备。

CM7/M7 世界：
    跑一个 bare-metal firmware。
    没有 Linux，没有进程，没有文件系统。
    只有启动代码、main()、中断、RPMsg-Lite。
```

`remoteproc` 负责“控制另一个处理器”：

```text
加载 M7 ELF 固件
解析 ELF 里的 resource table
把 .text/.data/.bss 加载到 TCM
通过 i.MX 的安全固件接口启动 CM7
根据 resource table 注册 virtio 设备
```

`rpmsg` 负责“两边通信”：

```text
Linux 和 M7 共用一块共享内存
共享内存里有 virtqueue/vring
数据本体放在共享内存 buffer 中
MU mailbox 只负责通知对方“有新消息”
```

最短总结：

```text
remoteproc 管启动。
virtio/vring 管共享内存队列。
rpmsg 管消息格式和 endpoint。
MU mailbox 管敲门通知。
```

---

## 2. 当前已经验证成功的现象对应什么

板子上看到：

```text
remoteproc remoteproc0: remote processor imx-rproc is now up
virtio_rpmsg_bus virtio0: rpmsg host is online
virtio_rpmsg_bus virtio0: creating channel rpmsg-virtual-tty-channel-1 addr 0x1e
imx_rpmsg_tty virtio0.rpmsg-virtual-tty-channel-1.-1.30: new channel: 0x400 -> 0x1e!
Install rpmsg tty driver!
/dev/ttyRPMSG30
```

这些日志可以翻译成：

```text
remote processor imx-rproc is now up
    CM7 已经被 remoteproc 启动。

registered virtio0 (type 7)
    Linux 从 M7 的 resource table 里发现了 VIRTIO_ID_RPMSG。

rpmsg host is online
    virtio_rpmsg_bus 已经接管这个 virtio RPMsg 设备。

creating channel rpmsg-virtual-tty-channel-1 addr 0x1e
    M7 主动向 Linux announce 了一个 RPMsg channel。

new channel: 0x400 -> 0x1e
    Linux 侧 tty driver 分配了本地 endpoint 0x400，远端 M7 endpoint 是 0x1e。

/dev/ttyRPMSG30
    imx_rpmsg_tty driver 把这个 RPMsg channel 暴露成了 tty 设备。
```

`0x1e` 是十进制 30，所以设备名是：

```text
/dev/ttyRPMSG30
```

---

## 3. 源码阅读地图

Linux 侧主要文件：

```text
drivers/remoteproc/remoteproc_sysfs.c
    /sys/class/remoteproc/remoteproc0/state 和 firmware 的入口。

drivers/remoteproc/remoteproc_core.c
    remoteproc 核心流程，负责 boot、parse firmware、load segments、handle resources、start subdevices。

drivers/remoteproc/imx_rproc.c
    NXP i.MX 平台 remoteproc 驱动，负责 CM7 地址映射、SMC 启动、MU mailbox kick。

drivers/remoteproc/remoteproc_virtio.c
    remoteproc 和 virtio 的桥，负责把 resource table 里的 vdev 注册成 Linux virtio device。

drivers/rpmsg/virtio_rpmsg_bus.c
    RPMsg 的 virtio transport，负责 vring buffer、rpmsg_hdr、endpoint 查找、收发。

drivers/rpmsg/rpmsg_core.c
    RPMsg bus 核心，负责 rpmsg_device/rpmsg_driver 的注册和匹配。

drivers/rpmsg/rpmsg_ns.c
    RPMsg name service，负责接收 M7 发来的 channel announce。

drivers/rpmsg/imx_rpmsg_tty.c
    NXP 的 RPMsg tty driver，负责把某些 channel 变成 /dev/ttyRPMSGx。

include/linux/remoteproc.h
    remoteproc 对外结构定义，比如 struct rproc、resource table 结构。

include/uapi/linux/virtio_ids.h
    virtio device id 定义，比如 VIRTIO_ID_RPMSG = 7。
```

M7 侧主要文件：

```text
robobase_m7_rpmsg_tty_echo.c
    M7 主程序，创建 endpoint，announce channel，echo Linux 发来的数据。

robobase_m7_rsc_table.c
    M7 ELF 的 .resource_table，告诉 Linux 这个固件需要 RPMsg virtio 设备。

armgcc/MIMX8ML8xxxxx_cm7_ram.ld
    链接脚本，确保 .resource_table 被放进 ELF。

third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/rpmsg_lite.c
    RPMsg-Lite 核心。

third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/rpmsg_ns.c
    M7 侧 name service announce。

third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/porting/platform/imx8mp_m7/rpmsg_platform.c
    M7 侧 i.MX8MP MU mailbox porting。

third_party/m7/rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/porting/environment/rpmsg_env_bm.c
    RPMsg-Lite bare-metal 环境层。
```

---

## 4. 从 `echo start` 开始看 remoteproc

板子上启动 M7 的命令：

```bash
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_rpmsg_tty_echo.elf > "$R/firmware"
echo start > "$R/state"
```

第一句设置固件名：

```text
/sys/class/remoteproc/remoteproc0/firmware
```

第二句触发启动：

```text
/sys/class/remoteproc/remoteproc0/state
```

源码入口：

```text
drivers/remoteproc/remoteproc_sysfs.c
```

重点看：

```c
state_store()
```

这个函数大概做：

```text
如果用户写入 "start"：
    调用 rproc_boot(rproc)

如果用户写入 "stop"：
    调用 rproc_shutdown(rproc)
```

所以用户态一条：

```bash
echo start > /sys/class/remoteproc/remoteproc0/state
```

进入内核后就变成：

```text
state_store()
-> rproc_boot()
```

---

## 5. `rproc_boot()` 做什么

文件：

```text
drivers/remoteproc/remoteproc_core.c
```

函数：

```c
rproc_boot()
```

可以把它理解成 remoteproc 的顶层启动函数。它主要做：

```text
1. 检查 remoteproc 当前状态。
2. 增加 power 引用计数。
3. 根据 rproc->firmware 请求固件文件。
4. 调用 rproc_fw_boot() 真正启动。
```

关键动作是：

```c
request_firmware(&firmware_p, rproc->firmware, dev)
```

这里的 `rproc->firmware` 就是你写入 sysfs 的：

```text
robobase_m7_rpmsg_tty_echo.elf
```

Linux firmware loader 会去查找：

```text
/lib/firmware/robobase_m7_rpmsg_tty_echo.elf
```

所以 remoteproc 能启动这个 ELF 的前提是：

```text
1. /lib/firmware 下有这个文件。
2. 文件名和 sysfs firmware 内容完全一致。
3. ELF 格式正确。
4. ELF 中有 remoteproc 能解析的段和 resource table。
```

常用检查：

```bash
cat /sys/class/remoteproc/remoteproc0/firmware
ls -l /lib/firmware/robobase_m7_rpmsg_tty_echo.elf
```

---

## 6. `request_firmware()` 不是 remoteproc 独有

`request_firmware()` 是 Linux 通用 firmware loader。

声明：

```text
include/linux/firmware.h
```

实现：

```text
drivers/base/firmware_loader/main.c
```

注意：它的实现里 `int` 和函数名可能分行写，所以 VSCode 搜索：

```text
request_firmware(
```

比搜索：

```text
int request_firmware(
```

更可靠。

在当前 remoteproc 场景中，它只是把 ELF 文件从 rootfs 加载进 Linux 内存，接下来还要由 remoteproc 解析这个 ELF。

---

## 7. `rproc_fw_boot()` 是启动主流程

文件：

```text
drivers/remoteproc/remoteproc_core.c
```

函数：

```c
rproc_fw_boot()
```

它可以理解成：

```text
拿到 firmware 文件后，按 remoteproc 规则处理它。
```

核心流程：

```text
rproc_fw_sanity_check()
    检查 ELF 是否基本合法。

rproc_enable_iommu()
    如果平台需要 IOMMU，在这里启用。

rproc_prepare_device()
    平台相关 prepare。

rproc_get_boot_addr()
    从 ELF 里读取入口地址。

rproc_parse_fw()
    解析 ELF 里的 resource table。

rproc_handle_resources()
    根据 resource table 申请 carveout、vdev、trace 等资源。

rproc_alloc_registered_carveouts()
    分配前面登记的 carveout。

rproc_start()
    加载 ELF 段，启动远端核，启动 subdevices。
```

你之前加的 debug log 里已经能看到这个顺序：

```text
fw_boot: sanity_check ret=0
fw_boot: parse_fw begin
fw_boot: handle_resources begin
fw_boot: alloc_carveouts begin
fw_boot: rproc_start begin
```

---

## 8. ELF 是什么，remoteproc 怎么用它

ELF 是一种可执行文件格式。Linux 上的普通程序、内核模块、M7 固件都可以是 ELF。

对 remoteproc 来说，M7 ELF 里最重要的是：

```text
入口地址：
    M7 从哪里开始执行。

program headers：
    哪些内容需要加载到内存。

.text：
    代码指令。

.data：
    已初始化的全局变量/静态变量。

.bss：
    未初始化或零初始化的全局变量/静态变量。

.resource_table：
    remoteproc 专用资源表。
```

remoteproc 加载 ELF 段时会做：

```text
对 .text/.data：
    memcpy 到目标地址。

对 .bss：
    memset 为 0。
```

你之前看到的 debug：

```text
da=0x0 len=0x2a8 sys=0x7e0000
elf_memcpy begin
elf_memcpy done
```

可以翻译成：

```text
ELF 里某段的 device address 是 0x0。
对 M7 来说 0x0 是 ITCM 开头。
对 A53/Linux 来说对应物理地址 0x007e0000。
Linux 把这段内容 memcpy 到 0x007e0000 对应的映射地址。
```

---

## 9. `struct rproc` 是 remoteproc 的核心对象

定义：

```text
include/linux/remoteproc.h
```

重点字段：

```c
struct rproc {
    const char *name;
    char *firmware;
    struct device dev;
    enum rproc_state state;
    const struct rproc_ops *ops;
    struct list_head rvdevs;
    struct list_head carveouts;
    struct list_head mappings;
    struct resource_table *cached_table;
    struct resource_table *table_ptr;
};
```

初学时可以这样理解：

```text
name：
    remoteproc 名字，比如 imx-rproc。

firmware：
    要加载的固件名。

state：
    offline、running 等状态。

ops：
    平台相关操作函数表。
    比如 start、stop、kick、da_to_va。

rvdevs：
    resource table 里声明的 virtio device 列表。

carveouts：
    remoteproc 需要管理的内存区域。

cached_table：
    Linux 解析并可能修改后的 resource table 副本。

table_ptr：
    当前实际使用的 resource table 指针。
```

`remoteproc_core.c` 是通用框架，不知道具体芯片怎么启动 CM7。它只会调用：

```c
rproc->ops->start(rproc)
rproc->ops->stop(rproc)
rproc->ops->kick(rproc, vqid)
rproc->ops->da_to_va(rproc, da, len, ...)
```

这些函数由 i.MX 平台驱动提供。

---

## 10. 为什么 `rproc->ops->start()` 会变成 `imx_rproc_start()`

文件：

```text
drivers/remoteproc/imx_rproc.c
```

里面有一个函数表：

```c
static const struct rproc_ops imx_rproc_ops = {
    .start = imx_rproc_start,
    .stop = imx_rproc_stop,
    .kick = imx_rproc_kick,
    .da_to_va = imx_rproc_da_to_va,
    .load = imx_rproc_elf_load_segments,
    .parse_fw = imx_rproc_parse_fw,
    .find_loaded_rsc_table = imx_rproc_elf_find_loaded_rsc_table,
    .sanity_check = rproc_elf_sanity_check,
    .get_boot_addr = rproc_elf_get_boot_addr,
};
```

probe 时调用：

```c
rproc_alloc(dev, "imx-rproc", &imx_rproc_ops, NULL, sizeof(*priv))
```

这一步把 `imx_rproc_ops` 塞进了 `struct rproc`。

所以 remoteproc core 里看起来是：

```c
rproc->ops->start(rproc)
```

实际运行时就是：

```c
imx_rproc_start(rproc)
```

这就是 C 语言里常见的“函数指针表”。

---

## 11. DTS compatible 怎么选中 i.MX8MP 配置

你的 DTS 里有类似：

```dts
imx8mp-cm7 {
    compatible = "fsl,imx8mp-cm7";
    ...
};
```

`imx_rproc.c` 里有匹配表：

```c
static const struct of_device_id imx_rproc_of_match[] = {
    ...
    { .compatible = "fsl,imx8mp-cm7", .data = &imx_rproc_cfg_imx8mn },
    ...
};
```

注意这里：

```text
fsl,imx8mp-cm7
```

匹配到的是：

```text
imx_rproc_cfg_imx8mn
```

也就是说 i.MX8MP CM7 在这个驱动里复用了 i.MX8MN CM7 的配置。

配置内容大概是：

```c
static const struct imx_rproc_dcfg imx_rproc_cfg_imx8mn = {
    .att = imx_rproc_att_imx8mn,
    .att_size = ARRAY_SIZE(imx_rproc_att_imx8mn),
    .elf_mem_hook = true,
    .method = IMX_ARM_SMCCC,
};
```

所以这几个结论很重要：

```text
1. 地址映射表用 imx_rproc_att_imx8mn。
2. ELF memcpy/memset 走 i.MX 自己的 hook。
3. 启动方式是 IMX_ARM_SMCCC。
```

---

## 12. 为什么启动 CM7 会走 SMC M4_START

`imx_rproc_start()` 里有：

```c
switch (dcfg->method) {
case IMX_DIRECT_MMIO:
    ...
    break;

case IMX_ARM_SMCCC:
    arm_smccc_smc(IMX_SIP_SRC, IMX_SIP_SRC_M4_START, 0, 0, 0, 0, 0, 0, &res);
    ret = res.a0;
    break;

case IMX_SCU_API:
    ...
    break;
}
```

前面已经知道：

```text
dcfg->method = IMX_ARM_SMCCC
```

所以一定进入：

```text
IMX_ARM_SMCCC 分支
```

然后调用：

```c
arm_smccc_smc(IMX_SIP_SRC, IMX_SIP_SRC_M4_START, ...)
```

`SMC` 是：

```text
Secure Monitor Call
```

意思是 Linux 内核通过 ARM 的安全调用机制进入 EL3 安全固件，通常是 ATF。某些复位、启动、低功耗相关操作不能由 Linux 直接随便写寄存器完成，需要 secure firmware 代做。

`M4_START` 这个名字看起来像 Cortex-M4，但在 NXP 的 SIP API 里是历史命名。对 i.MX8MP CM7 来说，也复用了这个名字。

定义在：

```text
include/soc/imx/imx_sip.h
```

```c
#define IMX_SIP_SRC             0xc2000005
#define IMX_SIP_SRC_M4_START    0x00
#define IMX_SIP_SRC_M4_STARTED  0x01
#define IMX_SIP_SRC_M4_STOP     0x02
```

所以：

```text
SMC M4_START
```

实际意思是：

```text
请 secure firmware 启动辅助 Cortex-M 核。
```

---

## 13. M7 地址 0x0 为什么对应 A53 物理地址 0x007e0000

M7 看到的地址空间和 A53/Linux 看到的物理地址空间不是完全一样的。

对 CM7 来说：

```text
0x00000000
    ITCM 开头，通常放 vector table 和代码。

0x20000000
    DTCM 开头，通常放数据。
```

对 A53/Linux 来说，访问同一块 TCM 的系统物理地址是：

```text
0x007e0000
    M7 ITCM 对应的系统地址。

0x00800000
    M7 DTCM 对应的系统地址。
```

`imx_rproc.c` 里的 address translation table 描述了这个关系：

```c
{ 0x00000000, 0x007E0000, 0x00020000, ATT_OWN },
{ 0x20000000, 0x00800000, 0x00020000, ATT_OWN },
```

可以读成：

```text
M7 device address 0x00000000
    -> A53 system address 0x007e0000
    -> size 128 KiB

M7 device address 0x20000000
    -> A53 system address 0x00800000
    -> size 128 KiB
```

remoteproc 加载 ELF 段时，ELF 里写的是 M7 视角地址，也就是 `da`，device address。

Linux 真正 memcpy 时必须变成自己能访问的地址，所以走：

```text
imx_rproc_da_to_va()
```

它的大致过程：

```text
输入 da = 0x0
查表发现 0x0 落在 ITCM 区间
换算 sys = 0x007e0000
找到之前 ioremap 出来的 Linux kernel virtual address
返回 va
```

所以 debug 里看到：

```text
da=0x0 sys=0x7e0000 va=...
```

这说明 TCM 地址转换生效。

---

## 14. TCM 在这里的意义

TCM 是：

```text
Tightly Coupled Memory
```

可以简单理解为 Cortex-M7 身边的一小块高速 SRAM。它不是 DDR。

特点：

```text
1. 容量小。
2. 访问快。
3. 延迟稳定。
4. 适合放实时控制代码、中断向量、关键数据。
```

在 i.MX8MP CM7 场景里：

```text
ITCM
    放指令、vector table。

DTCM
    放数据、栈、bss。
```

Linux remoteproc 在启动 M7 前，要把 ELF 的代码和数据加载进 TCM。M7 启动后从 TCM 取 vector table，然后跳到 Reset_Handler。

---

## 15. resource table 是 Linux 和 M7 的“启动合同”

M7 ELF 里有一个 `.resource_table` section。

你的 M7 侧文件：

```text
robobase_m7_rsc_table.c
```

核心结构：

```c
const struct robobase_remote_resource_table resources = {
    1,
    ROBOBASE_NUM_RSC_ENTRIES,
    {0, 0},
    {offsetof(struct robobase_remote_resource_table, user_vdev)},
    {
        RSC_VDEV,
        7,
        0,
        ROBOBASE_RSC_VDEV_FEATURE_NS,
        0,
        0,
        0,
        ROBOBASE_NUM_VRINGS,
        {0, 0},
    },
    {ROBOBASE_VDEV0_VRING_BASE, VRING_ALIGN, RL_BUFFER_COUNT, 0, 0},
    {ROBOBASE_VDEV0_VRING_BASE + VRING_SIZE, VRING_ALIGN, RL_BUFFER_COUNT, 1, 0},
};
```

这段可以逐项解释：

```text
version = 1
    resource table 版本。

num = 1
    只有一个 resource entry。

offset[0]
    第 0 个 entry 在结构体里的偏移。

RSC_VDEV
    这个 entry 的类型是 virtio device。

id = 7
    virtio device id。7 表示 VIRTIO_ID_RPMSG。

dfeatures = ROBOBASE_RSC_VDEV_FEATURE_NS
    M7 支持 RPMsg name service。

num_of_vrings = 2
    这个 RPMsg vdev 有两个 vring。

vring0
    一条方向的 ring。

vring1
    另一条方向的 ring。
```

Linux 侧对应结构定义：

```text
include/linux/remoteproc.h
```

重点结构：

```c
struct fw_rsc_vdev {
    u32 id;
    u32 notifyid;
    u32 dfeatures;
    u32 gfeatures;
    u32 config_len;
    u8 status;
    u8 num_of_vrings;
    u8 reserved[2];
    struct fw_rsc_vdev_vring vring[];
};

struct fw_rsc_vdev_vring {
    u32 da;
    u32 align;
    u32 num;
    u32 notifyid;
    u32 pa;
};
```

这就是 Linux 能解析 M7 resource table 的原因：两边使用兼容的数据结构。

---

## 16. resource table 怎么被放进 ELF

M7 侧 resource table 变量有：

```c
__attribute__((section(".resource_table"), used))
const struct robobase_remote_resource_table resources = { ... };
```

意思是：

```text
把 resources 这个变量放进 ELF 的 .resource_table section。
即使编译器觉得它没被 C 代码引用，也不要优化掉。
```

链接脚本里有：

```ld
.resource_table :
{
    KEEP(*(.resource_table))
}
```

`KEEP` 的意义是：

```text
链接器做垃圾回收时，也不能丢掉 .resource_table。
```

所以最终 ELF 里会有：

```text
.resource_table
```

remoteproc 解析 firmware 时能找到它。

---

## 17. Linux 如何处理 RSC_VDEV

文件：

```text
drivers/remoteproc/remoteproc_core.c
```

resource table 解析过程中，`RSC_VDEV` 会进入：

```c
rproc_handle_vdev()
```

这个函数的作用：

```text
1. 检查 resource table 里的 vdev entry 是否完整。
2. 读取 vdev id，比如 7。
3. 读取 num_of_vrings，比如 2。
4. 为每个 vring 调用 rproc_parse_vring()。
5. 为每个 vring 调用 rproc_alloc_vring()。
6. 创建 struct rproc_vdev。
7. 把 rproc_vdev 加入 rproc->rvdevs。
8. 注册一个 remoteproc subdevice。
```

关键代码：

```c
rvdev->id = rsc->id;
...
for (i = 0; i < rsc->num_of_vrings; i++)
    rproc_parse_vring(rvdev, rsc, i);

for (i = 0; i < rsc->num_of_vrings; i++)
    rproc_alloc_vring(rvdev, i);

rvdev->subdev.start = rproc_vdev_do_start;
rproc_add_subdev(rproc, &rvdev->subdev);
```

注意：

```text
rproc_handle_vdev() 只是准备 virtio 设备。
它还没有真正把 virtio0 注册出来。
真正注册发生在 M7 启动成功之后的 start_subdevices 阶段。
```

---

## 18. 为什么 virtio0 是 M7 启动后才出现

`rproc_start()` 的顺序很重要：

```text
1. rproc_load_segments()
2. 复制 resource table 到 remote memory
3. rproc_prepare_subdevices()
4. rproc->ops->start()
5. rproc_start_subdevices()
6. state = RPROC_RUNNING
```

第 4 步是启动 M7：

```c
rproc->ops->start(rproc)
```

在 i.MX8MP 上就是：

```text
imx_rproc_start()
-> arm_smccc_smc(... M4_START ...)
```

第 5 步才启动 subdevices：

```c
rproc_start_subdevices(rproc)
```

前面 `rproc_handle_vdev()` 注册过：

```c
rvdev->subdev.start = rproc_vdev_do_start;
```

所以这里会调用：

```c
rproc_vdev_do_start()
-> rproc_add_virtio_dev(rvdev, rvdev->id)
```

这就是为什么你看到日志顺序是：

```text
ops->start done ret=0
start_subdevices begin
remoteproc0#vdev0buffer: registered virtio0 (type 7)
```

---

## 19. remoteproc 如何注册 virtio0

文件：

```text
drivers/remoteproc/remoteproc_virtio.c
```

函数：

```c
rproc_add_virtio_dev()
```

关键逻辑：

```c
vdev = kzalloc(sizeof(*vdev), GFP_KERNEL);
vdev->id.device = id;
vdev->config = &rproc_virtio_config_ops;
vdev->dev.parent = dev;
register_virtio_device(vdev);
```

这里的 `id` 来自 M7 resource table：

```text
id = 7
```

所以 Linux 注册出来：

```text
virtio0 type 7
```

type 7 是：

```text
VIRTIO_ID_RPMSG
```

所以后面会被 `virtio_rpmsg_bus` 匹配。

---

## 20. virtio_rpmsg_bus 如何接管 virtio0

文件：

```text
drivers/rpmsg/virtio_rpmsg_bus.c
```

驱动匹配表：

```c
static struct virtio_device_id id_table[] = {
    { VIRTIO_ID_RPMSG, VIRTIO_DEV_ANY_ID },
    { 0 },
};
```

所以只要 virtio device 的 id 是 7，就会进入：

```c
rpmsg_probe(struct virtio_device *vdev)
```

这个函数做：

```text
1. 分配 struct virtproc_info。
2. 找到两个 virtqueue，input 和 output。
3. 分配 RPMsg buffer。
4. 把一半 buffer 给 RX，一半给 TX。
5. 创建 rpmsg_ctrl 设备。
6. 如果支持 name service，创建 rpmsg_ns 设备。
7. 设置 virtio_device_ready。
8. kick 远端，让 M7 可以开始发消息。
```

你看到的日志：

```text
virtio_rpmsg_bus virtio0: rpmsg host is online
```

就是这个阶段完成后出现的。

---

## 21. virtqueue/vring 是什么

可以先把 `virtqueue` 理解成：

```text
Linux 和 M7 共享的一条环形消息队列。
```

更准确一点：

```text
vring 是内存布局。
virtqueue 是代码里操作 vring 的抽象。
```

一个 vring 里面主要有三类东西：

```text
descriptor table
    描述每个 buffer 的地址、长度、flags。

available ring
    生产者告诉消费者：这些 descriptor 里有新 buffer 可用。

used ring
    消费者告诉生产者：这些 buffer 我用完了。
```

为什么需要两个 vring：

```text
一个方向：Linux 给 M7 发消息。
另一个方向：M7 给 Linux 发消息。
```

在 Linux 的 `virtio_rpmsg_bus.c` 里，这两个队列叫：

```text
rvq
    receive virtqueue，Linux 用来收 M7 发来的消息。

svq
    send virtqueue，Linux 用来发消息给 M7。
```

在 M7 的 RPMsg-Lite 里也有两个：

```text
rvq
    M7 接收 Linux 发来的消息。

tvq
    M7 发送消息给 Linux。
```

两边命名视角不同，但指向同一组共享内存 ring。

---

## 22. RPMsg endpoint 和 channel 是什么

`channel` 是一种服务名：

```text
rpmsg-virtual-tty-channel-1
```

Linux 通过 channel name 匹配对应的 rpmsg driver：

```text
imx_rpmsg_tty
```

`endpoint` 是一个地址：

```text
Linux endpoint: 0x400
M7 endpoint:    0x1e
```

每个 RPMsg 包都有：

```text
src
dst
len
payload
```

比如 Linux 发给 M7：

```text
src = 0x400
dst = 0x1e
payload = "robobase-test\n"
```

M7 echo 回来：

```text
src = 0x1e
dst = 0x400
payload = "robobase-test\n"
```

所以 endpoint 的作用是：

```text
让接收方知道这个包应该交给哪个 callback。
```

---

## 23. M7 如何 announce channel

M7 主程序：

```text
robobase_m7_rpmsg_tty_echo.c
```

初始化 RPMsg-Lite：

```c
rpmsg = rpmsg_lite_remote_init(ROBOBASE_RPMSG_SHMEM_BASE,
                               RL_PLATFORM_IMX8MP_M7_USER_LINK_ID,
                               RL_NO_FLAGS,
                               &s_rpmsg_context);
```

等待 Linux 端 ready：

```c
rpmsg_lite_wait_for_link_up(rpmsg, RL_BLOCK)
```

创建 M7 endpoint：

```c
ept = rpmsg_lite_create_ept(rpmsg,
                            ROBOBASE_RPMSG_LOCAL_EPT_ADDR,
                            robobase_rpmsg_rx_cb,
                            NULL,
                            &s_ept_context);
```

这里：

```text
ROBOBASE_RPMSG_LOCAL_EPT_ADDR = 30
```

也就是：

```text
0x1e
```

然后 announce：

```c
rpmsg_ns_announce(rpmsg, ept, "rpmsg-virtual-tty-channel-1", RL_NS_CREATE)
```

`rpmsg_ns_announce()` 会组一个 name service 消息：

```c
ns_msg.name = ept_name;
ns_msg.flags = RL_NS_CREATE;
ns_msg.addr = new_ept->addr;
```

然后发给 Linux 的 name service endpoint。

---

## 24. Linux 如何根据 announce 创建 RPMsg device

文件：

```text
drivers/rpmsg/rpmsg_ns.c
```

Linux 收到 name service 消息后进入：

```c
rpmsg_ns_cb()
```

它做：

```c
strncpy(chinfo.name, msg->name, sizeof(chinfo.name));
chinfo.src = RPMSG_ADDR_ANY;
chinfo.dst = msg->addr;
rpmsg_create_channel(rpdev, &chinfo);
```

对你的 M7 固件来说：

```text
msg->name = "rpmsg-virtual-tty-channel-1"
msg->addr = 0x1e
```

所以 Linux 创建了一个 rpmsg_device：

```text
name = rpmsg-virtual-tty-channel-1
dst = 0x1e
src = RPMSG_ADDR_ANY
```

之后 RPMsg bus 会拿这个 device 去匹配所有 rpmsg driver。

---

## 25. 为什么匹配到 imx_rpmsg_tty

文件：

```text
drivers/rpmsg/imx_rpmsg_tty.c
```

匹配表：

```c
static struct rpmsg_device_id rpmsg_driver_tty_id_table[] = {
    { .name = "rpmsg-virtual-tty-channel-1" },
    { .name = "rpmsg-virtual-tty-channel" },
    { .name = "rpmsg-openamp-demo-channel" },
    { },
};
```

你的 M7 announce 的 name 正好是：

```text
rpmsg-virtual-tty-channel-1
```

所以匹配成功。

RPMsg bus 的匹配逻辑在：

```text
drivers/rpmsg/rpmsg_core.c
```

它按 `rpdev->id.name` 和 driver id table 的 name 比较。

匹配成功后进入：

```c
rpmsg_tty_probe()
```

probe 里创建 tty driver：

```c
rpmsgtty_driver->name = kasprintf(GFP_KERNEL, "ttyRPMSG%d", rpdev->dst);
tty_register_driver(cport->rpmsgtty_driver);
```

因为：

```text
rpdev->dst = 30
```

所以设备名是：

```text
ttyRPMSG30
```

最终用户态看到：

```text
/dev/ttyRPMSG30
```

---

## 26. Linux 发送数据到 M7 的完整路径

用户态：

```bash
printf 'robobase-test\n' > /dev/ttyRPMSG30
```

进入 Linux tty 层后，调用 `imx_rpmsg_tty` 的 write：

```text
drivers/rpmsg/imx_rpmsg_tty.c
```

函数：

```c
rpmsgtty_write()
```

它做：

```text
1. 从 tty 拿到用户写入的数据。
2. 每包最多发送 RPMSG_MAX_SIZE。
3. 调用 rpmsg_send(rpdev->ept, data, len)。
```

代码大概是：

```c
ret = rpmsg_send(rpdev->ept, (void *)tbuf, count);
```

然后进入：

```text
drivers/rpmsg/rpmsg_core.c
```

```c
rpmsg_send()
```

这个函数只是一个转发层：

```c
return ept->ops->send(ept, data, len);
```

当前 endpoint 的 ops 来自 `virtio_rpmsg_bus`，所以进入：

```text
drivers/rpmsg/virtio_rpmsg_bus.c
```

```c
virtio_rpmsg_send()
```

它取出：

```c
src = ept->addr;
dst = rpdev->dst;
```

在你的场景中：

```text
src = 0x400
dst = 0x1e
```

然后进入：

```c
rpmsg_send_offchannel_raw()
```

这个函数是真正组包和入队的地方。

---

## 27. `rpmsg_send_offchannel_raw()` 如何组包

文件：

```text
drivers/rpmsg/virtio_rpmsg_bus.c
```

RPMsg header：

```c
struct rpmsg_hdr {
    __rpmsg32 src;
    __rpmsg32 dst;
    __rpmsg32 reserved;
    __rpmsg16 len;
    __rpmsg16 flags;
    u8 data[];
} __packed;
```

发送时：

```c
msg = get_a_tx_buf(vrp);
msg->len = len;
msg->flags = 0;
msg->src = src;
msg->dst = dst;
msg->reserved = 0;
memcpy(msg->data, data, len);
```

这一步完成后，共享内存里的 buffer 大概是：

```text
src      = 0x400
dst      = 0x1e
len      = 14
payload  = robobase-test\n
```

然后：

```c
virtqueue_add_outbuf(vrp->svq, &sg, 1, msg, GFP_KERNEL);
virtqueue_kick(vrp->svq);
```

含义：

```text
virtqueue_add_outbuf()
    把这个 buffer 放进 Linux -> M7 方向的 virtqueue。

virtqueue_kick()
    通知 M7：队列里有新消息。
```

---

## 28. Linux 的 kick 如何变成 MU mailbox

`virtqueue_kick()` 在通用 virtio ring 代码里：

```text
drivers/virtio/virtio_ring.c
```

它最终会调用：

```c
vq->notify(vq)
```

这个 notify 是创建 virtqueue 时传进去的：

```text
drivers/remoteproc/remoteproc_virtio.c
```

```c
vring_new_virtqueue(..., rproc_virtio_notify, callback, name);
```

所以 kick 进入：

```c
rproc_virtio_notify()
```

这个函数做：

```c
rproc->ops->kick(rproc, notifyid);
```

前面已经知道 `rproc->ops->kick` 实际是：

```text
imx_rproc_kick()
```

文件：

```text
drivers/remoteproc/imx_rproc.c
```

代码：

```c
mmsg = vqid << 16;
mbox_send_message(priv->tx_ch, (void *)&mmsg);
```

所以 Linux 发送一包 RPMsg 的最后一步是：

```text
通过 MU mailbox 给 M7 发一个中断消息。
```

注意：MU 里传的不是 payload。payload 已经在共享内存里。MU 只传一个 notify id，告诉 M7 去检查哪个 virtqueue。

---

## 29. M7 如何收到 Linux 发来的数据

M7 侧 MU 中断文件：

```text
rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/porting/platform/imx8mp_m7/rpmsg_platform.c
```

中断函数：

```c
MU1_M7_IRQHandler()
```

核心逻辑：

```c
channel = MU_ReceiveMsgNonBlocking(MUB, RPMSG_MU_CHANNEL);
env_isr(channel >> 16);
```

这里 `channel >> 16` 还原出 Linux 发来的 `vqid`。

`env_isr()` 在：

```text
rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/porting/environment/rpmsg_env_bm.c
```

它会调用：

```c
virtqueue_notification((struct virtqueue *)info->data);
```

然后进入 RPMsg-Lite 的 virtqueue callback。

M7 侧接收 callback：

```text
rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/rpmsg_lite.c
```

```c
rpmsg_lite_rx_callback()
```

这个函数做：

```text
1. 从 M7 的 receive virtqueue 取出 Linux 放进来的 buffer。
2. 读取 rpmsg header。
3. 根据 hdr.dst 查找 M7 endpoint。
4. 调用 endpoint 的 rx_cb。
5. 释放或归还 buffer。
```

关键逻辑：

```c
rpmsg_msg = rpmsg_lite_dev->vq_ops->vq_rx(...);
node = rpmsg_lite_get_endpoint_from_addr(rpmsg_lite_dev, rpmsg_msg->hdr.dst);
ept = node->data;
ept->rx_cb(rpmsg_msg->data, rpmsg_msg->hdr.len, rpmsg_msg->hdr.src, ept->rx_cb_data);
```

你的 M7 endpoint 是：

```text
addr = 30
```

Linux 发包时：

```text
dst = 30
```

所以能找到你的回调：

```text
robobase_rpmsg_rx_cb()
```

---

## 30. 你的 M7 echo 回调做了什么

文件：

```text
robobase_m7_rpmsg_tty_echo.c
```

回调：

```c
static int32_t robobase_rpmsg_rx_cb(void *payload,
                                    uint32_t payload_len,
                                    uint32_t src,
                                    void *priv)
```

它做：

```text
1. 检查 payload 是否为空。
2. 限制最大 copy 长度。
3. 把 payload 复制到 s_rx_buf。
4. 保存 src 到 s_rx_src。
5. 保存长度到 s_rx_len。
6. 设置 s_rx_pending = 1。
7. 返回 RL_RELEASE，让 RPMsg-Lite 释放接收 buffer。
```

重点是：

```c
s_rx_src = src;
```

这个 `src` 是 Linux 端 endpoint 地址，通常是：

```text
0x400
```

M7 后面 echo 的时候要发回这个地址。

M7 主循环：

```c
for (;;) {
    if (s_rx_pending == 0U) {
        __WFI();
        continue;
    }

    len = s_rx_len;
    dst = s_rx_src;
    memcpy(s_tx_buf, s_rx_buf, len);
    s_rx_pending = 0U;

    rpmsg_lite_send(rpmsg, ept, dst, (char *)s_tx_buf, len, RL_BLOCK);
}
```

所以它就是一个 echo firmware：

```text
收到什么，就发回给原来的 Linux endpoint。
```

---

## 31. M7 如何把 echo 发回 Linux

M7 调用：

```c
rpmsg_lite_send(rpmsg, ept, dst, s_tx_buf, len, RL_BLOCK)
```

文件：

```text
rpmsg-lite-minimal/rpmsg-lite/lib/rpmsg_lite/rpmsg_lite.c
```

`rpmsg_lite_send()` 只是检查长度后调用：

```c
rpmsg_lite_format_message()
```

`rpmsg_lite_format_message()` 做：

```c
buffer = rpmsg_lite_dev->vq_ops->vq_tx_alloc(...);
rpmsg_msg->hdr.dst = dst;
rpmsg_msg->hdr.src = src;
rpmsg_msg->hdr.len = size;
rpmsg_msg->hdr.flags = flags;
memcpy(rpmsg_msg->data, data, size);
rpmsg_lite_dev->vq_ops->vq_tx(...);
virtqueue_kick(rpmsg_lite_dev->tvq);
```

你的 echo 回包大概是：

```text
src = 0x1e
dst = 0x400
payload = robobase-test\n
```

M7 的 `virtqueue_kick()` 最终调用：

```text
rpmsg_platform.c
```

```c
platform_notify()
```

里面：

```c
uint32_t msg = vector_id << 16;
MU_SendMsg(MUB, RPMSG_MU_CHANNEL, msg);
```

这表示 M7 通过 MU mailbox 通知 Linux：

```text
我往共享内存队列里放了新消息。
```

---

## 32. Linux 如何收到 M7 回包

M7 用 MU 通知 Linux 后，Linux 侧进入 i.MX remoteproc 的 mailbox callback。

文件：

```text
drivers/remoteproc/imx_rproc.c
```

函数：

```c
imx_rproc_rx_callback()
```

它做：

```c
schedule_delayed_work(&(priv->rproc_work), 0);
```

work 函数：

```c
imx_rproc_vq_work()
```

这个函数调用：

```c
rproc_vq_interrupt(priv->rproc, 0);
rproc_vq_interrupt(priv->rproc, 1);
rproc_vq_interrupt(priv->rproc, 2);
rproc_vq_interrupt(priv->rproc, 3);
```

当前 i.MX 驱动没有只检查一个精确 vqid，而是把几个可能的队列都扫一遍。

`rproc_vq_interrupt()` 在：

```text
drivers/remoteproc/remoteproc_virtio.c
```

它做：

```c
rvring = idr_find(&rproc->notifyids, notifyid);
return vring_interrupt(0, rvring->vq);
```

然后进入 virtio ring 的回调。对 RPMsg 来说，就是：

```text
drivers/rpmsg/virtio_rpmsg_bus.c
```

```c
rpmsg_recv_done()
```

---

## 33. Linux `rpmsg_recv_done()` 如何找到 tty callback

文件：

```text
drivers/rpmsg/virtio_rpmsg_bus.c
```

函数：

```c
rpmsg_recv_done()
```

它从 virtqueue 取 M7 放回来的 buffer：

```c
msg = virtqueue_get_buf(rvq, &len);
```

然后逐个处理：

```c
rpmsg_recv_single(vrp, dev, msg, len);
```

`rpmsg_recv_single()` 最关键的是：

```c
ept = idr_find(&vrp->endpoints, msg->dst);
```

M7 回包时：

```text
msg->dst = 0x400
```

所以 Linux 找到本地 endpoint `0x400`。

这个 endpoint 是 `imx_rpmsg_tty` probe 时创建的，并且绑定了 callback：

```text
rpmsg_tty_cb()
```

所以后面调用：

```c
ept->cb(ept->rpdev, msg->data, msg_len, ept->priv, msg->src);
```

实际就是：

```text
rpmsg_tty_cb()
```

---

## 34. `rpmsg_tty_cb()` 如何让 `cat` 看到数据

文件：

```text
drivers/rpmsg/imx_rpmsg_tty.c
```

函数：

```c
rpmsg_tty_cb()
```

它做：

```c
space = tty_prepare_flip_string(&cport->port, &cbuf, len);
memcpy(cbuf, data, len);
tty_flip_buffer_push(&cport->port);
```

这几句是 Linux tty 子系统的典型接收路径。

可以这样理解：

```text
tty_prepare_flip_string()
    向 tty 层申请一块接收缓冲。

memcpy()
    把 RPMsg payload 塞进 tty 缓冲。

tty_flip_buffer_push()
    告诉 tty 层有新数据，可以唤醒读这个 tty 的用户进程。
```

所以用户态：

```bash
cat /dev/ttyRPMSG30
```

会读到 M7 echo 回来的：

```text
robobase-test
```

---

## 35. MU mailbox 和 RPMsg 的区别

这两个很容易混。

MU mailbox：

```text
硬件通知机制。
负责让 A53 和 M7 互相产生中断。
传输数据很少，通常只传 notify id。
```

RPMsg：

```text
软件消息协议。
负责定义 src/dst/len/payload。
真正 payload 在共享内存 buffer 中。
```

virtqueue/vring：

```text
共享内存队列机制。
负责管理哪些 buffer 可用、哪些 buffer 已用。
```

三者关系：

```text
RPMsg 把消息写进共享内存 buffer。
virtqueue/vring 管理 buffer 所有权。
MU mailbox 通知对方去看 virtqueue。
```

不要把 MU 理解成“数据通道”。在这个链路里，MU 更像门铃。

---

## 36. 结合当前 echo 流程完整串起来

用户态发送：

```bash
printf 'robobase-test\n' > /dev/ttyRPMSG30
```

Linux 发送路径：

```text
/dev/ttyRPMSG30
-> rpmsgtty_write()
-> rpmsg_send()
-> virtio_rpmsg_send()
-> rpmsg_send_offchannel_raw()
-> 填 rpmsg_hdr: src=0x400 dst=0x1e
-> virtqueue_add_outbuf()
-> virtqueue_kick()
-> rproc_virtio_notify()
-> imx_rproc_kick()
-> mbox_send_message()
-> MU interrupt to M7
```

M7 接收并回包：

```text
MU1_M7_IRQHandler()
-> env_isr()
-> virtqueue_notification()
-> rpmsg_lite_rx_callback()
-> robobase_rpmsg_rx_cb()
-> 保存 payload 和 src=0x400
-> main loop 发现 s_rx_pending
-> rpmsg_lite_send(dst=0x400)
-> 填 rpmsg header: src=0x1e dst=0x400
-> virtqueue_kick()
-> platform_notify()
-> MU interrupt to Linux
```

Linux 接收路径：

```text
imx_rproc_rx_callback()
-> schedule_delayed_work()
-> imx_rproc_vq_work()
-> rproc_vq_interrupt()
-> vring_interrupt()
-> rpmsg_recv_done()
-> rpmsg_recv_single()
-> idr_find(endpoint 0x400)
-> rpmsg_tty_cb()
-> tty_prepare_flip_string()
-> tty_flip_buffer_push()
-> cat /dev/ttyRPMSG30 读到数据
```

---

## 37. 为什么 `/dev/ttyRPMSG30` 是 30，不是 0

M7 代码里写死了本地 endpoint：

```c
#define ROBOBASE_RPMSG_LOCAL_EPT_ADDR (30U)
```

M7 announce 时告诉 Linux：

```text
我的 endpoint 地址是 30。
```

Linux `imx_rpmsg_tty` 创建 tty 名字时使用：

```c
"ttyRPMSG%d", rpdev->dst
```

此时：

```text
rpdev->dst = 30
```

所以设备名就是：

```text
/dev/ttyRPMSG30
```

如果你把 M7 endpoint 改成 42，并且 channel 仍然被 tty driver 匹配，那么理论上会出现：

```text
/dev/ttyRPMSG42
```

---

## 38. 为什么 Linux endpoint 是 0x400

`rpmsg_core.c` 在 probe rpmsg driver 时会创建 endpoint：

```c
rpmsg_create_ept(rpdev, rpdrv->callback, NULL, chinfo);
```

如果 `chinfo.src = RPMSG_ADDR_ANY`，底层会自动分配一个本地地址。

`virtio_rpmsg_bus.c` 里：

```c
if (addr == RPMSG_ADDR_ANY) {
    id_min = RPMSG_RESERVED_ADDRESSES;
    id_max = 0;
}

id = idr_alloc(&vrp->endpoints, ept, id_min, id_max, GFP_KERNEL);
ept->addr = id;
```

`RPMSG_RESERVED_ADDRESSES` 之前的地址保留给 name service 等系统用途。普通业务 endpoint 从保留区之后开始分配。

所以你看到：

```text
new channel: 0x400 -> 0x1e
```

代表：

```text
Linux 本地 endpoint = 0x400
M7 远端 endpoint = 0x1e
```

---

## 39. 当前调试最有用的命令

看 remoteproc 状态：

```bash
R=/sys/class/remoteproc/remoteproc0
cat "$R/name"
cat "$R/firmware"
cat "$R/state"
```

看 dmesg：

```bash
dmesg | grep -Ei 'remoteproc|imx-rproc|virtio_rpmsg|rpmsg|ttyRPMSG' | tail -160
```

看 RPMsg bus：

```bash
find /sys/bus/rpmsg -maxdepth 3 -type f -o -type l
```

看每个 rpmsg device：

```bash
for d in /sys/bus/rpmsg/devices/*; do
    echo "== $d =="
    [ -e "$d/name" ] && cat "$d/name"
    [ -e "$d/src" ] && cat "$d/src"
    [ -e "$d/dst" ] && cat "$d/dst"
    readlink "$d/driver" 2>/dev/null
done
```

看 tty：

```bash
ls -l /dev | grep -Ei 'rpmsg|ttyRPMSG'
```

启动固件：

```bash
R=/sys/class/remoteproc/remoteproc0
echo stop > "$R/state" 2>/dev/null || true
echo robobase_m7_rpmsg_tty_echo.elf > "$R/firmware"
echo start > "$R/state"
```

测试 echo：

```bash
TTY=/dev/ttyRPMSG30
stty -F "$TTY" raw -echo
cat "$TTY" &
CATPID=$!
printf 'robobase-test\n' > "$TTY"
sleep 1
kill "$CATPID" 2>/dev/null || true
```

如果能看到：

```text
robobase-test
```

说明：

```text
A53 -> M7 -> A53 双向 RPMsg 通信闭环成功。
```

---

## 40. 怎么在 VSCode 里按本文继续读源码

建议从 kernel-source 根目录打开 VSCode：

```bash
cd /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source
code .
```

如果跳转不准，先安装 ctags：

```bash
sudo apt install universal-ctags
make ARCH=arm64 tags
```

但对内核源码，最可靠的阅读方式仍然是：

```bash
rg -n "function_name"
```

例如：

```bash
rg -n "rproc_boot"
rg -n "rproc_fw_boot"
rg -n "imx_rproc_start"
rg -n "rproc_handle_vdev"
rg -n "rproc_add_virtio_dev"
rg -n "rpmsg_probe"
rg -n "rpmsg_send_offchannel_raw"
rg -n "rpmsg_recv_done"
```

M7 侧：

```bash
cd /home/compile/workstation/project/codex/myplatform
rg -n "robobase_rpmsg_rx_cb|rpmsg_lite_send|rpmsg_ns_announce|platform_notify|MU1_M7_IRQHandler" third_party/m7
```

---

## 41. 建议的阅读顺序

如果你是第一次系统看这套代码，建议不要从 `virtqueue.c` 开始。那会太底层。

第一轮只看主线：

```text
1. remoteproc_sysfs.c
    看 echo start 怎么进入 rproc_boot。

2. remoteproc_core.c
    看 rproc_boot、rproc_fw_boot、rproc_start。

3. imx_rproc.c
    看 rproc_ops、imx_rproc_start、imx_rproc_da_to_va、imx_rproc_kick。

4. robobase_m7_rsc_table.c
    看 M7 如何声明 RSC_VDEV。

5. remoteproc_core.c
    看 rproc_handle_vdev。

6. remoteproc_virtio.c
    看 rproc_add_virtio_dev。

7. virtio_rpmsg_bus.c
    看 rpmsg_probe、rpmsg_send_offchannel_raw、rpmsg_recv_done。

8. rpmsg_ns.c
    看 channel announce 怎么创建 rpmsg_device。

9. imx_rpmsg_tty.c
    看 ttyRPMSG30 怎么创建，write/callback 怎么走。

10. M7 rpmsg_lite.c 和 rpmsg_platform.c
    看 M7 如何接收、发送和 MU 通知。
```

第二轮再看数据结构：

```text
struct rproc
struct rproc_ops
struct fw_rsc_vdev
struct fw_rsc_vdev_vring
struct rpmsg_hdr
struct rpmsg_device
struct rpmsg_endpoint
struct virtproc_info
struct virtqueue
```

第三轮再看细节：

```text
virtqueue_add_outbuf()
virtqueue_get_buf()
vring_interrupt()
idr_alloc()
idr_find()
mailbox controller driver
cache coherency
reserved-memory / dma coherent memory
```

---

## 42. 常见误区

误区 1：

```text
ELF firmware 就一定是 bare-metal。
```

不对。ELF 只是文件格式。bare-metal、FreeRTOS、Zephyr firmware 都可以是 ELF。当前 `robobase_m7_rpmsg_tty_echo.elf` 是 bare-metal，是因为它使用 `rpmsg_env_bm.c`，没有 RTOS scheduler。

误区 2：

```text
MU mailbox 负责传输 RPMsg 数据。
```

不对。数据在共享内存。MU 只是通知。

误区 3：

```text
remoteproc 只要启动 M7 就完成了 RPMsg。
```

不对。remoteproc 负责启动和注册 virtio 设备。RPMsg 通信还需要 resource table、virtio_rpmsg_bus、M7 RPMsg-Lite、name service、具体 rpmsg driver 全部配合。

误区 4：

```text
看到 rpmsg_ctrl0 就说明业务 RPMsg 已经通了。
```

不完整。`rpmsg_ctrl0` 只能说明 RPMsg control device 出来了。业务通信还要看到具体 channel，比如 `rpmsg-virtual-tty-channel-1`，以及 `/dev/ttyRPMSG30`。

误区 5：

```text
看到 virtio0 就一定能收发业务数据。
```

不一定。`virtio0` 只是 RPMsg transport 出来了。还需要 M7 announce channel，并且 Linux 有 driver 匹配这个 channel。

---

## 43. 当前项目的结论

截至当前，项目已经完成：

```text
1. Linux remoteproc 能加载 M7 ELF。
2. i.MX8MP CM7 TCM clock 问题已经修复。
3. CM7 能从 remoteproc 成功启动。
4. M7 resource table 能声明 VIRTIO_ID_RPMSG。
5. Linux 能注册 virtio0 type 7。
6. virtio_rpmsg_bus 能上线。
7. M7 能 announce rpmsg-virtual-tty-channel-1。
8. imx_rpmsg_tty 能匹配 channel 并创建 /dev/ttyRPMSG30。
9. A53 写 ttyRPMSG30，M7 能收到。
10. M7 echo 回来，A53 能通过 ttyRPMSG30 读到。
```

也就是说，当前最小链路已经打通：

```text
Linux userspace
-> ttyRPMSG30
-> imx_rpmsg_tty
-> rpmsg core
-> virtio_rpmsg_bus
-> remoteproc virtio
-> imx_rproc MU kick
-> M7 RPMsg-Lite
-> M7 echo
-> MU kick
-> Linux rpmsg_recv_done
-> ttyRPMSG30
-> Linux userspace
```

后续可以在这个最小稳定基线上继续做：

```text
1. 定义 RoboBase 自己的 RPMsg 协议。
2. 替换 tty echo 为结构化 command/response。
3. 在 Linux 用户态写 robobase-rpmsg-test 工具。
4. 在 M7 侧接入真实传感器、PWM、GPIO 或控制环。
5. 做错误恢复和 remoteproc stop/start 稳定性测试。
```
