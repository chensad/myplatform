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
