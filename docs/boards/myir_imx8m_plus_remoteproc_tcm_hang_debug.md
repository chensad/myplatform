# MYIR i.MX8MP CM7 Remoteproc TCM 卡死 Debug 复盘

本文记录 MYIR MYD-JX8MP 上调试 CM7 `remoteproc` 时遇到的卡死问题，以及从现象、假设、验证到最终结论的完整过程。

适用对象：

```text
Board: MYIR MYD-JX8MP
SoC: NXP i.MX8M Plus
Linux: NXP linux-imx 5.10.72
Yocto MACHINE: myd-jx8mp
Remote core: Cortex-M7 / CM7
Remoteproc driver: imx-rproc
```

相关工程路径：

```text
/home/compile/workstation/project/codex/myplatform
```

相关文件：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-kernel/linux/linux-imx_%.bbappend
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-kernel/linux/files/0001-myir-imx8mp-enable-cm7-remoteproc.patch
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-kernel/linux/files/0002-remoteproc-add-robobase-cm7-boot-debug-logs.patch
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only
```

调试日期：

```text
2026-04-29
```

---

## 1. 问题背景

当前项目需要在 i.MX8M Plus 上跑 A53 Linux，同时使用 CM7 作为实时控制核。目标是先打通 Linux `remoteproc` 启动 CM7，再进一步调通 `rpmsg` 通信。

前期已经完成：

```text
1. Yocto 构建环境可用。
2. 自定义 meta-robobase layer 已加入构建。
3. 自定义 robobase-image 已能构建和烧录。
4. 设备树补丁已加入 imx8mp-cm7 remoteproc 节点。
5. Linux 启动后能看到 /sys/class/remoteproc/remoteproc0。
6. /lib/firmware 下已经放入 M7 固件。
```

Linux 侧 remoteproc 状态：

```bash
for r in /sys/class/remoteproc/remoteproc*; do
    echo "$r"
    cat "$r/name"
    cat "$r/state"
done
```

当时输出：

```text
/sys/class/remoteproc/remoteproc0
imx-rproc
offline

/sys/class/remoteproc/remoteproc1
imx-dsp-rproc
offline
```

`remoteproc0` 是 CM7，`remoteproc1` 是 DSP。本文只讨论 `remoteproc0`。

---

## 2. 初始现象

在 Linux 下启动 CM7 固件：

```bash
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_boot_only_wfi.elf > "$R/firmware"
echo start > "$R/state"
```

现象：

```text
1. 串口卡死，无法继续输入。
2. SSH 也卡死或断开。
3. 系统不像普通进程阻塞，而是 A53 Linux 整体失去响应。
```

早期测试 NXP/MYIR 提供的 demo 固件也有类似现象：

```text
imx8mp_m7_TCM_hello_world.elf
imx8mp_m7_TCM_rpmsg_lite_pingpong_rtos_linux_remote.elf
imx8mp_m7_TCM_rpmsg_lite_str_echo_rtos.elf
```

这些固件启动后也会导致串口或 SSH 卡死。因此最初怀疑方向包括：

```text
1. M7 固件初始化了 Linux 正在使用的外设。
2. M7 固件改了 clock、RDC、pinmux，影响 A53 Linux。
3. M7 rpmsg resource table 配置不正确。
4. remoteproc 设备树 memory-region 配置不正确。
5. Linux imx-rproc 驱动加载固件时访问了错误地址。
6. CM7 TCM 在 Linux 阶段不可访问。
```

---

## 3. 设备树和内核补丁基线

### 3.1 CM7 remoteproc 设备树节点

在 `myd-jx8mp-base.dts` 中新增 CM7 remoteproc 节点：

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

注意：

```text
1. compatible = "fsl,imx8mp-cm7" 会匹配 imx-rproc 驱动。
2. clocks = <&clk IMX8MP_CLK_M7_CORE> 声明 `imx-rproc` 需要持有 i.MX8MP clock driver 中真实注册的 `m7_core`。
3. mboxes 连接 MU mailbox，用于 remoteproc/rpmsg 通知。
4. memory-region 指向 rpmsg vring、vdev buffer 和 resource table。
5. rsc-da 在当前 linux-imx 5.10.72 的 imx_rproc.c 中没有实际被使用。
```

### 3.2 reserved-memory

在 `myd-jx8mp.dtsi` 中增加了 reserved memory：

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

rsc_table: rsc-table@550ff000 {
	reg = <0 0x550ff000 0 0x1000>;
	no-map;
};
```

这些地址主要服务 rpmsg：

```text
0x55000000: vring0
0x55008000: vring1
0x550ff000: resource table
0x55400000: rpmsg vdev buffer
```

本次卡死后来证明不发生在这些 DDR reserved memory 上，而是发生在 CM7 ITCM：

```text
0x007e0000
```

---

## 4. 为什么先做极简 M7 固件

为了排除 M7 demo 固件初始化外设导致 Linux 卡死，基于 NXP SDK 的 `hello_world` 工程复制了一个极简工程：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only
```

核心 `main()`：

```c
int main(void)
{
    while (1)
    {
        __asm volatile("wfi");
    }
}
```

这个固件刻意去掉：

```text
1. BOARD_InitBootPins()
2. BOARD_InitBootClocks()
3. BOARD_InitDebugConsole()
4. UART/printf
5. rpmsg-lite
6. FreeRTOS
7. 外设初始化
```

目的：

```text
只验证 Linux 能不能把固件加载到 CM7 TCM，并让 CM7 进入 WFI。
```

构建产物：

```text
armgcc/debug/robobase_m7_boot_only.elf
armgcc/debug/robobase_m7_boot_only_wfi.elf
armgcc/debug/robobase_m7_boot_only.bin
```

其中：

```text
.elf: 给 Linux remoteproc 使用，包含 ELF header、program header、符号和段信息。
.bin: 给 U-Boot 裸拷贝到 ITCM 使用，只包含实际机器码和数据。
```

`.bin` 只有约 3KB 是正常的，因为它没有调试符号和 SDK 大量功能代码。

检查 `.bin` 前 32 字节：

```bash
xxd -g 4 -l 32 robobase_m7_boot_only.bin
```

输出：

```text
00000000: 00000220 c5040000 55050000 59050000  ... ....U...Y...
00000010: 51050000 51050000 51050000 00000000  Q...Q...Q.......
```

按 Cortex-M 小端格式解释：

```text
0x20020000: 初始栈顶地址
0x000004c5: reset handler 入口地址
```

这说明 `.bin` 的向量表是合理的。

---

## 5. 增加 remoteproc 内核调试日志

为了定位到底卡在哪一步，给 linux-imx 增加了调试补丁：

```text
0002-remoteproc-add-robobase-cm7-boot-debug-logs.patch
```

补丁覆盖两个文件：

```text
drivers/remoteproc/remoteproc_core.c
drivers/remoteproc/imx_rproc.c
```

主要增加日志点：

```text
1. rproc_fw_boot()
2. rproc_start()
3. rproc_load_segments()
4. imx_rproc_da_to_va()
5. imx_rproc_memcpy()
6. imx_rproc_memset()
7. imx_rproc_start()
8. SMC M4_START 前后
```

关键目标：

```text
1. 确认卡死是在解析 ELF 阶段、加载段阶段、resource table 阶段，还是真正启动 M7 阶段。
2. 打印 remoteproc 把 M7 device address 映射到哪个 A53 system physical address。
3. 打印每次 memcpy_toio()/memset_io() 的开始和结束。
```

---

## 6. 第一次关键定位：卡在写 CM7 ITCM

未加 `clk_ignore_unused` 时，在 Linux 下启动极简 WFI 固件：

```bash
echo 8 > /proc/sys/kernel/printk
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_boot_only_wfi.elf > "$R/firmware"
echo start > "$R/state"
```

关键日志：

```text
[   67.717977] remoteproc remoteproc0: powering up imx-rproc
[   67.726476] remoteproc remoteproc0: robobase debug: fw_boot: sanity_check ret=0
[   67.733813] remoteproc remoteproc0: Booting fw image robobase_m7_boot_only_wfi.elf, size 158272
[   67.742548] remoteproc remoteproc0: robobase debug: fw_boot: enable_iommu begin
[   67.749887] remoteproc remoteproc0: robobase debug: fw_boot: enable_iommu done ret=0
[   67.757651] remoteproc remoteproc0: robobase debug: fw_boot: prepare_device begin
[   67.765166] remoteproc remoteproc0: robobase debug: fw_boot: prepare_device done ret=0
[   67.773108] remoteproc remoteproc0: robobase debug: fw_boot: bootaddr=0x4c5
[   67.780089] remoteproc remoteproc0: robobase debug: fw_boot: parse_fw begin
[   67.787090] remoteproc remoteproc0: robobase debug: da_to_va da=0x550ff000 len=0x400 sys=0x550ff000 va=...
[   67.797892] remoteproc remoteproc0: robobase debug: fw_boot: parse_fw done ret=0
[   67.805316] remoteproc remoteproc0: robobase debug: fw_boot: handle_resources begin
[   67.813046] remoteproc remoteproc0: robobase debug: fw_boot: handle_resources done ret=0
[   67.821166] remoteproc remoteproc0: robobase debug: fw_boot: alloc_carveouts begin
[   67.828773] remoteproc remoteproc0: robobase debug: fw_boot: alloc_carveouts done ret=0
[   67.836824] remoteproc remoteproc0: robobase debug: fw_boot: rproc_start begin
[   67.844067] remoteproc remoteproc0: robobase debug: rproc_start: load_segments begin
[   67.851838] remoteproc remoteproc0: robobase debug: da_to_va da=0x0 len=0x2a8 sys=0x7e0000 va=...
[   67.861870] remoteproc remoteproc0: robobase debug: elf_memcpy begin dest=... src=... count=0x2a8
```

卡死点非常明确：

```text
没有打印 elf_memcpy done。
```

因此内核卡在：

```text
imx_rproc_memcpy()
  -> memcpy_toio(dest, src, count)
```

这次 memcpy 的目的地址来自：

```text
M7 device address: 0x00000000
A53 system physical address: 0x007e0000
```

也就是 CM7 ITCM。

### 6.1 这个结论排除了什么

这个日志说明卡死发生在：

```text
rproc_start()
  -> rproc_load_segments()
     -> imx_rproc_memcpy()
```

还没有执行到：

```text
imx_rproc_start()
  -> SMC M4_START
```

所以可以排除：

```text
1. 不是 M7 main() 里的代码导致卡死。
2. 不是 M7 初始化外设导致卡死。
3. 不是 rpmsg 通信导致卡死。
4. 不是 MU mailbox 通知导致卡死。
5. 不是 SMC 启动 M7 后 M7 抢占外设导致卡死。
```

当时真正的问题是：

```text
Linux A53 在写 CM7 ITCM 时发生总线级卡死。
```

### 6.2 为什么不能继续用 Linux devmem 测试

理论上可以用 `devmem 0x007e0000` 测试 A53 是否能访问 TCM，但当前日志已经证明 Linux 写 ITCM 会卡死。

因此不建议在 Linux 下再执行：

```bash
devmem 0x007e0000
```

原因：

```text
这很可能再次导致整机卡死，需要硬件复位。
```

---

## 7. U-Boot 验证：TCM 硬件本身可写

为了区分“TCM 硬件完全不可访问”和“Linux 启动后某些资源被关掉”，进入 U-Boot 测试。

### 7.1 确认 bootaux 存在

U-Boot 命令：

```bash
help bootaux
```

输出：

```text
bootaux - Start auxiliary core

Usage:
bootaux <address> [<core>]
   - start auxiliary core [<core>] (default 0),
     at address <address>
```

说明当前 U-Boot 支持启动辅助核。

本地 U-Boot 源码中 `bootaux` 位于：

```text
third_party/uboot/imx-uboot2017.03/arch/arm/imx-common/imx_bootaux.c
```

i.MX8M 平台实现位于：

```text
third_party/uboot/imx-uboot2017.03/arch/arm/cpu/armv8/imx8m/soc.c
```

关键逻辑：

```c
stack = *(u32 *)boot_private_data;
pc = *(u32 *)(boot_private_data + 4);

/* Set the stack and pc to M4 bootROM */
writel(stack, M4_BOOTROM_BASE_ADDR);
writel(pc, M4_BOOTROM_BASE_ADDR + 4);

/* Enable M4 */
call_imx_sip(FSL_SIP_SRC, FSL_SIP_SRC_M4_START, 0, 0, 0);
```

这里虽然名字叫 M4，但在 i.MX8MP 上对应 CM7 启动路径。

`M4_BOOTROM_BASE_ADDR` 在 i.MX8M U-Boot 中定义为：

```c
#define M4_BOOTROM_BASE_ADDR 0x007E0000
```

### 7.2 U-Boot 下直接读写 ITCM

U-Boot 命令：

```bash
md.l 0x007e0000 4
mw.l 0x007e0000 0x11223344 1
md.l 0x007e0000 1
```

实际输出：

```text
u-boot=> md.l 0x007e0000 4
007e0000: 5c0c1768 be2f645e 9bac63ed 0494b5f5    h..\^d/..c......

u-boot=> mw.l 0x007e0000 0x11223344 1

u-boot=> md.l 0x007e0000 1
007e0000: 11223344                               D3".
```

结论：

```text
U-Boot 阶段 A53 可以读写 0x007e0000。
```

这排除了：

```text
CM7 ITCM 物理地址完全错误
CM7 ITCM 硬件完全不可访问
```

补充说明：

```text
md.l 后如果继续按回车，U-Boot 会继续显示后续地址内容。
这不是异常，也不是板子自动输出。
```

---

## 8. U-Boot 验证：bootaux 能启动 CM7

### 8.1 网络加载固件

U-Boot 环境：

```bash
setenv loadaddr 0x40480000
setenv ipaddr 192.168.1.8
setenv serverip 192.168.1.3
```

开始 `ping` 失败：

```text
ping failed; host 192.168.1.3 is not alive
```

但后续 TFTP 成功：

```bash
tftpboot ${loadaddr} robobase_m7_boot_only.bin
```

输出：

```text
Using ethernet@30bf0000 device
TFTP from server 192.168.1.3; our IP address is 192.168.1.8
Filename 'robobase_m7_boot_only.bin'.
Load address: 0x40480000
Loading: #
         239.3 KiB/s
done
Bytes transferred = 2948 (b84 hex)
```

说明：

```text
U-Boot ping 失败不一定代表 TFTP 不通。
可能是 PC 防火墙拦了 ICMP，但 UDP 69/TFTP 放行了。
实际以 tftpboot 能否成功为准。
```

### 8.2 拷贝 bin 到 ITCM

U-Boot 命令：

```bash
cp.b ${loadaddr} 0x007e0000 ${filesize}
dcache flush
md.l 0x007e0000 4
```

输出：

```text
007e0000: 20020000 000004c5 00000555 00000559    ... ....U...Y...
```

向量表解释：

```text
0x20020000: CM7 初始栈顶
0x000004c5: CM7 reset handler
0x00000555: NMI handler 或后续异常向量
0x00000559: HardFault handler 或后续异常向量
```

这个结果与 Linux remoteproc 解析 ELF 时打印的 `bootaddr=0x4c5` 一致。

### 8.3 bootaux 启动

U-Boot 命令：

```bash
bootaux 0x007e0000
```

输出：

```text
## Starting auxiliary core stack = 0x20020000, pc = 0x000004C5...
```

再次执行：

```bash
bootaux 0x007e0000
```

输出：

```text
## Auxiliary core is already up
```

结论：

```text
1. U-Boot 可以批量写 CM7 ITCM。
2. U-Boot 可以通过 ATF/SMC 启动 CM7。
3. ATF 的 FSL_SIP_SRC_M4_START 路径可用。
4. 极简 M7 boot-only 固件本身可以被启动。
```

这进一步说明：

```text
问题不是硬件 TCM 本身不可访问。
问题不是 ATF 完全不支持 CM7 start。
问题不是 boot-only 固件格式错误。
问题更可能发生在 Linux 启动后某些 clock/power/security 状态变化。
```

---

## 9. Linux 启动参数验证：clk_ignore_unused

### 9.1 假设

Linux 启动过程中会关闭一些“内核认为没有驱动使用”的 clock。

remoteproc 设备树最初只声明了：

```dts
clocks = <&clk IMX8MP_CLK_M7_DIV>;
```

进一步查 linux-imx 5.10.72 的 `drivers/clk/imx/clk-imx8mp.c` 后发现，当前 clock driver 真实注册的 CM7 core clock 是：

```c
hws[IMX8MP_CLK_M7_CORE] = imx8m_clk_hw_composite_core("m7_core", ...);
```

而 `IMX8MP_CLK_M7_DIV` 是旧的 dt-binding ID，在当前 `clk-imx8mp.c` 中没有对应的 real clock 注册。`imx-rproc` 使用 `devm_clk_get_optional(dev, NULL)` 获取默认 clock，如果 DTS 里给的是未注册的 clock ID，驱动很可能等价于没有真正持有和 enable `m7_core`。这样 Linux late init 关闭 unused clocks 后，`m7_core` gate 被关掉，后续 A53 写 CM7 ITCM 就会卡死。

如果 Linux 把相关 clock 关闭，后续 `imx_rproc` 写 `0x007e0000` 时可能导致总线挂死。

调试验证方式：

```text
给 Linux 加启动参数 clk_ignore_unused。
```

这个参数的作用：

```text
让 Linux clock framework 不要在启动后关闭 unused clocks。
```

它不是最终修复方案，只是定位问题的调试手段。

### 9.2 第一次设置没有生效

进入 Linux 后查看：

```bash
cat /proc/cmdline
```

输出：

```text
console=ttymxc1,115200 root=/dev/mmcblk2p2 rootwait rw
```

没有 `clk_ignore_unused`，说明 U-Boot 设置没有传进 Linux。

### 9.3 找到 U-Boot bootargs 生成方式

U-Boot 中查看环境：

```bash
printenv bootargs
printenv bootcmd
printenv mmcargs
```

输出：

```text
u-boot=> printenv bootargs
## Error: "bootargs" not defined

u-boot=> printenv bootcmd
bootcmd=mmc dev ${mmcdev}; if mmc rescan; then if run loadbootscript; then run bootscript; else if run loadimage; then run mmcboot; else run netboot; fi; fi; fi;

u-boot=> printenv mmcargs
mmcargs=setenv bootargs ${jh_clk} console=${console} root=${mmcroot}
```

说明：

```text
bootargs 不是长期保存的变量。
每次启动时由 mmcargs 动态生成。
```

因此需要修改 `mmcargs`：

```bash
setenv mmcargs 'setenv bootargs ${jh_clk} console=${console} root=${mmcroot} clk_ignore_unused'
run mmcargs
printenv bootargs
boot
```

注意：

```text
这里没有 saveenv，是临时验证。
确认有效前不要固化。
```

### 9.4 确认参数生效

Linux 启动后：

```bash
cat /proc/cmdline
```

输出：

```text
console=ttymxc1,115200 root=/dev/mmcblk2p2 rootwait rw clk_ignore_unused
```

说明 `clk_ignore_unused` 已经成功传入 Linux。

---

## 10. 最终关键验证：remoteproc 启动成功

在带 `clk_ignore_unused` 的 Linux 下重新启动 CM7：

```bash
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_boot_only_wfi.elf > "$R/firmware"
echo start > "$R/state"
```

完整关键日志：

```text
[   53.862202] remoteproc remoteproc0: powering up imx-rproc
[   53.870697] remoteproc remoteproc0: robobase debug: fw_boot: sanity_check ret=0
[   53.878104] remoteproc remoteproc0: Booting fw image robobase_m7_boot_only_wfi.elf, size 158272
[   53.886854] remoteproc remoteproc0: robobase debug: fw_boot: enable_iommu begin
[   53.894207] remoteproc remoteproc0: robobase debug: fw_boot: enable_iommu done ret=0
[   53.902016] remoteproc remoteproc0: robobase debug: fw_boot: prepare_device begin
[   53.909599] remoteproc remoteproc0: robobase debug: fw_boot: prepare_device done ret=0
[   53.917559] remoteproc remoteproc0: robobase debug: fw_boot: bootaddr=0x4c5
[   53.924574] remoteproc remoteproc0: robobase debug: fw_boot: parse_fw begin
[   53.931619] remoteproc remoteproc0: robobase debug: da_to_va da=0x550ff000 len=0x400 sys=0x550ff000 va=...
[   53.942441] remoteproc remoteproc0: robobase debug: fw_boot: parse_fw done ret=0
[   53.949874] remoteproc remoteproc0: robobase debug: fw_boot: handle_resources begin
[   53.957553] remoteproc remoteproc0: robobase debug: fw_boot: handle_resources done ret=0
[   53.965686] remoteproc remoteproc0: robobase debug: fw_boot: alloc_carveouts begin
[   53.973302] remoteproc remoteproc0: robobase debug: fw_boot: alloc_carveouts done ret=0
[   53.981349] remoteproc remoteproc0: robobase debug: fw_boot: rproc_start begin
[   53.988599] remoteproc remoteproc0: robobase debug: rproc_start: load_segments begin
[   53.996386] remoteproc remoteproc0: robobase debug: da_to_va da=0x0 len=0x2a8 sys=0x7e0000 va=...
[   54.006416] remoteproc remoteproc0: robobase debug: elf_memcpy begin dest=... src=... count=0x2a8
[   54.017585] remoteproc remoteproc0: robobase debug: elf_memcpy done count=0x2a8
[   54.024914] remoteproc remoteproc0: robobase debug: da_to_va da=0x400 len=0x724 sys=0x7e0400 va=...
[   54.035117] remoteproc remoteproc0: robobase debug: elf_memcpy begin dest=... src=... count=0x724
[   54.046274] remoteproc remoteproc0: robobase debug: elf_memcpy done count=0x724
[   54.053612] remoteproc remoteproc0: robobase debug: da_to_va da=0xb24 len=0x880 sys=0x7e0b24 va=...
[   54.063800] remoteproc remoteproc0: robobase debug: elf_memcpy begin dest=... src=... count=0x60
[   54.074859] remoteproc remoteproc0: robobase debug: elf_memcpy done count=0x60
[   54.082123] remoteproc remoteproc0: robobase debug: elf_memset begin dest=... value=0x0 count=0x820
[   54.092358] remoteproc remoteproc0: robobase debug: elf_memset done count=0x820
[   54.099683] remoteproc remoteproc0: robobase debug: rproc_start: load_segments done ret=0
[   54.107881] remoteproc remoteproc0: robobase debug: rproc_start: loaded_table=... cached_table=... table_sz=0x10
[   54.120338] remoteproc remoteproc0: robobase debug: rproc_start: resource_table copy begin
[   54.128631] remoteproc remoteproc0: robobase debug: rproc_start: resource_table copy done
[   54.136825] remoteproc remoteproc0: robobase debug: rproc_start: prepare_subdevices begin
[   54.145033] remoteproc remoteproc0: robobase debug: rproc_start: prepare_subdevices done
[   54.153180] remoteproc remoteproc0: robobase debug: rproc_start: ops->start begin
[   54.160701] imx-rproc imx8mp-cm7: robobase debug: imx_rproc_start: method=1 bootaddr=0x4c5
[   54.169002] imx-rproc imx8mp-cm7: robobase debug: imx_rproc_start: SMC M4_START begin
[   54.176867] imx-rproc imx8mp-cm7: robobase debug: imx_rproc_start: SMC M4_START done a0=0 a1=0 a2=0 a3=0
[   54.186375] imx-rproc imx8mp-cm7: robobase debug: imx_rproc_start: ready wait begin
[   54.244079] remoteproc remoteproc0: robobase debug: rproc_start: ops->start done ret=0
[   54.252015] remoteproc remoteproc0: robobase debug: rproc_start: start_subdevices begin
[   54.260029] remoteproc remoteproc0: robobase debug: rproc_start: start_subdevices done ret=0
[   54.268507] remoteproc remoteproc0: remote processor imx-rproc is now up
[   54.275238] remoteproc remoteproc0: robobase debug: fw_boot: rproc_start done ret=0
```

关键变化：

```text
之前卡在第一次 elf_memcpy begin。
现在三次 elf_memcpy 都有 done。
elf_memset 也正常 done。
SMC M4_START 成功返回。
remoteproc 状态变为 up。
```

最终验证命令：

```bash
cat /sys/class/remoteproc/remoteproc0/state
```

预期：

```text
running
```

---

## 11. 最终结论

本次卡死问题的直接原因：

```text
Linux remoteproc 在加载 CM7 ELF 时，需要把代码段写入 CM7 ITCM 0x007e0000。
正常启动时 Linux 关闭了某些 remoteproc/CM7 TCM 访问依赖的 unused clock。
这些 clock 被关掉后，A53 再写 CM7 ITCM 会触发总线级卡死。
```

证据链：

```text
1. 未加 clk_ignore_unused 时，Linux 卡在 imx_rproc_memcpy() 的 memcpy_toio()。
2. 卡死地址是 da=0x0 映射到 sys=0x007e0000，也就是 CM7 ITCM。
3. 当时还没执行 SMC M4_START，所以 M7 固件没有开始运行。
4. U-Boot 下 md.l/mw.l 能读写 0x007e0000，说明 TCM 硬件地址可访问。
5. U-Boot 下 cp.b 能批量写 0x007e0000，bootaux 能启动 CM7，说明 ATF 启动路径可用。
6. Linux 加 clk_ignore_unused 后，remoteproc 可以完整加载 ELF、执行 SMC、启动 CM7。
```

因此可以排除：

```text
1. 极简 M7 固件导致卡死。
2. rpmsg resource table 导致卡死。
3. MU mailbox 导致卡死。
4. SMC M4_START 本身不可用。
5. CM7 ITCM 物理地址完全错误。
```

当前最可信根因：

```text
Linux clock framework 在 late init 阶段关闭了某个 CM7 TCM/AHB/bus/root clock，
而 DTS/driver 没有把这个 clock 声明为 imx-rproc 的依赖。
```

---

## 12. 为什么 clk_ignore_unused 不是最终方案

`clk_ignore_unused` 可以让系统继续调试，但不适合作为产品级长期方案。

原因：

```text
1. 它会阻止 Linux 关闭所有 unused clocks，不只影响 CM7。
2. 功耗会上升。
3. 会掩盖 DTS 或驱动中缺失 clock dependency 的问题。
4. 未来更换内核、BSP 或设备树后问题可能再次出现。
```

它的正确定位：

```text
debug switch，用来证明问题属于 Linux clock/power 资源管理方向。
```

---

## 13. 最终修复：把 CM7 clock 改为 m7_core

### 13.1 缺失 clock 的最终定位

最终定位结果：

```text
remoteproc 需要持有并 enable 的关键 clock 是 m7_core。
对应 DTS binding 是 IMX8MP_CLK_M7_CORE。
```

源码依据：

```c
/* drivers/clk/imx/clk-imx8mp.c */
hws[IMX8MP_CLK_M7_CORE] =
	imx8m_clk_hw_composite_core("m7_core", imx8mp_m7_sels, ccm_base + 0x8080);
```

原先 DTS 使用的是：

```dts
clocks = <&clk IMX8MP_CLK_M7_DIV>;
```

但在当前 linux-imx 5.10.72 的 `clk-imx8mp.c` 中，没有为 `IMX8MP_CLK_M7_DIV` 注册实际 clock。`imx-rproc` probe 时通过：

```c
priv->clk = devm_clk_get_optional(dev, NULL);
clk_prepare_enable(priv->clk);
```

只会 enable DTS 给它的默认 clock。如果 DTS 给的是旧 ID，驱动就没有真正持有 `m7_core`。Linux late init 关闭 unused clocks 后，A53 再通过 remoteproc 写 CM7 ITCM `0x007e0000` 就会总线卡死。

`clk_ignore_unused` 能让 remoteproc 正常启动，正好证明卡死来自 clock 被关闭；源码进一步把具体 clock 收敛到 `m7_core`。

### 13.2 Yocto 补丁修复内容

已在 Yocto kernel DTS patch 中修正：

```text
platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-kernel/linux/files/0001-myir-imx8mp-enable-cm7-remoteproc.patch
```

修复前：

```dts
clocks = <&clk IMX8MP_CLK_M7_DIV>;
```

修复后：

```dts
clocks = <&clk IMX8MP_CLK_M7_CORE>;
```

重新编译后的 deploy DTB 反编译结果：

```dts
imx8mp-cm7 {
	compatible = "fsl,imx8mp-cm7";
	rsc-da = <0x55000000>;
	clocks = <0x02 0x131>;
	...
};
```

其中：

```text
0x131 = 305 = IMX8MP_CLK_M7_CORE
```

如果还是旧值，反编译会看到：

```text
0x55 = 85 = IMX8MP_CLK_M7_DIV
```

### 13.3 板上验证结果

把新 DTB 替换到 boot 分区后，不再使用 `clk_ignore_unused`，remoteproc 启动成功。

板上验证重点：

```bash
cat /proc/cmdline
hexdump -Cv /proc/device-tree/imx8mp-cm7/clocks
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_boot_only_wfi.elf > "$R/firmware"
echo start > "$R/state"
cat "$R/state"
```

运行中的设备树 clock cell 应为：

```text
00 00 00 02 00 00 01 31
```

其中 `00 00 01 31` 表示 `IMX8MP_CLK_M7_CORE`。

remoteproc 状态应为：

```text
running
```

这说明正式修复已经生效：

```text
不再需要 clk_ignore_unused，imx-rproc 通过 DTS 正确持有 m7_core，Linux 不会再把 CM7 core clock 当作 unused clock 关闭。
```

---

## 14. 当前推荐操作流程

### 14.1 替换新 DTB

boot 分区在当前板子上自动挂载为：

```text
/run/media/mmcblk2p1
```

替换流程：

```bash
cp /run/media/mmcblk2p1/myd-jx8mp-base.dtb \
   /run/media/mmcblk2p1/myd-jx8mp-base.dtb.bak-$(date +%Y%m%d-%H%M%S)

cp /tmp/myd-jx8mp-base.m7core.dtb \
   /run/media/mmcblk2p1/myd-jx8mp-base.dtb

sync
reboot
```

### 14.2 确认不再使用 clk_ignore_unused

重启后确认：

```bash
cat /proc/cmdline
```

正式修复后不应该依赖：

```text
clk_ignore_unused
```

### 14.3 确认运行中的 DTB 是新 clock

```bash
hexdump -Cv /proc/device-tree/imx8mp-cm7/clocks
```

预期：

```text
00 00 00 02 00 00 01 31
```

### 14.4 启动极简 M7 固件

```bash
echo 8 > /proc/sys/kernel/printk
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_boot_only_wfi.elf > "$R/firmware"
echo start > "$R/state"
cat "$R/state"
```

预期：

```text
running
```

### 14.3 停止和再次启动

```bash
echo stop > "$R/state"
cat "$R/state"
echo start > "$R/state"
cat "$R/state"
```

如果 stop/start 都正常，说明 remoteproc 基础控制链路可用。

### 14.4 回收调试日志

当前 debug patch 打印很多日志，适合 bring-up，不适合长期保留。

后续稳定后应考虑：

```text
1. 删除 0002 调试补丁。
2. 或把 dev_info 改成 dev_dbg。
3. 或只保留少量关键错误日志。
```

---

## 15. 常见误区

### 15.1 看到 `txdb` warning 不等于失败

日志：

```text
imx-rproc imx8mp-cm7: mbox_request_channel_byname() could not locate channel named "txdb"
imx-rproc imx8mp-cm7: No txdb, ret -22
```

这个不是当前卡死原因。

当前 DTS 只声明：

```dts
mbox-names = "tx", "rx", "rxdb";
```

而驱动尝试获取 `txdb` 时失败，会打印 warning。但从后续日志看，remoteproc 仍然可以进入 available 状态。

### 15.2 `.bin` 很小不是问题

`robobase_m7_boot_only.bin` 只有 2948 字节是合理的。

原因：

```text
1. 它是纯裸机镜像。
2. 没有 ELF header。
3. 没有符号表。
4. 没有调试信息。
5. 没有 printf、UART、FreeRTOS、rpmsg-lite。
```

### 15.3 U-Boot 里没有 `ls`

U-Boot 不是 Linux shell，不一定支持 `ls`。

查看 FAT 分区文件用：

```bash
fatls mmc 1:1
```

加载 FAT 分区文件用：

```bash
fatload mmc 1:1 ${loadaddr} filename.bin
```

### 15.4 `ping` 失败但 TFTP 成功并不矛盾

U-Boot `ping` 走 ICMP。

TFTP 走 UDP 69 和临时 UDP 端口。

PC 防火墙可能阻止 ICMP，但允许 TFTP，所以最终以 `tftpboot` 是否成功为准。

---

## 16. 一句话总结

本次 remoteproc 卡死不是 M7 固件跑坏了 Linux，而是 Linux 在启动后关闭了 CM7 TCM 访问所需的 clock，导致 `imx-rproc` 加载 ELF 时写 `0x007e0000` ITCM 总线卡死。U-Boot 验证证明 TCM 和 ATF 启动链路本身可用，`clk_ignore_unused` 验证证明问题属于 Linux clock 依赖缺失方向。源码进一步定位到最可疑缺失项是 `m7_core`，应把 CM7 remoteproc 节点的 clock 从旧 ID `IMX8MP_CLK_M7_DIV` 修正为当前 clock driver 真实注册的 `IMX8MP_CLK_M7_CORE`。
