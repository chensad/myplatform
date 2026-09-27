# RPMsg活跃发送期间停止M7导致Oops

记录日期：2026-09-27。来源为用户串口日志、本地BSP源码与现存vmlinux反汇编。已完成BSP补丁及ARM64模块编译；用户已临时加载修复模块并反馈原故障场景单次stop/start回归正常。旧FD跨重启与10轮活跃查询启停随后通过；长期压力测试及完整Yocto镜像重建仍待完成。

## 现场与结论

无电机台架正常续租时，用户停止TTY服务，再停止M7服务，保留后台测试进程。最早异常发生在停止完成之后，而不是重新启动M7时。

| 时间（启动后秒） | 证据 |
| --- | --- |
| 测试开始 | 后台robobase-rpmsg-test PID 998，租约200ms |
| 324.216720 | rpmsg tty driver is removed |
| 324.225616 | msg received with no recipient |
| 324.225715 | remoteproc0: stopped remote processor imx-rproc |
| 324.334183 | imx_rproc_kick: failed (0, err:-62) |
| 325.225994 | 页访问异常，地址ffff80001273a002，页表pte=0 |
| 325.280649 | Oops #1，ESR=0x96000007 |
| 325.306322 | CPU2/PID998/Comm robobase-rpmsg- |
| 325.332498 | PC virtqueue_get_buf_ctx_split+0x28/0x150 |
| 约472 | 后续Oops #5在PID1 cgroup清理中发生，最终Attempted to kill init导致panic |

第一处调用链：用户write → tty_write → n_tty_write → rpmsgtty_write → rpmsg_send → virtio_rpmsg_send → rpmsg_send_offchannel_raw → virtqueue_get_buf → virtqueue_get_buf_ctx_split。

直接故障已定位为：通信资源拆除后，后台发送路径仍访问已无有效页映射的vring used区域。具体在途发送/对象引用的竞态需要在修复中处理；不能只修最后的cgroup栈，也不能把这归因于与门接线或M7 MPU修复。

## 指令与源码对照

本地vmlinux：

`build/out/myir_imx8m_plus/xwayland/yocto/tmp/work/myd_jx8mp-poky-linux/linux-imx/5.10.72+gitAUTOINC+7da54520b8-r0/build/vmlinux`

用同一work目录recipe-sysroot-native中的aarch64-poky-linux-objdump反汇编，函数长度0x150、故障偏移+0x28及现场最后五条机器码一致：

```text
+0x18  350005e0  cbnz w0, ...
+0x1c  f9403660  ldr  x0, [x19, #104]
+0x20  aa0103e4  mov  x4, x1
+0x24  79409261  ldrh w1, [x19, #72]
+0x28  79400400  ldrh w0, [x0, #2]
```

现场x0=ffff80001273a000，读x0+2恰好为日志异常地址ffff80001273a002。对照virtio_ring.c的more_used_split及virtio_ring.h中vring_used布局，读取的是used->idx。局部指令一致不能替代完整板端内核镜像身份校验。

本地kernel-source位于`build/out/myir_imx8m_plus/xwayland/yocto/tmp/work-shared/myd-jx8mp/kernel-source`：

- `drivers/rpmsg/imx_rpmsg_tty.c`：write经cport/rpdev进入阻塞rpmsg_send；remove注销TTY driver、释放名称并销毁port，未见打开TTY/在途发送的显式下线协调。cport为devm分配。
- `drivers/rpmsg/virtio_rpmsg_bus.c`：get_a_tx_buf回收svq缓冲；发送缓冲不足时可等待15秒。remove注销子设备、删除virtqueue、释放DMA缓冲与vrp。
- `drivers/remoteproc/remoteproc_virtio.c`：删除virtqueue。
- `drivers/remoteproc/imx_rproc.c`：imx_rproc_mem_release调用iounmap。与页映射失效现象相符，但现场未跟踪该地址的具体unmap调用。
- TTY systemd服务没有ExecStop；stop该服务不等于用户进程退出、TTY关闭或模块卸载。

## 处置与修复边界

1. 已panic的内核先保存串口日志，再复位/上电；不在出现Oops后继续做恢复测试。
2. 暂停保留活跃TTY写入的remoteproc stop故障注入。常规维护先退出并等待所有RPMsg客户端结束，再停止服务。此顺序只规避触发，不是驱动修复。
3. 驱动修复需处理新发送拒绝、在途发送与设备移除同步、阻塞发送退出、打开TTY对象与端点/transport的生命周期。仅加延时、判空或在用户态忽略错误不足以解决此类失效引用。
4. 修复必须经匹配BSP构建与板端并发发送/stop/start回归，预期客户端获得可处理的断链错误而不是内核Oops。下文实现已编译，单次原故障、旧FD及10轮生命周期板测结果见后文。

硬件结论独立保存：停止M7后AHCT08 pin2保持高；双NC碰撞HW_OK仍能拉低最终输出。该结果不表示M7失效时自动撤销授权已实现。驱动器、电机仍未接入。

## 已实现修复

持久补丁：

`platform/boards/myir_imx8m_plus/yocto/layers/meta-robobase/recipes-kernel/linux/files/0003-rpmsg-tty-serialize-remove-and-keep-port-alive.patch`

已加入同目录上一级`linux-imx_%.bbappend`的`SRC_URI_append`，沿用本工程旧Yocto语法。工作目录kernel-source未直接修改；完整构建时由BitBake应用补丁。

### 发送与移除同步

- `rpmsgtty_write()`与设备下线共用每端口`tx_lock`。检查端点和实际发送处于同一临界区，避免“判空之后资源又被释放”的竞态。
- `remove()`首先取得此锁，将`rpdev`设为NULL，再释放锁。此后旧TTY写入返回`-ENODEV`，不再访问RPMsg端点或virtqueue。
- 发送改为`rpmsg_trysend()`，每次最多256字节，避免旧`rpmsg_send()`在缺少TX缓冲时等待15秒。TTY层负责处理短写。
- TX缓冲不足返回`-EAGAIN`；离线期间TTY层也可能返回`EIO`、读到EOF或报告HUP。当前`robobase-rpmsg-test`遇到写错误会退出，这是断链时可接受的行为。自定义持续发送客户端需实现有界重试，不能无限忙等；`write_room()`只报告包长上限/在线状态，不保证当前一定有空闲TX缓冲。
- 这里的“不等待”指不等待空闲RPMsg缓冲。互斥锁、底层kick仍可能耗时，本修复不提供停机时延上界。

### 端口生命周期与RX回调

原`devm_kzalloc()`会让设备解绑直接释放`cport`，而旧TTY的close/cleanup还可能访问它。现在使用普通`kzalloc()`和TTY port引用计数：

| 引用 | 获取 | 释放 |
| --- | --- | --- |
| RPMsg绑定引用 | `tty_port_init()`的初始引用 | devres action中的`tty_port_put()` |
| 已安装TTY引用 | `.install`中的`tty_port_get()` | `.cleanup`中的`tty_port_put()` |

引用按TTY对象而非每次open/close管理，因为多个文件描述符可以共享一个TTY。最后一个引用释放后，由`.destruct`释放`cport`，port缓冲的销毁由TTY port核心完成。

绑定引用不能在驱动`remove()`返回前直接释放。已核对当前5.10 BSP顺序：

```text
rpmsg_dev_remove
  → 驱动remove：关闭发送入口、注销设备、挂断TTY
  → rpmsg_destroy_ept：禁止并等待RX callback结束
返回驱动核心
  → devres_release_all：释放绑定持有的port引用
最后一个旧TTY cleanup
  → 释放TTY持有的引用，必要时最终销毁port
```

后两项也可能相反发生，引用计数保证两者都完成后才销毁。RX回调看到离线状态则丢弃消息；已经进入的回调仍有绑定引用保护。RX复制长度同时改为实际申请到的`space`，避免部分分配时按原`len`越界复制。

### 挂断、重新打开及失败清理

- 下线后请求TTY hangup，并提供`.hangup`实现调用`tty_port_hangup()`。调用挂断时不持有`tx_lock`，避免与TTY内部锁反向嵌套。
- 使用`TTY_DRIVER_DYNAMIC_DEV`显式注册/注销节点。即使旧文件描述符仍未关闭，新M7通道也能注册新的节点；旧TTY不会自动接到新端点。
- 名称采用静态`ttyRPMSG`加`name_base=远端端点号`，保持`/dev/ttyRPMSG30`不变，避免动态名称在旧TTY driver最终销毁之前被释放。
- 初始握手移到设备节点发布前，并采用trysend；失败时不留下已发布节点。注册失败路径与port引用释放对应，消除原来对devm分配对象手动kfree的问题。

## 本地构建与检查

在`myplatform`根目录执行：

```sh
python3 tools/verify-rpmsg-tty-fix.py
```

脚本将补丁应用到临时源码副本（禁止fuzz），用现有MYIR kernel build的配置、Module.symvers和Yocto交叉编译器执行`W=1`外部模块构建，不修改原kernel-source，不访问板端。可通过`--kernel-work`、`--kernel-source`、`--output`指定其他已构建环境；不适用于尚未准备内核配置/符号表的全新工作区。

输出目录：

`build/out/myir_imx8m_plus/diagnostics/rpmsg-tty-stop-fix/`

- `imx_rpmsg_tty.ko`：可供匹配内核台架验证的模块。
- `imx_rpmsg_tty.patched.c`：本次实际编译源码。
- `build.log`、`modinfo.txt`、`manifest.json`：构建日志、模块元数据、模块/补丁/源码/配置/符号表哈希。

本轮结果：补丁可无fuzz应用；ARM64编译、MODPOST和链接通过，`W=1`未报告警告；`checkpatch.pl --no-tree --no-signoff`为0 errors/0 warnings；`git diff --check`通过。checkpatch不检查项目内补丁的DCO签署，不表示已经向上游提交。

模块版本标记：`robobase-safe-teardown-1`。

vermagic：`5.10.72-lts-5.10.y+ge456793341af SMP preempt mod_unload modversions aarch64`。

以上是本地编译/静态检查。用户后续单次、旧FD及10轮板测结果见下文；专项RX并发及长期资源泄漏回归仍待完成。未运行完整BitBake镜像构建。

## 板端临时加载与回滚

先从上次panic干净重启，不启动续租；保持无驱动器、无电机台架。将上述`.ko`通过已有传输方式放到板端`/home/imx_rpmsg_tty.ko`。核对电脑manifest中的SHA256与板端文件，确认板端`uname -r`匹配构建版本。vermagic匹配不等于完整内核ABI身份已验证，不能强制忽略模块版本检查。

```sh
uname -r
sha256sum /home/imx_rpmsg_tty.ko
```

确认没有RPMsg测试程序或其他客户端持有TTY，再执行：

```sh
systemctl stop robobase-rpmsg-tty.service
systemctl stop robobase-m7.service
modprobe -r imx_rpmsg_tty
insmod /home/imx_rpmsg_tty.ko
cat /sys/module/imx_rpmsg_tty/version
systemctl start robobase-m7.service
systemctl start robobase-rpmsg-tty.service
robobase-rpmsg-test --query-status -d /dev/ttyRPMSG30
```

逐条检查执行结果：卸载若报告in use，先找出并关闭客户端，不强制卸载；insmod若报告invalid module format/unknown symbol，保存dmesg并停止后续步骤。版本必须为`robobase-safe-teardown-1`，内核日志应有`registered ttyRPMSG30 (safe teardown v1)`。

上述方法只临时加载新模块，不覆盖`/lib/modules`。正常重启后会加载镜像中的旧模块，不能继续当作修复版测试。回滚可在无客户端时停止两个服务、卸载测试模块，然后`modprobe imx_rpmsg_tty`并启动两个服务；若出现Oops/panic，保存串口后重启，不能继续在受损内核上热恢复。

验收后在已配置的Yocto环境构建`bitbake linux-imx`及`bitbake robobase-image`，让补丁进入正式镜像；此路径与临时模块验证分开记录，不能只替换M7 ELF来修复Linux驱动。

## 板端回归矩阵（原故障单次、旧FD及10轮启停已通过）

每次开始先核对已加载模块版本，启用串口日志。观察不到Oops只是必要条件，还要检查停止能完成、TTY重建、旧FD行为及后续通信。

| 场景 | 操作 | 验收重点 |
| --- | --- | --- |
| 正常路径 | echo、查询、短时续租 | 功能正常，无新增错误 |
| 常规重启 | 退出客户端后stop/start | 节点正常重建，新查询成功 |
| 原故障场景 | 持续续租期间stop M7 | 无Oops/panic；客户端可报EIO/ENODEV/HUP等，服务能停止 |
| 跨重启旧FD | 保留已打开FD，stop/start后再向旧FD写入 | 旧FD失败且不访问新通道；新FD查询成功；关闭旧FD不崩溃 |
| 发送背压 | 无电机环境发送足够多请求 | 可返回EAGAIN，不能卡在旧15秒TX缓冲等待中阻止移除 |
| 重复生命周期 | 前述stop/start重复10次，再扩展到100次 | 无Oops、重复节点注册错误、永久in use；新通道仍可通信 |

只有加载并确认修复模块后，才重新执行原故障场景：

```sh
robobase-rpmsg-test --safety --clear-fault 0xffffffff --lease-timeout-ms 200 -n 100000 -d /dev/ttyRPMSG30 > /home/rb-stop-test.log 2>&1 &
rb_test_pid=$!
```

先确认日志有正常通信，且进程仍在运行；再执行：

```sh
systemctl stop robobase-rpmsg-tty.service
systemctl stop robobase-m7.service
cat /sys/class/remoteproc/remoteproc0/state
```

预期offline且内核无异常。测试进程因断链非零退出可以接受，不要求测试工具全程报ok。保留串口与dmesg，结束剩余测试进程并等待退出，再启动服务、用新进程查询。不要把服务stop成功本身当作完整验收。

“跨重启旧FD”应单独验证，因为一般测试程序遇到断链会退出，不能覆盖长期持有文件描述符的情形。不能将下述单次测试扩大解释为整个矩阵通过。

## 首次修复后板测反馈（2026-09-27）

用户报告前述单次活跃发送stop/start流程“一切正常”，并提供`rb-fixed-after-stop.log`末尾120行：

- 7.667889s是开机旧驱动的`new channel`日志；不能据这条较早日志判断后面的测试仍用旧版。
- 321.302819s旧实例停止，339.633823s加载外部模块。
- 388.590723s明确出现`registered ttyRPMSG30 (safe teardown v1)`，支持修复版已实际工作。
- 880.966343s移除TTY，880.975325s报告remoteproc正常停止；所提供片段无Oops、paging request或panic。
- 用户口头确认恢复通信也正常；本次提供的是停止后日志，未包含此后恢复的STATUS或测试进程退出日志，证据来源应区分。

`loading out-of-tree module taints kernel`是外部构建模块的内核标记，不等于Oops。此处仅记录单次回归通过反馈；独立旧FD跨重启、多轮循环及长期资源检查未验收。M7 ELF日志大小279864字节也不代替固件哈希确认。

## 旧FD与10轮启停自动验证

板端脚本：`tools/board-test-rpmsg-tty-lifecycle.py`，依赖Python 3标准库、systemctl与dmesg。保持无驱动器/电机台架、修复模块已加载、M7及TTY服务已启动，并退出其他TTY客户端。脚本检查模块版本、remoteproc状态、TTY占用及已有内核异常；不满足条件会停止。保持串口记录，内核panic时脚本本身无法保存最终现场。

在电脑传输（板端没有SFTP服务，使用大写`-O`）：

```sh
scp -O /home/compile/workstation/project/codex/myplatform/tools/board-test-rpmsg-tty-lifecycle.py root@192.168.31.51:/home/
```

在主板运行：

```sh
python3 /home/board-test-rpmsg-tty-lifecycle.py --cycles 10
```

默认先测试旧FD跨一次停止/恢复，再执行10轮活跃查询期间停止/恢复。可用`--mode old-fd`或`--mode cycles`分别执行。测试只发送HELLO查询，不发送LEASE或CLEAR_FAULT；因此覆盖发送与拆除并发，不等同满负荷背压、授权输出或所有RX竞态测试。

- 旧FD保持打开，停止后及恢复后写入均必须失败；EBADF不算通过，因为那表示FD已关闭。
- 恢复后在旧FD仍存活时打开新FD并核验STATUS；关闭旧FD后再次查询，检查旧对象释放不影响新通道。
- 每轮先收到至少5个有效回复，再保持查询线程运行并停止服务；断链后线程应退出，恢复后新连接必须正常。查询超时可作为停止期间的断链表现，但单独的超时不能通过旧FD写失败验收。
- 每阶段保存dmesg；遇到Oops、WARNING、Call trace等立即失败，不自动恢复服务。停止后额外观察2秒，覆盖原故障约1秒后的异常窗口。

日志目录在开头显示，为`/home/rb-tty-regression-*`；含`events.log`、每阶段dmesg及`summary.json`。完整通过应输出`OLD_FD PASS`、`CYCLE 1/10 PASS`至`CYCLE 10/10 PASS`和`ALL REQUESTED TESTS PASS`。成功结束时M7运行，但未发送授权租约。

本地已完成8项协议/错误判定检查（正常回复、序号不匹配、短读、超时、EOF、旧FD错误筛选、旧FD错误接受写入、内核异常识别），以及命令行帮助检查；这些不替代板端运行。后续这两项板测已通过，见文末验收记录。

### 脚本前置检查误报修正（2026-09-27）

首次运行在前置检查报告`kernel warning/fault found: bug:`，尚未启停服务。原正则不区分大小写且没有词边界，导致正常`robobase debug:`中的后缀被`BUG:`匹配。已增加词边界并改为输出完整命中行，不删除日志、不绕过异常检查。本地12条正反日志样例及checkpoint保存/拦截检查通过。需重新上传脚本再运行；该次失败不能算旧FD或循环测试失败，也不能算通过。

### 新通道握手回显处理（2026-09-27）

第二次板测前置检查通过，停止后旧FD返回EIO，恢复后safe teardown v1节点重新注册；新FD查询因脚本把`hello world!`回显当STATUS头而失败。用户提供的头部元组可还原为12字节问候语加8字节RFS1帧头；驱动probe会发送该问候语，回显可能在节点打开后才到达。

脚本现仅允许先消费一条完整匹配的问候语，随后严格验证STATUS，全部读取共用原超时；任意未知数据、错误序号或只有问候语均不能通过。setraw使用TCSANOW保留输入，避免刷新丢弃部分回复。没有改内核模块。持久回归测试命令：

```sh
python3 -B -m unittest discover -s tools/tests -p test_rpmsg_tty_lifecycle.py -v
```

7项测试已通过，覆盖正常与带问候语的分段/合并读取、坏帧、错误问候语、超时、序号及debug误报。第二次板测未到恢复后旧FD写入和10轮循环，需更新板端脚本再验收。

## 旧FD与10轮板端验收结果（2026-09-27）

用户使用修订脚本执行默认all模式、`--cycles 10`，日志目录为`/home/rb-tty-regression-w4h46uvc`。后续贴出的events.log末尾80行包含第3至10轮详情，以及：

```text
[3760.364] CYCLE 10/10 PASS
[3760.445] ALL REQUESTED TESTS PASS; M7 running, no lease sent
```

各展示轮次发送线程在停止期间以ENODEV断开；恢复后旧FD写入EIO；旧FD仍持有时新FD能查询STATUS，关闭旧FD后新FD仍能查询。结合默认all模式和失败即停止逻辑，最终标记确认独立旧FD检查与全部10轮完成，且脚本的内核日志检查通过。助手没有独立获取完整dmesg或summary.json，证据为用户提供的执行日志。

状态`state=4, motion=0, fault=12, latched=0`与仅查询、不续租的测试相符：fault=0x0c为Linux及上游超时位。该结果不代表授权输出异常，也不覆盖M7失效后GPIO自动撤销、高负载背压、长期泄漏或全部RX竞态。

本阶段两项验收完成。后续应固化修复模块到正式部署并检查整板重启后的版本及通信；当前仍为临时模块，尚未完成完整Yocto镜像重建。

## 当前板卡持久部署（安装流程已准备，板端执行待确认）

开机服务`robobase-rpmsg-tty-setup`使用`modprobe -q imx_rpmsg_tty`。工具`tools/board-install-rpmsg-tty-fix.py`将已通过板测的外部模块替换到`modinfo -n imx_rpmsg_tty`解析出的系统路径，保留原路径以兼容原有加载方式。此为当前rootfs上的持久部署；源码已接入Yocto补丁，但不表示完整正式镜像已重建，后续刷旧镜像或包更新可能覆盖该文件。

要求当前运行修复版、内核版本匹配。脚本核对源文件SHA256、模块名、版本及完整vermagic；只支持当前内核目录下已有的普通未压缩`.ko`，异常路径/符号链接/压缩文件会拒绝。原文件备份到独立`/home/rb-rpmsg-module-backup-*`，manifest记录目标路径、原始与新版哈希及安装时boot_id。写入使用同目录临时文件、fsync及原子替换，随后depmod并复核解析路径和文件身份；替换后失败会尝试恢复原模块并重新depmod。若回滚也失败，保留报错和备份，先修复磁盘状态再重启。

电脑传输脚本（板端已有已测模块`/home/imx_rpmsg_tty.ko`）：

```sh
scp -O /home/compile/workstation/project/codex/myplatform/tools/board-install-rpmsg-tty-fix.py root@192.168.31.51:/home/
```

板端执行：

```sh
python3 /home/board-install-rpmsg-tty-fix.py /home/imx_rpmsg_tty.ko
```

脚本不会卸载模块、启停服务或重启。仅在输出`INSTALL PASS`后，在无驱动器/电机台架执行`sync`和`reboot`。保留BACKUP路径和串口日志。重新登录后：

```sh
python3 /home/board-install-rpmsg-tty-fix.py --verify
systemctl is-active robobase-m7.service robobase-rpmsg-tty.service
python3 /home/board-test-rpmsg-tty-lifecycle.py --cycles 10
```

`--verify`只读验证磁盘模块及已加载版本，输出当前boot_id；可与备份manifest中的boot_id比较证明经历了重启，本身不强制判定已经重启。验收应同时有重启后VERIFY PASS、服务active和生命周期脚本最终PASS。

人工回滚：从本次BACKUP目录的manifest获取准确target和original_sha256，核对`imx_rpmsg_tty.ko.original`后恢复到该target，运行`depmod -a 5.10.72-lts-5.10.y+ge456793341af`并sync。磁盘回滚不会更换已加载模块；需在台架重启使之生效。原模块含已知活跃发送拆除缺陷，回滚后不要执行该故障注入。

本地验证：5项临时文件测试通过（正常安装备份、depmod失败回滚、错误源哈希拒绝、重复安装保留备份、安装后校验失败回滚）；没有在主机修改/lib/modules，没有代替用户执行板端安装。完整Yocto镜像需后续从已接入0003补丁的layer构建与验收。
