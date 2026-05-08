# MYIR i.MX8MP M7 本地 Lease Watchdog 验证记录

本文记录 RoboBase M7 safety-v0.1 链路中的本地 watchdog 实现和板端验证结果。

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

主循环会调用 `robobase_safe_check_watchdog()`。即使没有新的 RPMsg 数据，SysTick
也会唤醒 `WFI`，让主循环继续检查 lease 是否过期。

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

复制 M7 固件：

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

## 当前边界

- 急停和 bumper 仍是 M7 固件内模拟输入，尚未接真实 GPIO。
- `driver_ok` 和 `power_ok` 目前仍是 Linux lease 字段，后续建议改名为更明确的
  Linux health/telemetry 字段。
- 协议 `crc32` 仍是占位禁用状态，后续需要补 CRC 或更强的完整性校验。
