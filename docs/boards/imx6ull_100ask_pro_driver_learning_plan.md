# imx6ull_100ask_pro Linux Driver Learning Plan

这份计划面向当前角色是“嵌入式应用开发工程师”，目标是在 `100ask_imx6ull_pro` 板子上系统学习 Linux 驱动，而不是零散做几个 demo。

这份计划强调 4 件事：

- 先建立板级硬件认知，再写驱动
- 先掌握字符设备、GPIO、设备树，再进复杂子系统
- 每一阶段都要有可验证的实验产出
- 所有实验都尽量绑定到 `imx6ull` 这块板子的真实接口

## 学习目标

学完这份计划后，至少要做到：

- 能独立读 `imx6ull` 板级原理图，知道一个外设如何从连接器追到 SoC
- 能独立修改设备树、重新编译内核或 dtb，并验证 pinmux/外设节点是否生效
- 能写出最小字符设备驱动、platform 驱动、基于设备树的驱动
- 能理解并使用常见子系统：
  - GPIO
  - pinctrl
  - irq
  - input
  - i2c
  - spi
  - net phy / mac
  - tty / rs485
- 能看懂板级 DTS 和 pinctrl 配置，知道引脚冲突在哪里
- 能独立排查“驱动没工作”到底是：
  - 原理图理解错误
  - pinmux 冲突
  - 设备树节点错误
  - 驱动 probe 失败
  - 用户态验证方法错误

## 前置准备

开始前，先确保你能稳定完成这些动作：

- 编译 Buildroot：

```bash
make BOARD=imx6ull_100ask_pro buildroot
```

- 单独编 app：

```bash
make BOARD=imx6ull_100ask_pro app
make BOARD=imx6ull_100ask_pro app PUBLIC_APPS="app_demo"
make BOARD=imx6ull_100ask_pro app PRIVATE_APPS="detect_gps"
```

- 单独重编 Linux：

```bash
make BOARD=imx6ull_100ask_pro linux
```

- 能把 `zImage`、`dtb`、`rootfs` 更新到板子并启动
- 能通过串口或网络稳定登录板子
- 能在板子上执行：
  - `dmesg`
  - `cat /proc/device-tree/...`
  - `ls /sys/class`
  - `ls /sys/bus`
  - `devmem` 或等效工具
  - `hexdump`

如果这些还不熟，先补下面文档：

- [build_guide.md](/home/compile/workstation/project/codex/myplatform/docs/build_guide.md)
- [README_PLATFORM.md](/home/compile/workstation/project/codex/myplatform/README_PLATFORM.md)
- [imx6ull_100ask_pro_uart_learning_notes.md](/home/compile/workstation/project/codex/myplatform/docs/boards/imx6ull_100ask_pro_uart_learning_notes.md)

## 资料与源码入口

### 板级资料

重点使用这些资料：

- 底板原理图  
  `/mnt/e/BaiduNetdiskDownload/02_100ask_imx6ull_pro_2022.08/04_开发板原理图/01_Base_board(底板)/100ask_imx6ull_v1.1.pdf`
- 丝印图  
  `/mnt/e/BaiduNetdiskDownload/02_100ask_imx6ull_pro_2022.08/04_开发板原理图/01_Base_board(底板)/100ask_imx6ull_PRO_V11_silktop(丝印图).pdf`
- 核心板原理图  
  `/mnt/e/BaiduNetdiskDownload/02_100ask_imx6ull_pro_2022.08/04_开发板原理图/02_Core_board(核心板)/MYC-Y6ULX1211.pdf`
- 核心板引脚表  
  `/mnt/e/BaiduNetdiskDownload/02_100ask_imx6ull_pro_2022.08/04_开发板原理图/02_Core_board(核心板)/MYC-Y6ULX_Pin_list_V13.xlsx`
- 学习手册  
  `/mnt/e/BaiduNetdiskDownload/02_100ask_imx6ull_pro_2022.08/01_学习手册/嵌入式Linux应用开发完全手册V5.3_IMX6ULL_Pro开发板.pdf`

### 当前仓库里的关键源码

- 板级设备树  
  [100ask_imx6ull-14x14.dts](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts)
- 芯片级设备树  
  [imx6ull.dtsi](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull.dtsi)
- pinfunc 宏  
  [imx6ull-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull-pinfunc.h)
- 内核源码根目录  
  [imx-linux4.9.88](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88)

## 这块板子最适合拿来学习驱动的接口

优先级按学习价值排序：

- LED / KEY
  最适合入门 GPIO、字符设备、input、irq
- RS485
  最适合理解 UART、收发器、方向控制、设备树属性
- CAN
  最适合理解 pinmux 复用、收发器、总线接口
- I2C 触摸 / I2C codec
  最适合理解 I2C 子系统和设备树从设备节点
- SPI 设备
  最适合理解总线、片选、设备树挂载、spidev 与专用驱动差异
- ADC / PWM
  最适合理解通用外设框架和用户态验证
- Ethernet PHY
  最适合理解 MAC/PHY 分层、MDIO、phy-handle
- LCD / Touch / Audio
  最适合后期进入完整子系统，但不适合前期入门

当前板级 DTS 已明确启用的部分接口包括：

- `uart1`、`uart3`、`uart6`
- `i2c1`、`i2c2`
- `ecspi1`、`ecspi3`
- `flexcan1`
- `fec1`、`fec2`
- `lcdif`
- `sai2`
- `adc1`
- `pwm1`

参考：
[100ask_imx6ull-14x14.dts](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts)

## 总体学习阶段

建议按 6 个阶段推进，每个阶段结束都要产出代码和记录。

### 阶段 0：建立硬件与 DTS 基础认知

目标：

- 能看懂原理图中一个接口怎么从连接器追到 SoC
- 能把原理图里的信号名和 DTS 里的 pinctrl 对上
- 能理解一个 pad 的复用关系

必须完成：

- 用原理图和 DTS 手工画出下面 4 条链路：
  - `LED`
  - `KEY`
  - `UART3 -> RS485`
  - `UART3_CTS/RTS -> FLEXCAN1`
- 写出一份你自己的“J5 复用表”
  - 原始原理图定义
  - 当前 DTS 定义
  - 冲突点

重点文件：

- [100ask_imx6ull-14x14.dts](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts)
- [imx6ull-pinfunc.h](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull-pinfunc.h)

阶段产出：

- 一份你自己写的板级接口笔记
- 一份 `J5 / J16 / J17 / J6 / J7` 对照表

### 阶段 1：字符设备与最小 GPIO 驱动

目标：

- 建立驱动最基本框架
- 理解 `open/read/write/ioctl/poll`
- 理解设备号、`cdev`、`class`、设备节点

建议练习顺序：

1. `hello` 字符设备驱动
2. LED 驱动
3. 按键驱动，先查询方式
4. 按键驱动，再中断方式

板上绑定对象：

- `LED`
- `KEY1`
- `KEY2`

建议掌握的内核接口：

- `alloc_chrdev_region`
- `cdev_init`
- `cdev_add`
- `class_create`
- `device_create`
- `copy_to_user`
- `copy_from_user`
- `gpio_request` / `gpiod_*`
- `request_irq`
- `free_irq`

阶段产出：

- `hello_drv.ko`
- `led_drv.ko`
- `key_drv.ko`
- 配套测试 app
- 一份实验记录：
  - 设备节点名
  - 驱动加载日志
  - 用户态操作方法

### 阶段 2：平台驱动与设备树

目标：

- 从“硬编码 GPIO”升级到“基于设备树取资源”
- 建立 `platform_device/platform_driver` 认知
- 掌握 pinctrl、gpio、irq 资源从 DTS 获取的方法

建议练习顺序：

1. 把 LED 驱动改成 platform 驱动
2. 从设备树读取 GPIO 与有效电平
3. 把按键驱动改成设备树版本
4. 增加 `irq`、`debounce`、`pinctrl` 的 DTS 属性

建议掌握的接口：

- `of_find_node_by_path`
- `of_property_read_*`
- `of_get_named_gpio`
- `platform_get_resource`
- `platform_get_irq`
- `devm_*`
- `gpiod_get`
- `of_match_table`

重点掌握：

- `compatible`
- `status`
- `pinctrl-names`
- `pinctrl-0`
- `gpios`
- `interrupt-parent`
- `interrupts`

阶段产出：

- 一个基于设备树的 LED 驱动
- 一个基于设备树的按键驱动
- 你自己写的 DTS patch

### 阶段 3：总线驱动基础，先 I2C 再 SPI

目标：

- 理解“控制器驱动”和“设备驱动”是两层
- 学会从原理图、设备树和总线枚举定位设备
- 知道什么时候用 `spidev/i2c-dev`，什么时候写专用驱动

#### 3.1 I2C

优先练习对象：

- 触摸芯片 `gt9xx`
- 音频 codec `wm8960`
- 先用用户态工具感知总线，再写简单驱动

建议动作：

- 看 `i2c1`、`i2c2` 的 DTS 与 pinctrl
- 用 `i2cdetect`、`i2cget`、`i2cset`
- 写一个最小 I2C client 驱动
- 理解 `probe/remove`

#### 3.2 SPI

优先练习对象：

- `ecspi1`
- `ecspi3`
- 先从 `spidev` 或简单 SPI 从设备开始

建议动作：

- 看 `cs-gpios`
- 理解 `spi-max-frequency`
- 写一个最小 `spi_driver`

阶段产出：

- 一份 I2C 总线拓扑图
- 一份 SPI 总线拓扑图
- 一个最小 I2C 驱动
- 一个最小 SPI 驱动

### 阶段 4：串口、RS485、CAN

目标：

- 理解串口控制器与外部收发器的关系
- 理解 pad 复用与板级外设冲突
- 掌握 RS485 和 CAN 的设备树配置方法

#### 4.1 UART / RS485

重点看：

- `uart3`
- `pinctrl_uart3`
- `pinctrl_485_ctl`

目标：

- 看懂 `rs485-rts-active-high`
- 看懂 `linux,rs485-enabled-at-boot-time`
- 理解为什么 `uart3` 仍然是串口驱动，但外部接口是 RS485

#### 4.2 CAN

重点看：

- `flexcan1`
- `pinctrl_flexcan1`
- `UART3_CTS_B__FLEXCAN1_TX`
- `UART3_RTS_B__FLEXCAN1_RX`

目标：

- 搞清楚为什么原理图上写 `UART3_CTS/RTS`，但 DTS 里是 `FLEXCAN1`
- 理解这是 pinmux，不是协议混用
- 能验证 CAN 口是否起来

阶段产出：

- 一份 `UART3 / RS485 / CAN` 复用冲突分析
- 一份实验记录：
  - 开 RS485 时哪些脚被占用
  - 开 CAN 时哪些脚被占用

### 阶段 5：网络、输入、ADC、PWM

目标：

- 接触标准子系统
- 不再只停留在字符设备模型

建议顺序：

1. `adc1`
2. `pwm1`
3. `gpio-keys` / input
4. `fec1/fec2 + phy`

你要学会：

- `sysfs` / `iio` / `input event`
- `ethtool`
- `phy-handle`
- `mdio`

阶段产出：

- 一个 ADC 测试记录
- 一个 PWM 测试记录
- 一份双网口拓扑和 PHY 关系笔记

### 阶段 6：显示、触摸、音频与系统级调试

目标：

- 进入复杂子系统
- 学会跨越原理图、DTS、驱动、用户态验证的完整链路

建议顺序：

1. LCDIF
2. Touch
3. WM8960 / SAI2
4. 如果后续真要学 camera，再回头看 `J5`

注意：

- 这一阶段不适合一开始就学
- 它涉及 pinctrl、clk、regulator、bus、irq、firmware、userspace 多层联动

阶段产出：

- 一份显示子系统启动链路笔记
- 一份触摸屏中断链路笔记
- 一份音频播放采集链路笔记

## 建议时间安排

如果按业余系统学习节奏，建议 12 周。

### 第 1-2 周

- 阶段 0
- 目标是把原理图、连接器、DTS、pinctrl 对上

### 第 3-4 周

- 阶段 1
- 完成最小字符设备 + LED + KEY

### 第 5-6 周

- 阶段 2
- 完成 platform 驱动 + 设备树版本 LED/KEY

### 第 7-8 周

- 阶段 3
- I2C / SPI 总线实验

### 第 9 周

- 阶段 4
- UART / RS485 / CAN

### 第 10 周

- 阶段 5
- ADC / PWM / input / ethernet

### 第 11-12 周

- 阶段 6
- LCD / touch / audio

## 每周固定动作

不管学到哪一阶段，每周都保持这 5 个固定动作：

1. 读 1 个接口的原理图
2. 读 1 个接口的 DTS 和 pinctrl
3. 读 1 个内核驱动源码入口
4. 做 1 个最小实验
5. 写 1 份实验记录

建议实验记录至少包括：

- 目标接口
- 原理图页码
- DTS 节点
- pinctrl 配置
- 编译命令
- 烧录方式
- 运行日志
- 成功条件
- 问题与结论

## 你当前最合理的学习主线

结合你现在的背景是“应用开发工程师”，不要一上来啃复杂子系统。当前最合理的主线是：

1. 原理图阅读方法
2. 字符设备
3. GPIO / pinctrl / irq
4. 设备树
5. I2C / SPI
6. UART / RS485 / CAN
7. input / ADC / PWM
8. net / audio / display

也就是说：

- 先学“驱动的骨架”
- 再学“总线和资源获取”
- 最后学“复杂子系统”

这个顺序比“从 camera / LCD / audio 起步”更稳。

## 不建议的学习方式

下面这些方式效率很低：

- 只看视频不动手改 DTS
- 只会 `insmod/rmmod`，不会看设备树和 pinmux
- 直接上摄像头、LCD、音频，跳过 GPIO / I2C / SPI
- 只会背 API，不会从原理图判断电平和复用
- 只看板级 demo，不去读内核已有驱动

## 每阶段的完成判定

你不要用“看完了”判断自己是否学会，要用“能不能独立做出来”判断。

### 阶段 0 完成标志

- 能解释 `J5` 为什么原理图叫 camera，但现在被拿去做 `I2C + SPI + UART + ADC`
- 能解释 `J16` 是 RS485、`J17` 是 CAN
- 能解释为什么 `UART3_CTS/RTS` 可以变成 `FLEXCAN1`

### 阶段 1 完成标志

- 能自己写一个最小字符设备驱动
- 能自己控制 LED
- 能自己读取按键

### 阶段 2 完成标志

- 能自己增加一个设备树节点
- 能让驱动通过 `compatible` 成功 probe

### 阶段 3 完成标志

- 能解释 I2C/SPI controller 和 device 的区别
- 能自己挂一个 I2C/SPI 从设备节点并验证

### 阶段 4 完成标志

- 能独立解释 RS485 与 CAN 的硬件链路
- 能判断 pinmux 冲突

### 阶段 5-6 完成标志

- 能独立读一个复杂子系统的 DTS
- 能通过日志、sysfs、原理图定位问题

## 后续建议

建议把这份计划变成实际工作流，而不是只当阅读文档。

推荐你再补两个目录：

- `docs/boards/imx6ull_100ask_pro_lab_notes/`
  用来放每个接口的实验记录
- `docs/boards/imx6ull_100ask_pro_signal_maps/`
  用来放你自己整理的信号对照表

如果后续继续推进，下一份最值得写的文档是：

- `imx6ull_100ask_pro_j5_mux_map.md`

专门把 `J5` 的原理图定义、设备树复用和扩展板丝印一一对应起来。
