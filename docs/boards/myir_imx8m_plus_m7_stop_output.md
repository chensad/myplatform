# M7停止后授权输出保持高：定位与修复边界

更新：2026-09-28。用户选择先只处理正常退出，不采购外部看门狗。QUIESCE固件/工具/服务已实现并构建，11项本地测试通过；QUIESCE、带授权正常停止高→低及停止锁存保持板测均通过。后文硬件方案保留为未实施参考。此问题独立于已通过板测的RPMsg TTY拆除修复。

## 证据

用户在授权状态停止M7后，测得AHCT08 pin2仍高；独立双NC碰撞触点驱动的HW_OK仍能控制门输出。此前100k下拉下授权电平约3.17V。停止后没有提供GPIO DR/GDIR寄存器读数或波形，不能把寄存器保持的具体机制当成已测事实。

本地源码：

- M7 `robobase_safety_outputs.c`将GPIO5_IO11配置为输出，写DR置位/清零；初始化默认低，之后由安全状态机更新。
- `robobase_safe_app.c`中的租约watchdog是M7安全主循环执行的软件逻辑，不是独立硬件监督器。停止核后无法继续计算租约过期或写低输出。
- Linux `robobase-m7-stop`直接向remoteproc state写stop；当前没有先请求M7撤销授权，也用`|| true`忽略停止失败。
- BSP `imx_rproc_stop()`在本平台走SMC停止核；该函数未显式清除GPIO5_IO11。停止CPU不能据此等同于复位GPIO外设。结合测量，最符合证据的是GPIO输出状态在核停止后保持，仍需寄存器/波形才能确认精确电气过程。

100k下拉用于高阻情况下的默认低电平，不应通过减小下拉阻值与主动输出争用来处理该故障。

## 两个独立目标

### 正常关闭

可设计显式QUIESCE/停止授权协议：M7先锁存禁止授权、拉低输出，再回ACK；锁存期间拒绝后续续租重新授权，Linux收到确认才进入正常停核流程。必须覆盖后台发送者竞争，不能只发一次无效租约或等待200ms。若M7无响应，软件握手不能证明输出已低；不能把超时后强停描述为安全撤销完成。

此协议需同步修改公共协议、M7状态机、Linux工具及服务，验证ACK顺序、重复请求和重启初始化。当前未实施。直接从Linux用devmem同时修改M7拥有的GPIO寄存器不作为部署方案。

### 意外卡死或直接停核

建议外部边沿/脉冲超时监督，形成独立许可条件：

```text
M7安全主循环完成检查 -> 心跳GPIO -> 外部超时监测 -> M7_ALIVE
最终使能 = HW_OK AND safety_allow AND M7_ALIVE
```

这是功能关系，尚非可直接接线的电路图。GPIO pin2本身可以仍高，但最终EN_NODE必须在规定超时内变低；如要求pin2也低，需要另行定义合格授权信号并调整门的位置，不能把监督器输出直接短接到推挽GPIO。

心跳只在安全主循环完成所需检查后更新，不能使用独立PWM或仅在SysTick中喂狗，否则安全主循环卡住仍可能输出心跳。现有主循环存在RL_BLOCK发送，超时监督也应覆盖该阻塞；超时后的再次授权须考虑锁存/明确复位，防止瞬时恢复自动使能。

器件选择需核对：输入电压与板上电平转换、掉电/上电默认禁止、静态高及静态低均能超时、超时输出是否保持还是周期脉冲、复位/锁存行为和最大公差。不得把低有效WDO不加分析地直接当成持续健康许可。TI的TPS3431资料说明独立WDI超时监测原理，仅作原理参考，尚未指定采购型号或具体接线：https://www.ti.com/product/TPS3431 。

需要确定可用器件/模块、空闲引脚以及允许的最大撤销时间，才能给出电路和固件心跳周期；不能直接把目前Linux租约200ms当成执行器可接受的停机时限。

## 台架验收方向

保持无电机台架，分别测量HW_OK、原授权GPIO、心跳、监督器许可和最终EN_NODE：

1. 上电无心跳时最终输出低；有效心跳但无授权时也低。
2. 输入闭合、心跳正常、租约有效时才允许最终输出高。
3. 授权期间停核、心跳卡高、心跳卡低、心跳线断开，均在规定最大时间内撤销最终输出。
4. M7主循环卡住但中断仍运行时也必须超时。
5. 急停/碰撞独立通道仍可立即撤销；M7或心跳恢复不绕过锁存/重新授权条件。
6. 测量最坏响应时间和启动/停止瞬态；万用表稳态值不能代替该时序验收。

本轮没有实际硬件验证结果，不把诊断或上述目标写成已实现。

## 2026-09-28：心跳检测参考设计

设计阶段，尚非可直接生产/接执行器的定版原理图。建议以TPS3431超时检测、SN74LVC1G74许可锁存、电源监控及现有AHCT08组成台架参考方案。采用锁存后的RUN_OK而不是直接把WDO称作M7_ALIVE。

### 数据手册核对

- TPS3431 Rev.A表5-1：VDD=1、CWD=2、EN=3、GND=4、SET1=5、WDI=6、WDO=7、ENOUT=8，DRB VSON-8封装，裸露焊盘接地。WDI检测下降沿，VIH至少0.8×VDD，因此采用3.3V供电以接收3.3V心跳，不直接用5V供电接3.3V信号。
- CWD通过10k接VDD且SET1高，tWD=170/200/230ms(min/typ/max)。这是无电机台架初始参数，不代表机器人安全停机允许时间。CWD悬空会变成1.6s典型值，不能漏接。
- WDO开漏低有效，超时拉低tRST后释放，并非持续心跳有效信号。直接接入与门会存在重新放行窗口。TPS3435某些锁存型号也会被WDI下降沿自动解除，不能当成人工复位锁存。
- SN74LVC1G74可在3.3V供电，有异步低有效CLR/PRE与上升沿CLK。SN74AHCT08维持5V，使用其TTL输入门限接收3.3V许可。最终还需核对实际负载、掉电和输入电平裕量。

资料：
- https://www.ti.com/lit/ds/symlink/tps3431.pdf
- https://www.ti.com/lit/ds/symlink/sn74lvc1g74.pdf
- https://www.ti.com/lit/ds/symlink/sn74ahct08.pdf
- https://www.ti.com/lit/ds/symlink/tps3435.pdf

### 超时检测接线（TPS3431 DRB）

| 引脚 | 参考连接 |
| --- | --- |
| 1 VDD | 3.3V，近端100nF去耦 |
| 2 CWD | 10kΩ到3.3V，选择200ms典型值 |
| 3 EN | 固定3.3V，避免M7关闭检测 |
| 4 GND及散热焊盘 | 公共地 |
| 5 SET1 | 固定3.3V |
| 6 WDI | M7心跳输入；可先用1k串联、检测端100k下拉的短线台架参数，按实际GPIO输出/电平转换核验幅值与边沿 |
| 7 WDO | 10kΩ上拉至3.3V，接故障清零链，不直接作最终许可 |
| 8 ENOUT | 未使用时不接，不能作为已收到心跳的证明 |

VSON不适合直接插面包板，需转接板或小PCB。所有IC就近去耦并共地。心跳引脚尚未分配，不复用现有授权、急停或碰撞监测引脚。

### 许可锁存与上电复位

SN74LVC1G74供电3.3V：D固定1、PRE_N固定1、CLK来自去抖/整形后的明确ARM上升沿，Q为RUN_OK；CLR_N由WDO_N及电源正常条件共同决定，任何故障/电源不正常时均强制低。逻辑关系为CLR_N = WDO_N AND POWER_OK；若采用多个开漏复位输出并联，必须保证它们均为开漏、同一允许上拉域，绝不并联推挽输出。

上电电源监控先清Q=0，监控须覆盖3.3V监督电路与5V门控供电的失效/时序；不能依赖触发器随机上电值或WDO上电高。监督器具体型号和电源掉电隔离尚未定，失电时最终使能必须默认低。检测板断电、断线、5V单独存在的情况均需专测。

超时清Q=0，WDO后来释放或心跳恢复都不产生ARM边沿，因此Q保持0。ARM应是人工确认或受控重新授权的一次边沿，不能自动由WDO上升沿产生，也不能由自由运行脉冲驱动。原始机械按键需要去抖，不能直接当可靠CLK。

RUN_OK准确含义是“曾明确授权，之后未出现检测到的故障”，不是“当前已严格证明收到足够心跳”。仅看WDO高并不能证明存在心跳：启动/两次故障脉冲间也可能高。因此第一次ARM前须确认有效心跳和初始化完成，台架可人工观察；无人值守版本须另做心跳资格判定/受控授权逻辑，不能把手动参考方案当成自动启动定版。

### 接入现有14脚AHCT08

保持pin1=HW_OK、pin2=safety_allow、pin14=5V、pin7=GND。pin3作为中间结果，接pin4；RUN_OK接pin5，pin6作为新的最终EN_NODE。原pin3不再直连最终使能。若pin4/pin5原先因闲置接地，需先移除这些固定连接再接入。未用门输入固定电平、输出悬空。最终输出在驱动器端的默认下拉及掉电反灌也必须在定版中核验。

最终关系：EN_NODE = HW_OK AND safety_allow AND RUN_OK。原授权GPIO卡高时，超时锁存仍可使pin6变低。

### 固件与验收

台架可先考虑主循环每10ms翻转一次GPIO，因此下降沿间隔约20ms，给170ms最短检测时间留裕量。只能在安全检查完成后更新，禁止定时器自主PWM/仅中断喂狗，也不允许积压tick回放制造集中虚假心跳。实际最大间隔须测量，不能把这个建议写成已实现。

停止后从最后有效下降沿到故障检测的上界按230ms加锁存/门传播时间评估，实际停机能否接受还需机械侧要求。检查卡高、卡低、断线、主循环阻塞、监督电源掉电、心跳恢复但未ARM、ARM按键保持以及整板重启。预期故障后最终输出持续低；再次出现心跳不能自动恢复使能。

## 2026-09-28：正常退出的软件修复（当前实施范围）

用户明确暂不采购TPS3431，只处理M7正常退出。本次没有硬件改动，没有实现卡死/强制停核的独立保护。

### 协议与固件

公共协议增加头部-only `RB_SAFE_MSG_QUIESCE=6`，STATUS的fault_bits新增`RB_FAULT_STOP_REQUESTED=0x80`作为行政停止原因，现有布局/协议版本保持兼容。M7收到有效请求时：

1. 设置本次固件运行期不可解除的`s_stop_requested`。
2. 调用统一授权计算，写GPIO5_IO11低；之后所有租约、清故障、输入调试及周期检查均受该标志限制。
3. 执行`__DSB()`，确保Device内存的GPIO写在确认前完成，再返回同序号STATUS。

QUIESCE可重复发送，CLEAR_FAULT不能解除此标志；必须通过M7固件重新启动清零BSS，才可重新授权。STATUS确认仍是软件/寄存器操作完成的证据，不代替板端电压/波形测量。STOP_REQUESTED可与其他fault位叠加，不能只判断fault恰好等于0x80。

### Linux工具与服务

- `robobase-rpmsg-test --quiesce`确认同序号STATUS、motion=0、STOP_REQUESTED位存在和停止类state。旧固件对未知命令返回的普通motion=0/PROTOCOL_ERROR不能通过。
- 接收支持一条完整`hello world!`握手回显前缀，拒绝未知坏帧；使用CLOCK_MONOTONIC及统一读帧deadline。
- 工具所有模式在I/O前取得TTY的非阻塞flock。正常关闭前应结束所有RPMsg客户端；外国/旧客户端未必遵守该锁，不能并行读取同一TTY。脚本不杀未知进程。
- `robobase-m7-stop`先QUIESCE，成功才向state写stop并核实offline；无应答、TTY忙、工具缺失或旧固件均非零退出，不执行强停。已offline为幂等成功。停止错误不再被`|| true`吞掉。
- `robobase-m7-start`遇到已running/attached的核，也先调用正常stop脚本；防止服务启动路径绕过握手。
- 服务recipe依赖新版测试工具。工具recipe对公共头文件加入task checksum，避免协议更新被构建缓存漏掉。配置新增ROBOBASE_RPMSG_TTY_DEVICE与ROBOBASE_M7_QUIESCE_TIMEOUT_MS，默认ttyRPMSG30、1500ms；缺新配置时也有相同默认值。

ExecStop失败可能让systemd服务显示failed/inactive，但硬件核仍running；排查以remoteproc state为准。此处理不能阻止整个Linux关机流程继续，也不覆盖直接echo stop、崩溃复位、调试器停核或掉电。旧的“活跃发送期间stop”的驱动压力测试与正常退出测试不同：不要并行运行旧生命周期脚本和该握手客户端，也不要为了通过新测试绕过确认。

### 本地验证与产物

`python3 -B -m unittest discover -s tools/tests -p test_m7_quiesce.py -v`：11项通过。测试将实际M7状态机源文件与GPIO/CMSIS替身链接，检查授权高→QUIESCE低、ACK前barrier、无效请求、重复QUIESCE，以及后续LEASE/CLEAR_FAULT/DEBUG_INPUTS/tick保持低；还使用PTY测试真实Linux客户端的ACK/旧固件/超时/错误序号/占用，模拟sysfs检查服务握手顺序及拒绝强停。

Cortex-M7 debug ELF与使用既有Yocto sysroot的ARM64客户端编译成功。M7编译有厂商fsl_mu.c未使用函数及旧GCC不识别-Wno-address-of-packed-member警告；不是零警告构建。Linux工具-Wall -Wextra -Werror通过。完整BitBake镜像未构建。

产物目录：`build/out/myir_imx8m_plus/diagnostics/m7-normal-stop/`，包含ELF、ARM64工具、start/stop脚本、配置参考、manifest与SHA256SUMS。ELF SHA256：`8a71d63992e5fcfc0bc25abed7ce23f24c9e8f8f3d25e66b20fdd0116293fd5d`；工具SHA256：`6e01348cd63ee3599064bdd7938e24c25270b87a8437aa94a783437eda0ca303`。

### 配套部署与板端验收

不能只安装新停止脚本而继续用旧固件。台架保持无驱动器/电机，当前RPMsg驱动仍使用已验证修复版。

1. 从电脑用`scp -O -r`将上述m7-normal-stop目录上传到主板/home。在目录内执行`sha256sum -c SHA256SUMS`，先确认全部OK。
2. 结束其他RPMsg客户端，用原工具查询motion=0，并测量pin2低。使用原stop服务停止TTY/M7并确认offline，再更换文件。若此前已误安装新版stop配旧固件，不能靠它完成升级；先恢复备份旧stop并按本步骤确保输出低后停止。
3. 将当前`/lib/firmware/robobase_m7_rpmsg_tty_echo.elf`、`/usr/bin/robobase-rpmsg-test`、`/usr/bin/robobase-m7-start`和`/usr/bin/robobase-m7-stop`备份到独立目录；安装同名新文件（ELF 0644，工具/脚本0755）。配置文件为参考，不覆盖用户原有/etc/default设置。更换前核对实际文件路径，若固件在/usr/lib则使用实际路径。
4. 启动robobase-m7.service及robobase-rpmsg-tty.service，查询状态。无需重启整板或重新加载Linux模块。
5. 在无其他客户端时先单测`robobase-rpmsg-test --quiesce`：应打印QUIESCE confirmed、motion=0、fault含0x80，测量pin2低。随后尝试一次有效LEASE和CLEAR_FAULT，pin2必须仍低；这些命令的通信成功不代表重新获得授权。
6. 执行systemctl stop robobase-m7.service：应先显示QUIESCE确认，再报告remoteproc offline；pin2继续低。重新启动两服务后stop标志应消失，默认无租约仍低，重新有效租约才允许高。
7. 为区分“正常关闭主动拉低”与“原租约自然过期”，可在无电机台架先使用一次5秒测试租约，然后立即停止服务（客户端已退出）。核对服务在租约过期前收到确认并停核，记录pin2高→低和停核后保持低；5秒只作该项诊断，不改默认200ms租约。
8. 验证TTY忙/旧固件等失败场景不得写stop。保存journalctl、remoteproc state及实测电压，才将板端结果记录为通过。

未在主板执行这些步骤，当前仍为待部署/待测状态。直接强停保留GPIO高的问题并未由本次软件协议消除。

### 配套更新包安装器（2026-09-28）

新增`tools/board-install-m7-normal-stop.py`，已复制到产物目录，默认从自身所在目录取配套文件。固定校验4份已构建产物的SHA256；仅接受remoteproc0固件名匹配、已offline、两服务inactive/failed、已加载safe-teardown驱动的环境。保留usrmerge目录链接，但拒绝单独文件的自定义符号链接。当前安装目标是/lib/firmware的ELF和/usr/bin的工具/start/stop；其他布局应先核对，不盲目替换。

全部旧文件备份到`/home/rb-m7-normal-stop-backup-*`，manifest含原目标、哈希及权限。逐文件原子替换，安装失败且M7仍停机时回滚已动文件；多文件替换不是跨掉电事务，中途断电或回滚失败需用备份人工恢复。脚本不改/etc/default、不自动启停服务/重启、不替换Linux驱动。INSTALL PASS只说明文件安装完成，固件启动与电压验证另行验收。

电脑上传：

```sh
scp -O -r /home/compile/workstation/project/codex/myplatform/build/out/myir_imx8m_plus/diagnostics/m7-normal-stop root@192.168.31.51:/home/
```

无电机台架，先结束所有其他RPMsg客户端，再在主板校验并撤销旧固件授权：

```sh
cd /home/m7-normal-stop
sha256sum -c SHA256SUMS
./robobase-rpmsg-test --safety --upstream-invalid -n 1 -d /dev/ttyRPMSG30
```

仅在文件校验全OK、收到motion=0并测得pin2低后继续。此处使用新工具发旧固件也支持的无上游许可LEASE，不使用旧固件不支持的QUIESCE；没有并发写者是前提。

```sh
systemctl stop robobase-rpmsg-tty.service
systemctl stop robobase-m7.service
cat /sys/class/remoteproc/remoteproc0/state
```

确认offline后安装；任何FAIL不继续启动：

```sh
python3 /home/m7-normal-stop/board-install-m7-normal-stop.py
```

INSTALL PASS后：

```sh
systemctl start robobase-m7.service
systemctl start robobase-rpmsg-tty.service
robobase-rpmsg-test --quiesce -d /dev/ttyRPMSG30
systemctl stop robobase-m7.service
cat /sys/class/remoteproc/remoteproc0/state
```

预期QUIESCE confirmed、正常stop及offline，pin2持续低；这一步不自动重新授权。按前述验收还需验证带授权关闭及后续LEASE/CLEAR不能清停止锁。要恢复待机再启动M7、TTY两服务即可。

安装器5项本地临时文件测试通过：正常备份/权限/安装、坏哈希拒绝、运行中拒绝、部分安装回滚、原文件缺失拒绝。使用`python3 -B -m unittest discover -s tools/tests -p test_m7_normal_stop_install.py -v`复现。未连接或代替用户更新主板。

### 首次新版正常停止板测（2026-09-28）

用户执行--quiesce得到SAFE_STOP、motion=0、fault=0x8c、latched=0及QUIESCE confirmed，随后systemctl stop robobase-m7.service，510.566906s停止remoteproc且state=offline；用户报告实测低电平。0x8c包含停止请求和Linux/上游超时位，符合未发送租约的状态。此项证明新协议确认和正常停核能完成，低电平为用户测量反馈；不是由授权高转低的完整证据，也不代表整套磁盘文件哈希已核验。后续需带有效租约正常停止及停锁不能被续租/清故障解除的板测。

### 带授权正常停止板测通过（2026-09-28）

用户按前述5秒测试租约执行250次续租，并在客户端成功退出后立即systemctl stop，反馈电平表现符合预期（高→低并保持）。日志247至250条均为RUNNING、motion=1、fault=0、latched=0、NC输入均1；summary requested=250 ok=250 failed=0，停止后remoteproc0=offline。由此记录目标场景“有授权时正常关闭，撤销输出后停核”通过。此为用户稳态观察与日志证据，没有测量精确撤销时延，不覆盖直接强停或M7卡死。

剩余补测：M7仍运行时QUIESCE后发送新的有效LEASE及CLEAR_FAULT，输出应继续低且STOP_REQUESTED位保留；重新启动M7才允许重新授权。本地状态机测试已覆盖这些路径，板端确认尚未收到。

### 停止锁存保持板测通过（2026-09-28）

用户在QUIESCE后执行`robobase-rpmsg-test --safety --clear-fault 0xffffffff -n 3 -d /dev/ttyRPMSG30`。清故障响应为SAFE_STOP、motion=0、fault=0x8c、latched=0；之后3个有效LEASE响应均SAFE_STOP、motion=0、fault=0x80、latched=0，用户测量确认输出始终低。有效租约消除了Linux/上游超时位，但不能清除行政停止位0x80；普通latched字段为0不代表停止锁解除。

至此，正常退出流程的高→低与停止后禁止重新授权两项主要板测通过。此轮未提供最后一次stop/state输出，不推定当前remoteproc已offline。卡死/直接强停保护、精确时序和整机镜像仍不在已完成范围；源码提交及镜像集成待后续执行。
