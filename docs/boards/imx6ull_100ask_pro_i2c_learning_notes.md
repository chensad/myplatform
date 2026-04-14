# imx6ull_100ask_pro I2C Learning Notes

这份文档结合当前 `imx6ull_100ask_pro` 板子的原理图和设备树，解释 I2C 协议本身、这块板子上 I2C 总线接了什么、设备树怎么描述 I2C，以及 Linux 下 I2C 应用和驱动应该怎么写。

目标不是只讲抽象协议，而是把：

- 协议层
- 板级连线
- 设备树
- Linux 驱动模型

四层串成一条完整的学习线。

## 1. 先把 I2C 协议讲清楚

I2C 只有两根线：

- `SCL`
  时钟线
- `SDA`
  数据线

它是一个典型的：

- 主从式总线
- 多从设备共享两根线
- 半双工总线
- 开漏/开集电极输出结构

### 1.1 为什么 I2C 能多设备共线

I2C 总线之所以能多个设备共用，是因为：

- 器件不会主动把总线强推高电平
- 器件只能拉低或者释放总线
- 总线变成高电平依赖上拉电阻

所以你以后看原理图时，看到 I2C 一定要同时找：

- `SCL`
- `SDA`
- 上拉电阻
- 供电电压域

没有上拉电阻，I2C 总线基本不成立。

### 1.2 一次 I2C 通信在干什么

一次典型 I2C 访问，大致是：

1. `START`
2. 主机发送从机地址和读写方向位
3. 从机 `ACK`
4. 继续发送寄存器地址或数据
5. 对方继续 `ACK`
6. `STOP`

如果是“读寄存器”，通常流程是：

1. 先写寄存器地址
2. 再发一次重复起始 `RESTART`
3. 然后按读方向把数据读回来

所以 I2C 本质上不是 UART 那种“连续字节流”，而是：

- 带地址的
- 带应答的
- 带起始/停止条件的

## 2. 这块板子上 I2C 在哪里

### 2.1 原理图总图里已经把 I2C 拉出来了

从底板原理图第 2 页连接器总图，可以直接看到：

- `I2C1_SCL`
- `I2C1_SDA`
- `I2C2_SCL`
- `I2C2_SDA`

原理图：

- [/mnt/e/BaiduNetdiskDownload/02_100ask_imx6ull_pro_2022.08/04_开发板原理图/01_Base_board(底板)/100ask_imx6ull_v1.1.pdf](/mnt/e/BaiduNetdiskDownload/02_100ask_imx6ull_pro_2022.08/04_开发板原理图/01_Base_board(底板)/100ask_imx6ull_v1.1.pdf)

这一步说明：

- SoC 至少有两路 I2C 在底板上被实际接出
- 后续要做的是继续追这两路总线上挂了哪些设备

## 3. 当前设备树里启用了哪两路 I2C

板级 DTS 在：

[100ask_imx6ull-14x14.dts](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts)

### 3.1 I2C1

[i2c1 节点](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L254)

```dts
&i2c1 {
    clock-frequency = <100000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_i2c1>;
    status = "okay";
};
```

这表示：

- `i2c1` 总线已启用
- 工作频率 `100kHz`
- 绑定了 `pinctrl_i2c1`

但当前 DTS 里没有在 `i2c1` 节点下面继续挂具体从设备节点。  
这本身就是一个很重要的学习点：

**原理图里有设备，不代表当前 DTS 一定已经把它们都描述出来了。**

### 3.2 I2C2

[i2c2 节点](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L261)

```dts
&i2c2 {
    clock_frequency = <100000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_i2c2>;
    status = "okay";
    ...
};
```

这说明：

- `i2c2` 也已启用
- 频率目标同样是 `100kHz`
- 它下面还挂了多个从设备节点

这里还顺便暴露了一个细节：

- `i2c1` 用的是 `clock-frequency`
- `i2c2` 这里写成了 `clock_frequency`

从设备树属性规范角度，标准写法应是 `clock-frequency`。这类小差异以后你做 DTS 审查时要能识别出来。

## 4. pinctrl 里 I2C 是怎么配的

### 4.1 I2C1 的 pinctrl

[pinctrl_i2c1](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L464)

```dts
pinctrl_i2c1: i2c1grp {
    fsl,pins = <
        MX6UL_PAD_UART4_TX_DATA__I2C1_SCL 0x4001b8b0
        MX6UL_PAD_UART4_RX_DATA__I2C1_SDA 0x4001b8b0
    >;
};
```

这说明：

- `UART4_TX_DATA` 这根 pad 被复用成 `I2C1_SCL`
- `UART4_RX_DATA` 这根 pad 被复用成 `I2C1_SDA`

这再次说明一个重要事实：

**pad 原始名字不等于当前功能。**

原始 pad 名字看起来像 UART4，并不代表当前它真在做 UART4。

### 4.2 I2C2 的 pinctrl

[pinctrl_i2c2](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L471)

```dts
pinctrl_i2c2: i2c2grp {
    fsl,pins = <
        MX6UL_PAD_UART5_TX_DATA__I2C2_SCL 0x4001b8b0
        MX6UL_PAD_UART5_RX_DATA__I2C2_SDA 0x4001b8b0
    >;
};
```

这表示：

- `UART5_TX_DATA -> I2C2_SCL`
- `UART5_RX_DATA -> I2C2_SDA`

所以从 pinctrl 角度看：

- `i2c1` 使用的是 UART4 那组 pad
- `i2c2` 使用的是 UART5 那组 pad

## 5. 这块板子上 I2C2 挂了哪些设备

当前 DTS 里，`i2c2` 下面挂了 3 类典型设备，这些都很适合拿来学 I2C。

### 5.1 音频 codec：WM8960

[wm8960 节点](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L267)

```dts
codec: wm8960@1a {
    compatible = "wlf,wm8960";
    reg = <0x1a>;
    clocks = <&clks IMX6UL_CLK_SAI2>;
    clock-names = "mclk";
    wlf,shared-lrclk;
};
```

这表示：

- 设备挂在 `i2c2`
- I2C 地址是 `0x1a`
- Linux 用 `wlf,wm8960` 驱动来匹配

原理图文本里也能看到 `WM8960`，说明板子上确实有这颗音频 codec。

这里最值得你理解的是：

**I2C 在 WM8960 上主要是控制平面，不是音频数据平面。**

也就是说：

- I2C 负责配置寄存器
- 真正的音频数据通常走 `SAI/I2S`

### 5.2 HDMI 发射相关芯片：SiI902x

[sii902x 节点](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L274)

```dts
sii902x: sii902x@39 {
    compatible = "SiI,sii902x";
    reg = <0x39>;
    ...
};
```

这表示：

- 这颗芯片也挂在 `i2c2`
- 地址是 `0x39`

原理图文本里也能看到：

- `I2C2_SCL`
- `I2C2_SDA`
- HDMI 相关的 `HDMI_DSCL/HDMI_DSDA`

这说明：

- `i2c2` 在这块板子上还承担了 HDMI 相关外设的控制通路

### 5.3 触摸芯片：Goodix GT9xx

[gt9xx 节点](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L289)

```dts
gt9xx@5d {
    compatible = "goodix,gt9xx";
    reg = <0x5d>;
    status = "okay";
    interrupt-parent = <&gpio1>;
    interrupts = <5 IRQ_TYPE_EDGE_FALLING>;
    reset-gpios = <&gpio5 2 GPIO_ACTIVE_LOW>;
    irq-gpios = <&gpio1 5 IRQ_TYPE_EDGE_FALLING>;
    ...
};
```

这说明：

- 触摸芯片挂在 `i2c2`
- I2C 地址是 `0x5d`
- 除了 I2C 总线外，它还依赖：
  - `reset-gpio`
  - `irq-gpio`

这是一个非常典型、非常真实的 I2C 设备模型：

- I2C 负责收发寄存器/数据
- GPIO 负责复位
- IRQ 负责中断通知

所以学 I2C 驱动时，不要只盯着 `SCL/SDA` 两根线。  
真实设备经常还要配合：

- reset
- interrupt
- power-enable

## 6. I2C1 在这块板子上的学习价值

虽然 DTS 没有在 `i2c1` 下挂具体从设备，但原理图文本里能看到一个典型器件：

- `AP3216C`

并且它和：

- `I2C1_SCL`
- `I2C1_SDA`

连在一起。

这说明：

- 板子上 `i2c1` 这路总线并不是空的
- 只是当前 DTS 没有把它完整描述出来

这反而很适合学习，因为它能训练你理解：

**原理图里有设备，Linux 不一定已经启用它；驱动开发经常要补的就是这层 DTS 和驱动接入。**

所以 `i2c1` 适合你做：

- 地址扫描
- 总线联通性验证
- 练习自己补一个 I2C 从设备节点

## 7. 为什么原理图和 DTS 必须一起看

只看原理图，你只能知道：

- 板子上连了哪些芯片
- `SCL/SDA` 走到了哪里
- 有没有上拉电阻
- 有没有 `INT` / `RST`

只看 DTS，你只能知道：

- Linux 打算怎么启用这些设备
- 驱动匹配字符串是什么
- 地址是多少
- 还额外用了哪些 GPIO/IRQ

把两者合起来，才能真正看懂一个 I2C 设备。

以 `gt9xx` 为例：

1. 原理图告诉你：
   - 触摸芯片挂在 I2C2
   - 它还带中断线和复位线
2. DTS 告诉你：
   - 地址是 `0x5d`
   - `compatible = "goodix,gt9xx"`
   - 使用了 `reset-gpios` 和 `irq-gpios`
3. Linux 驱动层才会进一步做：
   - I2C probe
   - 复位控制
   - 中断注册

这就是完整的板级驱动认知链。

## 8. I2C 设备树节点该怎么读

以：

```dts
codec: wm8960@1a {
    compatible = "wlf,wm8960";
    reg = <0x1a>;
    ...
};
```

为例：

### `wm8960@1a`

节点名通常写成：

- `设备名@地址`

### `compatible`

告诉内核该用哪个驱动来匹配。

### `reg = <0x1a>`

对 I2C 设备来说，`reg` 不是 MMIO 基地址，而是：

**I2C 从机地址**

这个点非常关键。

## 9. Linux 下 I2C 应用该怎么写

用户态常见有两条路。

### 9.1 直接用 Linux I2C 工具

例如：

- `i2cdetect`
- `i2cget`
- `i2cset`
- `i2ctransfer`

典型用途：

- 扫总线地址
- 验证设备是否在线
- 调简单寄存器

### 9.2 自己写程序访问 `/dev/i2c-X`

常见流程：

1. `open("/dev/i2c-X", ...)`
2. `ioctl(fd, I2C_SLAVE, addr)`
3. `read/write`
4. 或者使用 `I2C_RDWR` 做组合事务

适合：

- 调试传感器寄存器
- 做板级联调
- 封装用户态驱动库

### 9.3 当前项目里的 `i2c-tools` 从哪里来

你当前板子上跑的：

- `i2cdetect`
- `i2cget`
- `i2cset`
- `i2ctransfer`

通常不是系统凭空自带，而是 Buildroot 打进去的。

在当前 `myplatform` 仓库里，`i2c-tools` 的 Buildroot package 定义在：

- [i2c-tools.mk](/home/compile/workstation/project/codex/myplatform/third_party/buildroot/buildroot-2020.02/package/i2c-tools/i2c-tools.mk)
- [Config.in](/home/compile/workstation/project/codex/myplatform/third_party/buildroot/buildroot-2020.02/package/i2c-tools/Config.in)

从这里可以直接看出：

- 当前 Buildroot 使用的版本是 `i2c-tools 4.1`
- 源码下载地址来自 `kernel.org`
- 编译完成后会安装到 target 和 staging

如果你已经跑过 Buildroot，实际展开后的源码通常能在输出目录里找到。当前这套工程里对应路径是：

- [i2c-tools-4.1](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1)

以后你想看某个工具到底怎么实现，不要只盯着板子上的二进制，优先到这个源码目录里看。

### 9.4 `i2c-tools` 源码最值得先看的几个文件

如果你现在最关心的是“一个命令怎么从用户态一路走到 I2C 控制器”，建议优先看这几份源码：

- [tools/i2cget.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/tools/i2cget.c)
- [tools/i2cset.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/tools/i2cset.c)
- [tools/i2cbusses.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/tools/i2cbusses.c)
- [lib/smbus.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/lib/smbus.c)
- [include/i2c/smbus.h](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/include/i2c/smbus.h)
- [i2c-dev.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/include/uapi/linux/i2c-dev.h)

它们的职责大致是：

- `i2cget.c`
  处理命令行参数，决定做哪种读操作
- `i2cset.c`
  处理命令行参数，决定做哪种写操作
- `i2cbusses.c`
  打开 `/dev/i2c-X`，并通过 `ioctl(I2C_SLAVE)` 选中从设备地址
- `smbus.c`
  把读写操作统一封装成 `ioctl(I2C_SMBUS)`
- `smbus.h`
  声明各种 `i2c_smbus_*` 接口
- `i2c-dev.h`
  定义用户态和内核 `i2c-dev` 通信时用到的 ioctl 命令

### 9.5 `i2cget` 的调用链是怎么走的

以：

```bash
i2cget -y 0 0x1e 0x0c
```

为例，它大致会走下面这条链：

1. `main()` 解析参数
2. `open_i2c_dev()` 打开 `/dev/i2c-0`
3. `ioctl(I2C_FUNCS)` 查询当前 adapter 支持哪些能力
4. `set_slave_addr()` 通过 `ioctl(I2C_SLAVE)` 选择从地址 `0x1e`
5. 根据模式调用 `i2c_smbus_read_byte_data()`
6. `i2c_smbus_read_byte_data()` 继续调用 `i2c_smbus_access()`
7. `i2c_smbus_access()` 最终通过 `ioctl(I2C_SMBUS)` 把请求交给内核

对应源码位置：

- [i2cget.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/tools/i2cget.c)
- [i2cbusses.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/tools/i2cbusses.c)
- [smbus.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/lib/smbus.c)

你可以把这条链记成：

- `i2cget main`
- `open /dev/i2c-X`
- `I2C_SLAVE`
- `i2c_smbus_read_*`
- `I2C_SMBUS ioctl`

也就是说：

- `I2C_SLAVE`
  只是“选中要访问哪个从设备”
- `I2C_SMBUS`
  才是真正“发起一次读写事务”

### 9.6 `i2cset` 的调用链是怎么走的

以：

```bash
i2cset -y 0 0x1e 0x00 0x03
```

为例，它大致会走下面这条链：

1. `main()` 解析总线号、从地址、寄存器地址、要写的值、模式
2. `open_i2c_dev()` 打开 `/dev/i2c-0`
3. `ioctl(I2C_FUNCS)` 检查 adapter 能力
4. `set_slave_addr()` 通过 `ioctl(I2C_SLAVE)` 选择从设备
5. 默认 `b` 模式下，调用 `i2c_smbus_write_byte_data()`
6. `i2c_smbus_write_byte_data()` 再调用 `i2c_smbus_access()`
7. `i2c_smbus_access()` 最终通过 `ioctl(I2C_SMBUS)` 把写请求交给内核

对应源码位置：

- [i2cset.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/tools/i2cset.c)
- [i2cbusses.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/tools/i2cbusses.c)
- [smbus.c](/home/compile/workstation/project/codex/myplatform/build/out/imx6ull_100ask_pro/demo_console/buildroot/build/i2c-tools-4.1/lib/smbus.c)

如果把它翻成更直白的话，`i2cset -y 0 0x1e 0x00 0x03` 干的事就是：

- 打开 `i2c-0`
- 选中从设备 `0x1e`
- 把 `0x00` 当成寄存器地址
- 把 `0x03` 当成要写的数据
- 通过 `I2C_SMBUS` ioctl 把这次事务交给内核驱动执行

### 9.7 为什么 `i2cget` / `i2cset` 特别适合调寄存器设备

这是因为它们常用的访问接口本质上是 SMBus 风格：

- `i2c_smbus_read_byte_data(file, command)`
- `i2c_smbus_write_byte_data(file, command, value)`
- `i2c_smbus_read_word_data(file, command)`
- `i2c_smbus_write_word_data(file, command, value)`

这里的：

- `command`
  很适合对应“寄存器地址”
- `value`
  很适合对应“寄存器值”

因此对于：

- AP3216C
- EEPROM
- RTC
- 绝大多数传感器

这种“寄存器式 I2C 设备”，`i2cget/i2cset` 用起来会非常顺手。

比如 AP3216C 的：

```bash
i2cset -y 0 0x1e 0x00 0x03
```

就可以直接理解成：

- 向 `0x1e` 这个 I2C 从设备
- 的 `0x00` 寄存器
- 写入 `0x03`

也就是把 `REG_SYSTEM_CONFIG` 配成 `ALS + PS + IR continuous mode`。

### 9.8 `i2c-tools` 常见接口和用途

你现在最常用的几个命令，建议这样理解。

#### `i2cdetect`

作用：

- 扫总线
- 看哪些地址有设备响应

示例：

```bash
i2cdetect -y 0
```

适合做：

- 板级联通性确认
- 确认 AP3216C 是否真的在 `0x1e`
- 确认设备到底挂在哪条总线上

#### `i2cget`

作用：

- 读某个寄存器
- 读某个状态值

示例：

```bash
i2cget -y 0 0x1e 0x00
i2cget -y 0 0x1e 0x0c
i2cget -y 0 0x1e 0x0d
```

适合做：

- 验证某个配置寄存器是否写成功
- 读传感器状态
- 单独读一个数据字节

#### `i2cset`

作用：

- 写某个寄存器
- 改配置
- 发复位或模式切换命令

示例：

```bash
i2cset -y 0 0x1e 0x00 0x04
i2cset -y 0 0x1e 0x00 0x03
i2cset -y 0 0x1e 0x00 0x00
```

分别可以理解成：

- 软件复位
- 进入连续测量模式
- 进入掉电模式

#### `i2cdump`

作用：

- 一次性查看一整片寄存器空间

示例：

```bash
i2cdump -y 0 0x1e
```

适合做：

- 比较初始化前后寄存器变化
- 观察强光照射前后 ALS 寄存器变化
- 快速排查“到底哪个寄存器没配对”

#### `i2ctransfer`

作用：

- 发送更接近原始 I2C 的组合事务
- 在一条命令里同时做多段读写

它和 `i2cget/i2cset` 不同的地方在于：

- `i2cget/i2cset` 更多是 SMBus 风格访问
- `i2ctransfer` 直接走 `I2C_RDWR`

这类方式更接近你以后自己写用户态 I2C 程序时会使用的：

- `struct i2c_msg`
- `struct i2c_rdwr_ioctl_data`
- `ioctl(fd, I2C_RDWR, ...)`

### 9.9 结合 `24C16` 理解 EEPROM 是什么

`24C16` 是一类很典型的 I2C EEPROM。

`EEPROM` 全称是：

- `Electrically Erasable Programmable Read-Only Memory`

它的特点是：

- 掉电不丢数据
- 容量通常不大
- 常用来存少量但长期保留的信息

典型用途包括：

- 板卡 ID
- 序列号
- MAC 地址
- 出厂参数
- 传感器校准值

它和常见存储器的区别可以先粗略记成：

- `RAM`
  断电丢失，运行时临时存储
- `Flash`
  断电不丢，容量更大，常用来存程序和文件系统
- `EEPROM`
  断电不丢，容量较小，适合存配置和身份信息

### 9.10 为什么 `24C16` 会同时出现在 `0x50~0x57`

很多人第一次看到 `i2cdetect` 输出：

```text
50 51 52 53 54 55 56 57
```

会以为板子上突然多了 8 个器件。

对 `24C16` 来说，通常不是 8 个独立器件，而是：

- 1 颗 EEPROM
- 总共 2048 字节
- 被分成 8 个 256 字节地址窗口
- 每个窗口映射到 `0x50~0x57` 中的一个 I2C 地址

所以：

- `0x50` 对应第 0 个 256B block
- `0x51` 对应第 1 个 256B block
- ...
- `0x57` 对应第 7 个 256B block

这就是为什么扫描总线时会看到一串连续地址。

### 9.11 `i2cdump` 看到的到底是什么

对 EEPROM 来说，`i2cdump` 看到的不是“自动解析好的业务信息”，而是：

- 某个地址窗口里按偏移排布的原始字节

例如：

```bash
i2cdump -y 0 0x50
```

看到的是：

- `24C16` 第 0 个地址窗口里的 256 个字节

而：

```bash
i2cdump -y 0 0x51
```

看到的是：

- 第 1 个地址窗口里的 256 个字节

这些字节到底代表：

- 板卡信息
- 字符串
- 校准参数
- 还是空白区

取决于上层软件或板级规范怎么定义，而不是 EEPROM 自己天然知道。

如果某个区域全是：

```text
ff ff ff ff ...
```

通常表示：

- 这块区域还没写过
- 或者当前正处于擦空态

### 9.12 `eeprom24c16` 这个用户态工具是怎么映射地址的

当前仓库里已经放了一个直接使用 `I2C_RDWR` 的示例工具：

- [eeprom24c16.c](/home/compile/workstation/project/codex/myplatform/apps/private/eeprom24c16/eeprom24c16.c)

它没有再去调用 `i2cget/i2cset`，而是自己完成：

- 打开 `/dev/i2c-X`
- 计算 `24C16` 的 block 地址
- 组装 `struct i2c_msg`
- 调 `ioctl(fd, I2C_RDWR, ...)`

核心地址换算逻辑是：

- 先根据总偏移算出当前属于哪个 256B block
- 再把 block 号加到 `base_addr`
- 剩下的低 8 位作为 block 内偏移

也就是：

- `addr = base_addr + offset / 256`
- `reg = offset % 256`

例如：

- `offset = 0x000`
  对应 `addr = 0x50`, `reg = 0x00`
- `offset = 0x120`
  对应 `addr = 0x51`, `reg = 0x20`

### 9.13 为什么 `read_chunk` 和 `write_chunk` 长得不一样

很多人第一次看 EEPROM 代码时会疑惑：

- 为什么写只用 1 条 `i2c_msg`
- 读却要用 2 条 `i2c_msg`

根本原因是：

- EEPROM 的读事务和写事务本来就不是同一种协议流程

对 `write_chunk()` 来说，主机要做的是：

1. 发从设备地址，方向为写
2. 发 block 内偏移
3. 紧接着把待写入的数据发过去

所以一条消息里就能把：

- 地址偏移
- 数据字节

一起带上。

而 `read_chunk()` 的逻辑是：

1. 先发一条写消息，只告诉 EEPROM：
   - “把内部地址指针移动到哪个偏移”
2. 再发一条读消息，把数据读回来

也就是说，读流程本质上是：

- 先“写地址”
- 再“读数据”

在 I2C 总线上通常表现成：

- `START`
- 从地址 + 写
- 内部偏移
- `RESTART`
- 从地址 + 读
- 数据返回
- `STOP`

所以 `read_chunk()` 需要两条 `i2c_msg`，而 `write_chunk()` 只需要一条。

### 9.14 `eeprom_wait_ready()` 在等什么

`eeprom_wait_ready()` 的作用不是“读取数据”，而是：

- 等待 EEPROM 完成一次内部写周期

这点和普通寄存器设备很不一样。

像很多传感器寄存器：

- 你把值写进去
- 几乎立刻就能继续下一次访问

但 EEPROM 不一样：

- 总线上的写事务结束后
- 芯片内部还要花几毫秒把数据真正写进非易失存储单元
- 在这段时间里，器件可能暂时不响应新的访问

所以标准做法通常是：

- 写完以后不要立即继续读写
- 先做一段 `ACK polling`
- 等它重新应答后再继续下一次事务

当前工具里的：

- [eeprom_wait_ready()](/home/compile/workstation/project/codex/myplatform/apps/private/eeprom24c16/eeprom24c16.c#L94)

就是在做这个事情。

它的实现思路是：

1. 构造一条很小的 I2C 写消息
2. 反复调用 `ioctl(fd, I2C_RDWR, &rdwr)`
3. 如果 EEPROM 重新 ACK，这条消息就会成功
4. 一旦成功，就说明这次写周期已经完成

这类方法通常叫：

- `ACK polling`
- `write-cycle polling`

你可以把它理解成：

- 写完 page 后，程序不断去问 EEPROM：
  - “你现在忙完了吗？”
  - “我现在可以继续访问你了吗？”

### 9.15 为什么这里直接用 `ioctl(I2C_RDWR)`，而不是 `i2c_smbus_*`

这是因为 `24C16` 这类 EEPROM 的访问模型更接近“原始 I2C 组合事务”，而不是单纯的 SMBus byte-data 风格。

如果你只做最简单的单字节寄存器访问，`i2c_smbus_*` 往往很方便。

但对当前这个 `24C16` 工具来说，有几个现实原因更适合直接走：

- `I2C_RDWR`

#### 原因 1：需要自己控制“先写地址再读”的两段事务

`read_chunk()` 的核心就是：

- 第 1 段写内部偏移
- 第 2 段读数据

这天然就是：

- `struct i2c_msg msgs[2]`
- `ioctl(fd, I2C_RDWR, ...)`

这种模型表达起来最直接。

#### 原因 2：要跨 `24C16` 的地址窗口做偏移映射

这个工具不是只访问一个固定 I2C 地址下的单个寄存器，而是：

- 按总偏移在 `0x50~0x57` 之间切换
- 每一段 block 再指定内部偏移

直接用 `I2C_RDWR` 自己组消息，更容易把这种“block 地址 + block 内偏移”的逻辑写清楚。

#### 原因 3：要自己做 page write 和写后轮询

这个工具需要同时处理：

- page boundary
- block boundary
- 写后 ACK polling

如果再套一层 `i2c_smbus_*`，并不会让逻辑更清晰，反而会把 EEPROM 的真实访问过程藏起来。

#### 原因 4：这是更接近底层 I2C 思维的教学写法

当前这个工具本身就兼顾：

- 实用
- 学习

直接用：

- `struct i2c_msg`
- `struct i2c_rdwr_ioctl_data`
- `ioctl(fd, I2C_RDWR, ...)`

更容易让你把用户态 I2C 访问和总线事务一一对应起来。

所以可以这样理解：

- `i2cget/i2cset`
  更像“现成的调试工具”
- `i2c_smbus_*`
  更像“对 SMBus 风格寄存器访问的函数封装”
- `I2C_RDWR`
  更像“用户态最通用、最接近底层事务模型的接口”

对于 `24C16` 这种 EEPROM 示例，当前这个工具选择 `I2C_RDWR` 是合理的。

## 10. Linux 下 I2C 驱动该怎么写

内核态 I2C 驱动通常走：

- `struct i2c_driver`
- `struct i2c_client`
- `probe/remove`
- `of_match_table`

一个典型 I2C 驱动通常会做这些事：

1. 根据 `compatible` 匹配设备
2. 从 `client->addr` 拿到 I2C 地址
3. 用 `i2c_smbus_*` 或 `i2c_transfer()` 访问寄存器
4. 如果设备还有 GPIO/IRQ/电源，就顺带申请：
   - `reset-gpios`
   - `irq`
   - regulator
5. 接入对应子系统：
   - input
   - codec
   - rtc
   - hwmon
   - backlight
   - 其他

所以一个真实 I2C 驱动通常不是“只有两根线”的驱动，而是：

- I2C 总线访问
- GPIO/IRQ/电源控制
- 某个功能子系统接入

三部分组合在一起。

## 11. 对这块板子，I2C 最推荐的学习顺序

建议按下面这个梯度来学。

### 第一步：先把协议层吃透

你至少要彻底理解：

- `SCL/SDA`
- 上拉电阻
- 开漏
- 地址
- ACK/NACK
- START/STOP

### 第二步：先练总线调试，不急着写驱动

在板子上先做这些动作：

- 看总线节点
- 扫地址
- 读写一个简单寄存器

### 第三步：拿 `wm8960` 学“设备树中的 I2C 从设备”

因为它的 DTS 结构清晰：

- 地址明确
- compatible 明确
- 它作为 codec 的角色也很明确

### 第四步：拿 `gt9xx` 学“真实 I2C 设备不止 I2C 两根线”

因为它同时涉及：

- I2C
- reset-gpio
- irq-gpio

这比只看纯 I2C 协议更接近真实驱动开发。

## 12. 当前这块板子上，你最该记住的几点

- I2C 是两根线共享总线，不是 UART 那种点对点字节流
- I2C 依赖上拉电阻和开漏结构
- DTS 里 I2C 从设备的 `reg` 表示的是设备地址
- `i2c1` / `i2c2` 是总线
- `wm8960@1a` / `gt9xx@5d` / `sii902x@39` 是挂在总线上的从设备
- 原理图告诉你板子上连了什么
- DTS 告诉你 Linux 打算怎么启用它们
- 真正的设备驱动往往还要配合 GPIO/IRQ，不是只管 `SCL/SDA`

## 13. 你下一步最值得做的实验

建议按这个顺序：

1. 用工具扫描 I2C 总线，确认当前在线设备地址
2. 对照 DTS 验证：
   - `0x1a`
   - `0x39`
   - `0x5d`
   是否出现
3. 选一个最简单的 I2C 从设备，先做用户态读写实验
4. 再去看对应 Linux 驱动的 `probe` 流程

先把“总线能不能通、设备地址对不对、DTS 是否一致”这三件事吃透，再进驱动，会稳很多。
