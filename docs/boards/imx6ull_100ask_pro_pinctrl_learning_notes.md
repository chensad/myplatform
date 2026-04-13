# imx6ull_100ask_pro Pinctrl Learning Notes

这份文档专门解释 `imx6ull` 设备树里的 `pinctrl` 怎么看、怎么理解、怎么和外设节点对应起来。

目标不是把 pinctrl 讲成一堆抽象概念，而是让你能结合当前板子的真实 DTS，读懂：

- 一根 pad 为什么能复用成不同功能
- `pinctrl_xxx` 节点到底在描述什么
- `pinctrl-0 = <&xxx>` 为什么要写
- `pinctrl` 和 `gpio` 到底是什么关系

## 1. 先把 pinctrl 的本质说清楚

不要先把 `pinctrl` 当成“设备树里的特殊语法”。  
它本质上只做一件事：

**告诉内核：某个外设工作时，哪些物理引脚要切成什么功能，并且这些引脚的电气参数是什么。**

在 `imx6ull` 这类 SoC 上，一个物理引脚通常不是只能做一件事。  
同一根 pad 可能既能做：

- GPIO
- UART TX/RX
- I2C
- SPI
- PWM
- LCD/CSI

所以在设备树里，必须有一层配置把它“切换”到当前要用的功能，这层就是 `pinctrl`。

## 2. 一根引脚其实有 3 层含义

你可以把一根 SoC 引脚拆成 3 层理解：

1. 物理 pad
   芯片上的真实引脚，比如 `CSI_MCLK`

2. 复用功能 mux
   这根 pad 当前到底拿来干什么，比如：
   - `UART6_DCE_TX`
   - `GPIO4_IO17`
   - `CSI_MCLK`

3. 电气配置 pad control
   这根引脚的上拉、下拉、驱动能力、速度、施密特触发等参数

`pinctrl` 同时管的是第 2 和第 3 层。

## 3. 当前板子里的一个真实例子

看你当前板级 DTS：

[pinctrl_uart6](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L513)

```dts
pinctrl_uart6: uart6grp {
    fsl,pins = <
        MX6UL_PAD_CSI_MCLK__UART6_DCE_TX      0x1b0b1
        MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX    0x1b0b1
    >;
};
```

逐个拆开看。

### 3.1 `MX6UL_PAD_CSI_MCLK__UART6_DCE_TX`

这表示：

- `MX6UL_PAD_CSI_MCLK`
  这根 pad 的原始名字叫 `CSI_MCLK`

- `__UART6_DCE_TX`
  当前把它复用成 `uart6` 的发送脚

所以这行的真实含义就是：

**把 `CSI_MCLK` 这根物理引脚切换成 `uart6 tx` 功能。**

### 3.2 `MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX`

同理：

- `CSI_PIXCLK`
  是这根 pad 的原始名字
- `UART6_DCE_RX`
  表示当前把它切成 `uart6` 的接收脚

所以当前 DTS 的结论非常明确：

- `CSI_MCLK -> uart6 tx`
- `CSI_PIXCLK -> uart6 rx`

更严格一点写，是：

- `CSI_MCLK -> UART6_DCE_TX`
- `CSI_PIXCLK -> UART6_DCE_RX`

### 3.3 `0x1b0b1`

这是这根引脚的电气配置值，也就是 pad control。

你现在先不用一开始就背 bit 位。  
先建立这个认知就够了：

- 左边决定“这根脚干什么”
- 右边决定“这根脚怎么驱动”

后面再结合芯片参考手册，慢慢把：

- 上拉/下拉
- 驱动能力
- 速度
- 开漏
- 迟滞

这些位字段吃透。

## 4. 为什么要单独定义一个 `pinctrl_uart6`

因为 `uart6` 这个外设节点本身不会凭空知道“自己该用哪两根脚”。

它只知道：

- 我是 `uart6` 控制器

但它不知道：

- TX 用哪根 pad
- RX 用哪根 pad
- 这些 pad 的电气参数应该怎么配

所以必须先定义一组“引脚方案”，例如：

```dts
pinctrl_uart6: uart6grp { ... };
```

然后再在设备节点里引用它。

## 5. `&uart6` 里是怎么把 pinctrl 用起来的

看这段：

[uart6](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L852)

```dts
&uart6 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart6>;
    status = "okay";
};
```

逐行解释：

### `&uart6 { ... }`

表示修改 SoC 里已经存在的 `uart6` 节点。

### `pinctrl-names = "default";`

表示这个设备有一个 pinctrl 状态，名字叫 `default`。

你可以把它理解成：

- 设备正常工作时用这套引脚配置

有些设备不止一个状态，还可能有：

- `sleep`
- `idle`

例如：

```dts
pinctrl-names = "default", "sleep";
pinctrl-0 = <&pinctrl_uart6>;
pinctrl-1 = <&pinctrl_uart6_sleep>;
```

表示：

- 正常工作时用一套
- 休眠时切到另一套

但入门阶段先只看 `default` 就够了。

### `pinctrl-0 = <&pinctrl_uart6>;`

这句最关键。

意思是：

- `default` 这个状态使用 `pinctrl_uart6` 这组引脚配置

也就是把前面定义好的那套 pad 复用方案，真正绑定给 `uart6`。

### `status = "okay";`

启用这个 UART 设备。

少了这段，即使 `pinctrl_uart6` 存在，驱动也不会把这路串口跑起来。

## 6. pinctrl 的完整工作流

以后你看到 pinctrl，固定按这三步理解：

1. 先定义一组引脚方案
   例如 `pinctrl_uart6`

2. 在设备节点里声明有哪些状态
   例如 `pinctrl-names = "default"`

3. 把某个状态绑定到那组引脚方案
   例如 `pinctrl-0 = <&pinctrl_uart6>`

## 7. 为什么不直接在 `&uart6` 里写 pad 配置

因为 pinctrl 的设计就是把：

- 引脚配置
- 设备节点

分开管理。

这样做的好处是：

- 结构更清晰
- 可以复用
- 可以支持多个状态
- 不同设备都按统一模式引用

否则所有 pad 配置都散在设备节点里，后期很难维护。

## 8. `pinctrl` 和 `gpio` 到底是什么关系

很多人第一次看 DTS 时，最容易把这两个混在一起。

### 8.1 `pinctrl`

决定的是：

- 这根 pad 现在是什么功能
- 这根 pad 的电气属性是什么

### 8.2 `gpio`

是这根 pad 被切成 GPIO 功能后，再去读写它的电平

所以：

- `pinctrl` 决定“它是不是 GPIO”
- `gpio` 决定“GPIO 模式下怎么用它”

例如一根脚本来既可做 UART，也可做 GPIO：

- 如果 pinctrl 把它切成 `UART6_TX`
  那它就不能再当普通 GPIO 用

- 如果 pinctrl 把它切成 `GPIO4_IO17`
  那你才能在别的节点里写 `gpios = <&gpio4 17 ...>`

## 9. 再看一个 GPIO 场景

像 LED 这类设备，通常会同时看到两层配置：

1. pinctrl 里把 pad 切成 GPIO
2. 设备节点里通过 `gpios = <...>` 使用它

逻辑一般会像这样：

```dts
pinctrl_leds: ledgrp {
    fsl,pins = <
        MX6UL_PAD_SNVS_TAMPER3__GPIO5_IO03 0x10b0
    >;
};

leds {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_leds>;

    led0 {
        gpios = <&gpio5 3 GPIO_ACTIVE_LOW>;
    };
};
```

这里两句不是重复：

- `MX6UL_PAD_...__GPIO5_IO03`
  是在说“这根 pad 被切成 GPIO5_IO03”

- `gpios = <&gpio5 3 GPIO_ACTIVE_LOW>`
  是在说“这个 LED 节点使用 gpio5 的第 3 根线，而且低电平有效”

## 10. `fsl,pins` 里的宏从哪里来

这些宏定义在：

[imx6ull-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull-pinfunc.h)

例如会有这类定义：

```c
#define MX6UL_PAD_CSI_MCLK__UART6_DCE_TX ...
```

这些宏不是普通名字，它们编码了：

- mux 寄存器位置
- pad control 寄存器位置
- 复用选择值
- 输入选择寄存器等信息

所以设备树里写的不是“给人看的标签”，而是 pinctrl 驱动真正会拿去配置硬件寄存器的参数。

### 10.1 为什么有些宏明明不在 `imx6ull-pinfunc.h` 里也能用

这个点非常容易让人困惑。

以当前 DTS 里用到的这两个宏为例：

- `MX6UL_PAD_CSI_MCLK__UART6_DCE_TX`
- `MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX`

你如果直接在 [imx6ull-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull-pinfunc.h) 里搜，可能找不到它们的定义。原因不是“设备树会魔法展开”，而是包含链是这样的：

1. 板级 DTS 包含  
   [imx6ull.dtsi](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull.dtsi)
2. `imx6ull.dtsi` 包含  
   [imx6ull-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull-pinfunc.h)
3. [imx6ull-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull-pinfunc.h#L11) 又包含  
   [imx6ul-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ul-pinfunc.h)

也就是说：

- `imx6ull-pinfunc.h` 并不是把所有 pin 宏都重新定义一遍
- 它是先复用 `imx6ul-pinfunc.h`
- 再在本文件里补或覆盖 `6ULL` 和 `6UL` 不同的那部分宏

所以，这两个宏实际上定义在：

- [imx6ul-pinfunc.h#L865](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ul-pinfunc.h#L865)
- [imx6ul-pinfunc.h#L874](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ul-pinfunc.h#L874)

真实定义分别是：

```c
#define MX6UL_PAD_CSI_MCLK__UART6_DCE_TX        0x01d4 0x0460 0x0000 8 0
#define MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX      0x01d8 0x0464 0x064c 8 3
```

### 10.2 宏到底展开成什么

[imx6ull-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull-pinfunc.h#L13) 开头已经写了说明：

```c
/*
 * The pin function ID is a tuple of
 * <mux_reg conf_reg input_reg mux_mode input_val>
 */
```

所以：

```c
#define MX6UL_PAD_CSI_MCLK__UART6_DCE_TX  0x01d4 0x0460 0x0000 8 0
```

展开后就是这 5 个字段：

1. `mux_reg = 0x01d4`
   复用功能选择寄存器偏移
2. `conf_reg = 0x0460`
   pad 电气配置寄存器偏移
3. `input_reg = 0x0000`
   输入选择寄存器偏移
4. `mux_mode = 8`
   表示选第 8 路复用功能
5. `input_val = 0`
   输入选择值

对应 RX 这条：

```c
#define MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX  0x01d8 0x0464 0x064c 8 3
```

展开后是：

1. `mux_reg = 0x01d8`
2. `conf_reg = 0x0464`
3. `input_reg = 0x064c`
4. `mux_mode = 8`
5. `input_val = 3`

这说明：

- TX 这根脚不需要额外配置输入路径，所以 `input_reg` 是 `0x0000`
- RX 这根脚是输入脚，需要额外配置输入选择器，所以有 `input_reg = 0x064c`

### 10.3 为什么 DTS 里后面还要再写一个 `0x1b0b1`

你在 DTS 里看到的是：

```dts
MX6UL_PAD_CSI_MCLK__UART6_DCE_TX      0x1b0b1
```

这不是说宏本身只有一个值，而是：

- 宏先展开成 5 个字段
- DTS 里再额外补 1 个 pad 电气配置值

所以它在 `fsl,pins` 里最终等价于概念上的：

```text
<0x01d4 0x0460 0x0000 8 0 0x1b0b1>
```

也就是：

```text
<mux_reg conf_reg input_reg mux_mode input_val pad_ctrl>
```

这里：

- 前 5 个值来自 pinfunc 宏
- 最后 1 个值 `0x1b0b1` 是设备树里写的 pad 电气参数

### 10.4 为什么 pinctrl 需要这些参数

因为 pinctrl 最终不是在“理解业务含义”，而是在**写硬件寄存器**。

这些参数存在的原因是：内核必须知道要改哪几个寄存器、往里面写什么值，才能把某个 pad 真的切成某个功能。

例如：

```c
#define MX6UL_PAD_CSI_MCLK__UART6_DCE_TX  0x01d4 0x0460 0x0000 8 0
```

它不是“描述性文字”，而是给 pinctrl 驱动的硬件配置坐标。驱动需要至少知道：

- 去哪个 `mux` 寄存器写值
- 去哪个 `pad control` 寄存器写电气参数
- 这根输入脚是否还要配置 `input select` 寄存器
- 该选哪一路复用功能
- 如果有输入选择，该选哪一路输入来源

否则驱动只知道“你想把它变成 UART6_TX”，但并不知道：

- 改哪个寄存器
- 写哪个值
- 有没有额外输入路径要切

所以这些参数本质上是：

**把一个功能名字翻译成具体寄存器操作所需的最小信息集。**

### 10.5 这 5 个参数怎么把 pad 和 UART6 对应起来

关键点是：

**对应关系不是运行时算出来的，而是芯片厂商已经在 pinfunc 宏里预先编码好了。**

也就是说：

- `MX6UL_PAD_CSI_MCLK__UART6_DCE_TX`
  这个宏本身就代表：
  “把 `CSI_MCLK` 这根 pad 切成 `UART6_DCE_TX`，需要这样配寄存器”

- `MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX`
  这个宏本身就代表：
  “把 `CSI_PIXCLK` 这根 pad 切成 `UART6_DCE_RX`，需要这样配寄存器”

所以“pad 和 UART6 的对应关系”不是 DTS 运行时推理出来的，而是：

1. 芯片手册先定义硬件复用关系
2. pinfunc 头文件把这种复用关系写成宏
3. DTS 只是选择了要用哪一个宏

### 10.6 TX 和 RX 为什么参数不一样

这点很重要。

#### TX 一般更简单

以：

```c
MX6UL_PAD_CSI_MCLK__UART6_DCE_TX  0x01d4 0x0460 0x0000 8 0
```

为例：

- `mux_reg = 0x01d4`
- `conf_reg = 0x0460`
- `input_reg = 0x0000`
- `mux_mode = 8`
- `input_val = 0`

对 TX 脚来说，SoC 只需要把这根 pad 切成 UART 发送功能，然后往外驱动数据。  
因此通常不需要额外配置输入路径，所以 `input_reg` 往往是 `0x0000`。

#### RX 一般还要配置输入路径

以：

```c
MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX  0x01d8 0x0464 0x064c 8 3
```

为例：

- `mux_reg = 0x01d8`
- `conf_reg = 0x0464`
- `input_reg = 0x064c`
- `mux_mode = 8`
- `input_val = 3`

对 RX 脚来说，除了把 pad 切成 UART 接收功能，还要告诉芯片内部：

- 这一路 UART 的输入信号应该从哪根 pad 进来

所以 RX 宏常常比 TX 宏多一个实际生效的 `input_reg/input_val`。

## 11. 用一个文字示意图把它串起来

你可以把当前 `uart6` 的两根脚理解成下面这样。

### 11.1 `CSI_MCLK -> mux -> UART6_TX`

```text
物理 pad: CSI_MCLK
    |
    |  mux_reg = 0x01d4
    |  mux_mode = 8
    v
复用功能: UART6_DCE_TX
    |
    |  conf_reg = 0x0460
    |  pad_ctrl = 0x1b0b1
    v
最终效果: 这根脚作为 uart6 的 TX 输出
```

这里没有额外 `input select`，因为它是发送脚。

### 11.2 `CSI_PIXCLK -> mux + input select -> UART6_RX`

```text
物理 pad: CSI_PIXCLK
    |
    |  mux_reg = 0x01d8
    |  mux_mode = 8
    v
复用功能: UART6_DCE_RX
    |
    |  input_reg = 0x064c
    |  input_val = 3
    |  告诉芯片内部：uart6 的 RX 输入从这根 pad 进来
    v
输入路径绑定完成
    |
    |  conf_reg = 0x0464
    |  pad_ctrl = 0x1b0b1
    v
最终效果: 这根脚作为 uart6 的 RX 输入
```

### 11.3 为什么 `&uart6` 还要再引用 `pinctrl_uart6`

前面的宏和 `fsl,pins` 只是在定义：

- 这两根 pad 应该怎么配

而：

```dts
&uart6 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart6>;
    status = "okay";
};
```

才是在声明：

- `uart6` 这个设备，默认就使用这组 pad 配置

所以完整绑定关系分成两段：

1. `fsl,pins`
   决定 pad 到功能的映射
2. `pinctrl-0 = <&pinctrl_uart6>`
   决定这组映射属于哪个设备

## 11. `0x1b0b1` 这种值该怎么学

这类值是电气参数，不建议你一开始死背。

更务实的学习顺序是：

1. 先知道它是“pad 电气配置”
2. 改 pinmux 时优先复用板上已经验证过的稳定值
3. 后面再结合参考手册逐 bit 理解它的含义

入门阶段，把左边的：

- `PAD__FUNC`

和右边的：

- `pad control value`

区分开，就已经跨过最重要的门槛了。

## 12. 你以后该怎么读一个 pinctrl 配置

建议固定按这个模板读。

### 12.1 先看 pinctrl 组本身

例如：

```dts
pinctrl_uart6: uart6grp {
    fsl,pins = <
        MX6UL_PAD_CSI_MCLK__UART6_DCE_TX      0x1b0b1
        MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX    0x1b0b1
    >;
};
```

问自己两个问题：

1. 哪些 pad 被用了？
2. 它们分别被切成了什么功能？

### 12.2 再看设备节点怎么引用

例如：

```dts
&uart6 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart6>;
    status = "okay";
};
```

再问两个问题：

1. 这组 pinctrl 绑定给了哪个设备？
2. 设备是不是启用了？

这样你就能把“引脚”和“外设”真正串起来。

## 13. 什么叫 pinctrl 冲突

当同一根 pad 被两个功能都想占用时，就会冲突。

例如你这块板子的 J5 一带，很多 pad 原本叫：

- `CSI_MCLK`
- `CSI_PIXCLK`
- `CSI_DATAx`

但当前 DTS 已经把它们拿去做了：

- `uart6`
- `ecspi1`
- 其他复用功能

所以如果你又想把它们重新拿去跑 camera/CSI，就会和现有配置冲突。

这也是为什么设备树里 `pinctrl` 是核心，不是边角。

## 14. 对你现在最重要的一句话

你至少要把这句话彻底吃透：

**设备树里的 pinctrl，不是在“声明设备存在”，而是在“给设备分配并配置引脚”。**

设备节点解决的是：

- 我是谁
- 我开不开

而 pinctrl 解决的是：

- 我到底走哪几根脚
- 这些脚切成什么功能
- 这些脚的电气参数怎么配

## 15. 建议你按这个顺序学 pinctrl

1. 先看 `uart6`
   因为只有两根脚，最清楚

2. 再看 `leds`
   学会 `PAD__GPIOx_IOy` 和 `gpios = <...>` 的区别

3. 再看 `uart3 + rs485`
   学会 pinctrl 和外设属性一起配

4. 再看 `ecspi1`
   学会一组设备往往不止 2 根脚，而是 `SCLK/MOSI/MISO/CS`

这样你会比只看抽象概念更快懂，也更容易和板级原理图、驱动代码对应起来。
