# MYIR i.MX8MP M7 本地 Lease Watchdog 验证记录

本文记录 RoboBase M7 safety-v0.1 链路中的本地 watchdog、1ms 安全调度、
M7 GPIO 安全输入实现和板端验证结果。

## 背景

RoboBase 的安全链路采用 lease 模型：

```text
Linux 必须周期性向 M7 发送 LEASE。
M7 只有在 lease 未过期且本地安全条件正常时才允许 motion_enable。
如果 Linux 不再刷新 lease，M7 必须自主进入 SAFE_STOP。
```

这比“Linux 主动发送 stop 命令”更安全，因为 Linux 崩溃、进程卡死或 RPMsg
链路失效时，不能依赖故障侧继续发出 stop。

## 实现摘要

M7 固件使用 Cortex-M7 自带的 SysTick 作为本地毫秒时基：

```c
void SysTick_Handler(void)
{
    s_m7_uptime_ms++;
}
```

初始化时调用：

```c
SystemCoreClockUpdate();
SysTick_Config(SystemCoreClock / 1000U);
```

因此 SysTick 每 1ms 触发一次中断，更新 `s_m7_uptime_ms`。

每次收到 Linux `LEASE` 时，M7 记录：

```text
s_last_lease_m7_ms
s_current_lease_timeout_ms
最新 Linux/upstream/driver/power health 输入
```

SysTick 中断只做轻量计数，不在中断里跑完整安全状态机。主循环调用
`robobase_safe_process_pending_tick()` 消费待处理 tick，并在普通上下文里运行
`robobase_safe_run_1ms()`。

每个 1ms 安全 tick 会执行：

```text
采样 M7 GPIO 安全输入
检查 Linux lease watchdog
更新 safety state / motion_enable / fault bits
刷新状态快照
```

这种结构把 RPMsg 收发和 1ms 安全调度解耦，但当前仍是 bare-metal 协作式主循环。
如果后续需要更强的实时优先级，应把 RTOS 高优先级 SafetyTask 列入下一阶段。

超时条件：

```text
s_m7_uptime_ms - s_last_lease_m7_ms > s_current_lease_timeout_ms
```

超时后：

```text
state = SAFE_STOP
motion_enable = 0
fault_bits |= RB_FAULT_LINUX_TIMEOUT
```

## 查询状态

为了验证“停止刷新 lease 后 M7 自主超时”，Linux 测试工具增加了：

```sh
robobase-rpmsg-test --query-status -d /dev/ttyRPMSG30
```

这个命令发送 `HELLO`，M7 返回 `STATUS`，但不会刷新 lease。

## M7 GPIO 安全输入

当前 M7 侧真实采样两路 NC 安全输入：

```text
E-stop NC auxiliary contact: J25 pin 23, ECSPI2_SCLK_3V3, GPIO5_IO10
Bumper/microswitch NC:       J25 pin 21, ECSPI2_MISO_3V3, GPIO5_IO12
```

安全语义：

```text
低电平: NC 闭合，输入安全，status 中 *_nc_closed=1
高电平: NC 断开或未接线，输入故障，status 中 *_nc_closed=0
```

相关 M7 文件：

```text
robobase_safe_app.c/.h
robobase_safety_inputs.c/.h
robobase_m7_rpmsg_tty_echo.c
```

`robobase_safety_inputs.c` 负责 IOMUX 和 GPIO5 输入初始化；安全状态机不直接耦合
具体 pinmux 寄存器。

## 编译

编译 M7 固件：

```sh
cd /home/compile/workstation/project/codex/myplatform/third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc
export ARMGCC_DIR=/home/compile/workstation/project/codex/myplatform/third_party/m7/gcc-arm-none-eabi-7-2017-q4-major
./build_debug.sh
```

编译 Linux 测试工具：

```sh
cd /home/compile/workstation/project/codex/myplatform/third_party/yocto/yocto_5.10.72
export EULA=1
export DISTRO=fsl-imx-xwayland
export MACHINE=myd-jx8mp
source setup-environment ../../../build/out/myir_imx8m_plus/xwayland/yocto
bitbake robobase-rpmsg-test
```

## 板端部署

当前推荐通过 Yocto `robobase-m7-firmware` recipe 把 M7 ELF 安装进镜像。
临时调试时仍可手动复制 M7 固件：

```sh
scp -O debug/robobase_m7_rpmsg_tty_echo.elf root@192.168.1.2:/lib/firmware/
```

复制 Linux 测试工具：

```sh
scp -O /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/xwayland/yocto/tmp/work/cortexa53-crypto-poky-linux/robobase-rpmsg-test/0.1-r0/image/usr/bin/robobase-rpmsg-test root@192.168.1.2:/usr/bin/
```

启动 M7：

```sh
modprobe imx_rpmsg_tty
R=/sys/class/remoteproc/remoteproc0
echo robobase_m7_rpmsg_tty_echo.elf > "$R/firmware"
echo start > "$R/state"
```

当前推荐的产品化启动方式是：

```sh
systemctl restart robobase-m7.service
systemctl restart robobase-rpmsg-tty.service
```

## 验证命令

先验证正常 lease：

```sh
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 -n 3
```

再验证 watchdog：

```sh
robobase-rpmsg-test --safety -d /dev/ttyRPMSG30 --lease-timeout-ms 200 -n 1
sleep 1
robobase-rpmsg-test --query-status -d /dev/ttyRPMSG30
```

## 已验证结果

正常 lease 测试：

```text
status 1 state=RUNNING motion=1 fault=0x00000000 latched=0x00000000 heartbeat=1 last_seq=1 lease_age=0
status 2 state=RUNNING motion=1 fault=0x00000000 latched=0x00000000 heartbeat=2 last_seq=2 lease_age=0
status 3 state=RUNNING motion=1 fault=0x00000000 latched=0x00000000 heartbeat=3 last_seq=3 lease_age=0
summary: requested=3 ok=3 failed=0
```

Watchdog 超时查询：

```text
status 0 state=SAFE_STOP motion=0 fault=0x00000004 latched=0x00000000 heartbeat=5 last_seq=1 lease_age=32417
```

结论：

```text
RPMsg safety LEASE/STATUS 链路正常。
M7 本地 SysTick 计时正常。
停止刷新 lease 后，M7 可以自主进入 SAFE_STOP。
motion_enable 会被清为 0。
fault=0x00000004 对应 RB_FAULT_LINUX_TIMEOUT。
```

真实 GPIO 采样验证：

```text
未接线或 NC 断开时，estop_nc=0 / bumper_nc=0，并进入 FAULT_LATCHED。
J25 pin 23 短接到 GND 时，预期 estop_nc=1。
J25 pin 21 短接到 GND 时，预期 bumper_nc=1。
两路都闭合且 clear fault 后，才允许 RUNNING/motion=1。
```

## 当前边界

- 急停和 bumper 已改成 M7 真实 GPIO 采样。无接线时用 SoC 内部 pulldown 模拟低电平
  在本板上不可靠，因为 J25 ECSPI2 信号经过 TXS0108E 自动方向电平转换器。
- `driver_ok` 和 `power_ok` 目前仍是 Linux lease 字段，后续建议改名为更明确的
  Linux health/telemetry 字段。
- 协议 `crc32` 仍是占位禁用状态，后续需要补 CRC 或更强的完整性校验。
- 当前 bare-metal 架构仍是单主循环协作式调度，RTOS 已列入后续计划。
