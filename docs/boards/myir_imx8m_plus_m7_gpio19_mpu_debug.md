# MYD-JX8MP：M7 safety_allow 恒高的定位与 MPU 修复

日期：2026-09-19。平台：MYIR MYD-JX8MP / i.MX8MP，Linux remoteproc + 裸机 Cortex-M7。

## 1. 结论与验证边界

本次故障为：安全状态机已经输出 `motion=0`，J25 第19脚却仍为约3.3V。输入开关和 RPMsg 正常，不能据此认定运动授权的物理链路正常。

M7 最小固件省略了 MPU 初始化，外设寄存器所在的 `0x30000000` 地址区没有设置为 Device 内存。通过初始化分阶段快照，观察到写一个寄存器时相邻寄存器状态发生变化。增加外设 Device 属性后，复用和方向配置稳定；用户随后确认开关触发、锁存、续租及停止续租测试均通过。

正式修复：在所有安全 GPIO、时钟查询及 RPMsg 外设访问之前，将 `0x30000000–0x30FFFFFF` 配置为 Device、Shareable、不可执行的16MB MPU区域。保留其余地址的默认映射，不开启缓存，不调用整板初始化。

证据支持“外设内存属性缺失导致 MMIO 访问异常”的工程根因。普通内存写入合并是与现象相符的硬件机制，但没有总线分析仪轨迹，不把具体 AXI 事务宽度/字节选通行为写成已测事实。

验证边界：

- 用户板测通过的是保留快照功能的 MPU 验证固件；用户反馈“都测试OK”，未提供每项电压的数值记录或示波器时间测量。
- 本轮已把同一 MPU 配置纳入正式源码，正式 ELF 本机构建及反汇编检查通过。
- 正式 ELF 尚未由助手部署到板端，也未获得该最终产物的再次板测结果。
- 未重建完整 Yocto 镜像。修复未自动进入已有 ext4/SD卡镜像。
- 本次没有接电机；独立 HW_OK 硬件开关回路和执行器验收不在本次结论内。

## 2. 电路和信号定义

以下都是 J25 物理针号：

| 信号 | 针脚 / GPIO | 作用 |
| --- | --- | --- |
| estop NC | 23 / GPIO5_IO10 | NC接该脚，COM接GND；正常闭合输入为低 |
| bumper NC | 21 / GPIO5_IO12 | NC接该脚，COM接GND；正常闭合输入为低 |
| safety_allow | 19 / GPIO5_IO11 | `motion=1`时高，禁止运动时低 |
| GND | 6、9、14、20、25、30、34、39 | 当前低压台架公共地 |

开关NO留空。`estop_nc=1` / `bumper_nc=1` 表示闭合状态，不是输入电压为高。输出测量用直流电压档，黑笔GND、红笔第19脚；第19脚空载，不连接与门或模拟3.3V跳线。

J25 与 SoC 之间有 TXS0108E 电平转换；外部3.3V不是GPIO已主动输出高的充分证据。与门SN74AHCT08N的5V输出不可回接M7输入。

## 3. 初始现象与排查

碰撞触发时用户回报：

```text
state=FAULT_LATCHED motion=0 fault=0x00000002 latched=0x00000002
estop_nc=1 bumper_nc=0
```

第19脚空载仍约3.3V。正常启动时 `SAFE_STOP motion=0 fault=0x0c`，引脚也未拉低。

依次确认：

1. 测量点确实为物理第19脚，已去除外部负载和模拟电源跳线。
2. 板端ELF哈希与包含输出代码的本地产物一致。
3. remoteproc日志显示实际执行stop/load/start，加载278328字节ELF，RPMsg通道创建成功。
4. ELF反汇编包含GPIO复用、方向置输出、默认拉低及后续授权更新指令。
5. Linux pinctrl显示第19脚 `MUX UNCLAIMED / GPIO UNCLAIMED`。这只表示Linux未登记所有者，不证明硬件功能是GPIO，也不能排除历史写入。
6. Linux GPIO5仅登记了CAN1 standby（GPIO5_IO05）。GPIO5仍为两核共享寄存器组。
7. `gpio5_root_clk`在Linux时钟框架中enable/prepare均为1；不能据此证明M7全部域权限，但不支持“Linux简单关掉GPIO5时钟”的解释。
8. 摄像头驱动重试日志与故障同时出现，但本地设备树未找到其占用该pad的证据，未据此修改摄像头配置。

## 4. 寄存器读取方法与注意事项

| 项目 | 地址 | 预期 |
| --- | --- | --- |
| pin19 MUX | 0x303301F4 | 低3位=5（GPIO） |
| pin19 PAD | 0x30330454 | 当前驱动配置为0x2 |
| GPIO5 DR | 0x30240000 | 授权位mask=0x800；输出模式下跟随motion |
| GPIO5 GDIR | 0x30240004 | bit11=1（输出），bit10/12=0（输入） |
| GPIO5 PSR | 0x30240008 | pad采样；结合SION等配置解释 |
| pin23 MUX | 0x303301F0 | 0x15：GPIO + SION |
| pin21 MUX | 0x303301F8 | 0x15：GPIO + SION |

不要要求整组GDIR等于某一常数，Linux还使用该组其他GPIO。输出方向未建立时，DR读数不应被理解成已成功主动输出该电平；实际引脚电压须测量。

板上没有BusyBox devmem/独立devmem。最初Python mmap+struct读取不能保证访问宽度，随后用GCC编译的只读工具明确执行对齐的 `volatile uint32_t` 读取，结果一致。后续以此为可靠复核方式。核心读法如下：

```c
int fd = open("/dev/mem", O_RDONLY | O_SYNC);
/* 检查open/mmap错误；base按sysconf(_SC_PAGESIZE)对齐。 */
void *p = mmap(NULL, page_size, PROT_READ, MAP_SHARED, fd, base);
uint32_t value = *(volatile uint32_t *)((char *)p + (addr - base));
```

不要把任意地址的/dev/mem读取当作通用安全操作；本次地址已与SDK和Linux pinfunc核对。保持只读，不通过直接写寄存器掩盖初始化问题。

## 5. M7快照：缩小问题发生区间

首版诊断仅增加读取快照，仍保留原初始化顺序：

```text
output_init → inputs_init → sample_inputs → update_motion
```

用户实际结果摘录：

| 阶段 | MUX19 | PAD19 | GDIR | MUX23 | MUX21 |
| --- | --- | --- | --- | --- | --- |
| before_output_init | 2 | 2 | 0x20 | 0x15 | 0x15 |
| after_mux | 5 | 2 | 0x20 | **0** | 0x15 |
| after_output_init | 5 | 2 | 0x820 | 0 | 0x15 |
| after_safe_init | **0** | **0** | **0** | 0x15 | 0x15 |
| at_query | 0 | 0 | 0x01010525 | 0x15 | 0x15 |

关键证据：输出初始化本身成功，但其后配置丢失；写pin19 MUX时，紧邻的pin23 MUX也改变。两个寄存器相差4字节，GPIO DR/GDIR也相差4字节。这推动排查从“旧固件/开关/I2C占用”转向MMIO内存属性。

本地SDK `BOARD_InitMemory()` 把低地址大范围设为Device再覆盖TCM等区域；最小固件为了避免整板缓存/时钟/RDC初始化，跳过了这一配置。`SystemInit()`本身只做FPU等设置，没有替代的MPU初始化。

Arm Cortex-M7 TRM说明Normal内存写入允许合并，Device/Strongly-ordered不进行这种合并：
https://documentation-service.arm.com/static/5e906b038259fe2368e2a7bb

`volatile`约束编译器访问，不能替代处理器的内存类型设置。

## 6. MPU验证版与正式修复

验证版在GPIO初始化前增加：

```c
ARM_MPU_SetRegionEx(region_count - 1U, 0x30000000U,
    ARM_MPU_RASR(1U, ARM_MPU_AP_FULL,
                 0U, 1U, 0U, 1U, 0U, ARM_MPU_REGION_SIZE_16MB));
ARM_MPU_Enable(saved_ctrl | MPU_CTRL_PRIVDEFENA_Msk | MPU_CTRL_HFNMIENA_Msk);
```

配合保存/恢复PRIMASK、临时关中断、CMSIS MPU禁用/启用和同步屏障；不改缓存状态。该RASR编码为`0x1305002f`。特权后台映射保留TCM、代码和RPMsg共享内存等区域原有默认行为。

验证版用户快照：

| 阶段 | MUX19 | PAD19 | GDIR | MUX23 | MUX21 |
| --- | --- | --- | --- | --- | --- |
| after_mux | 5 | 0 | 0x04040424 | 0x15 | 0x15 |
| after_output_init | 5 | 2 | 0x04040c24 | 0x15 | 0x15 |
| after_safe_init | 5 | 2 | 0x04040824 | 0x15 | 0x15 |
| at_query | 5 | 2 | 0x04040824 | 0x15 | 0x15 |

`after_safe_init`和`at_query`均方向bit11=1、DRbit11=0；输入方向bit10/12=0。用户随后确认开关和租约超时测试通过。

正式实现位于M7应用的 `robobase_m7_rpmsg_tty_echo.c`：

```text
main
  → robobase_init_mmio_memory
  → robobase_safe_init
  → SysTick初始化
  → RPMsg初始化
```

实现保留已验证配置；若MPU报告没有region，则停留在idle，不进入正常应用初始化。这不是独立硬件拉低保证。正式版不包含RBGPIO诊断命令及快照数组。

最高MPU region由此应用保留；当前最小固件没有其他MPU region所有者。后续若引入RTOS、缓存或其他MPU配置，必须统一region规划，不能悄悄覆盖该区域。此修改也不解决两核同时读改写同一GPIO寄存器的所有权问题。

## 7. 构建、打包与产物

WSL工作区已有CMake配置时：

```sh
cd /home/compile/workstation/project/codex/myplatform
cmake --build third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc --target robobase_m7_rpmsg_tty_echo.elf -j 2
```

产物目录：

```text
third_party/m7/SDK_2_10_0_EVK-MIMX8MP/boards/evkmimx8mp/demo_apps/robobase_m7_boot_only/armgcc/debug/
```

原有Yocto配方从此目录安装预编译ELF。本轮补充：

```bitbake
do_install[file-checksums] += "${ROBOBASE_M7_ELF}:True"
```

外部ELF不在SRC_URI中，因此需要其内容进入安装任务签名，防止M7已重编而固件包复用旧缓存。此配方不会替你编译M7；先构建M7，再在现有Yocto环境重建固件包/镜像。本轮未运行完整BitBake打包或镜像构建。

| 产物 | SHA256 |
| --- | --- |
| 修复前正式文件 | `1c5b112d2d4ef776e918b67a6fd383c3b2b9e6d4ffc5a5d0706377b8af8da4f6` |
| 只读诊断版 | `1dcc60ee1c797fe3f9f8ad67e73c5aaf41c1200c6419e86e093e014e8bb3560d` |
| 用户板测通过的MPU诊断版 | `578c94468d7b3dbc4832544eb5124f36be3e5044bcb6de9157b74a505d854bac` |
| 正式修复版 | `e47e866603db3be64cafac90993f8b419a1c9d5e1ea4d93f16296f7e32d9be52` |

诊断文件归档在工作区根目录 `diagnostics/gpio19/` 和 `diagnostics/gpio19_mpu/`。其构建脚本复用本地源码/对象文件，正式源码改变后重新运行不保证再生成历史哈希；历史结果以已保存ELF及哈希为准。

## 8. 正式固件部署与回归

将正式ELF传至主板 `/home/robobase_m7_rpmsg_tty_echo.elf`，核对上表哈希。保持不接电机、第19脚空载，停止所有RPMsg客户端。

```sh
sha256sum /home/robobase_m7_rpmsg_tty_echo.elf
systemctl stop robobase-rpmsg-tty.service
systemctl stop robobase-m7.service
cat /sys/class/remoteproc/remoteproc0/state
```

若手动诊断固件仍处于running，显式停止后确认offline：

```sh
echo stop > /sys/class/remoteproc/remoteproc0/state
```

然后备份旧文件（此备份用于回滚启动问题，不代表旧版授权输出正常），安装并启动正式服务：

```sh
cp -p /lib/firmware/robobase_m7_rpmsg_tty_echo.elf /home/robobase_m7_before_mpu_$(date +%Y%m%d-%H%M%S).elf
install -m 0644 /home/robobase_m7_rpmsg_tty_echo.elf /lib/firmware/robobase_m7_rpmsg_tty_echo.elf
systemctl start robobase-m7.service
systemctl start robobase-rpmsg-tty.service
cat /sys/class/remoteproc/remoteproc0/firmware
cat /sys/class/remoteproc/remoteproc0/state
ls /dev/ttyRPMSG*
```

预期原正式文件名、running以及TTY设备存在。测试设备号以实际为准，只运行一个RPMsg客户端。

先查询停止状态、测第19脚约0V：

```sh
robobase-rpmsg-test --query-status -d /dev/ttyRPMSG30
```

两个开关松开后持续续租：

```sh
robobase-rpmsg-test --safety --clear-fault 0xffffffff --lease-timeout-ms 200 -n 100000 -d /dev/ttyRPMSG30
```

| 测试 | 状态/电压预期 |
| --- | --- |
| 续租且全部条件正常 | RUNNING，motion=1，第19脚约3.3V |
| 分别触发急停/碰撞 | FAULT_LATCHED，motion=0，第19脚约0V |
| 松开触发开关 | NC恢复1，仍锁存，第19脚保持低 |
| 两开关正常、重新清故障续租 | 恢复RUNNING及高电平 |
| 正常授权时Ctrl+C停止续租 | 超时后motion=0，第19脚低；fault包含0x04 |
| 仅查询状态 | 不刷新租约 |
| 超时后重新续租、无锁存故障 | 可恢复授权 |

万用表只验证稳态高低，不能证明200ms或1ms响应时间；实时延迟应另用示波器/逻辑分析仪验证。

后续可再做与门联调：撤销模拟输入跳线，确认电平转换负载与共地，不能把本次单独pin19验收等同于完整执行器或独立HW_OK安全链验收。

## 9. 排查经验

- 软件motion=0不能替代物理使能输出的测量。
- 文件哈希、运行实例、初始化时刻快照和最终引脚电压是不同层面的证据。
- MUX值对应某外设功能不意味着那个Linux驱动就是修改者。
- 输入正常不能证明同组输出或共享寄存器配置正确。
- 外设寄存器需要正确的MPU内存类型；volatile、关闭D-cache、正确STR指令并不能替代它。
- 不用反复改初始化顺序、周期性重写MUX或外加下拉来掩盖相邻寄存器损坏。
