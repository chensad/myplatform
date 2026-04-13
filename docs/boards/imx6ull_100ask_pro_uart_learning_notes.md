# imx6ull_100ask_pro UART Learning Notes

这份文档不是泛泛讲 UART，而是结合当前 `imx6ull_100ask_pro` 板子、当前设备树和 `detect_gps` 应用，把 UART 的协议、电气、设备树、内核驱动和用户态编程串成一条线。

## 1. 先把 UART 说清楚

### 1.1 UART 是什么

UART，`Universal Asynchronous Receiver/Transmitter`，本质上是一种异步串行通信方式。它有几个核心特点：

- 异步
  不额外提供时钟线，通信双方靠事先约定好的波特率采样
- 全双工
  `TX` 和 `RX` 各一根线，可以同时发送和接收
- 点对点
  最典型的是两个设备直接对接
- 帧结构固定
  通常由起始位、数据位、可选校验位、停止位组成

最常见的参数写法就是：

- `9600 8N1`

意思是：

- 波特率 `9600`
- 数据位 `8`
- 无校验 `N`
- 停止位 `1`

### 1.2 UART 线上真正传的是什么

UART 在线上看到的是一串按位变化的电平。接收方并不知道什么时候“自然开始”，所以需要起始位做同步。

一个典型 `8N1` 帧长这样：

1. 空闲态通常为高电平
2. 起始位 1 位，低电平
3. 数据位 8 位，低位在前
4. 无校验位
5. 停止位 1 位，高电平

如果波特率是 `9600`，每一位时间大约是：

```text
1 / 9600 ≈ 104.17 us
```

所以收发双方波特率一旦不一致，采样点就会逐步漂移，最后看到乱码或者根本无法识别帧。

### 1.3 UART 协议层和电气层不是一回事

这点在板级开发里非常关键。

- UART
  是收发逻辑和帧格式
- TTL UART
  是常见开发板/模组之间的 3.3V 或 1.8V 串口电平
- RS232
  是更老的串口电平标准，电压摆幅和 TTL 不兼容
- RS485
  是差分总线物理层，常用于工业现场

所以：

- `uart3 + RS485 收发器` 仍然是 UART 协议
- `NEO-6M 模块 TXD/RXD` 一般是 TTL UART，不是 RS232

## 2. 这块板子的 UART 在哪里

### 2.1 imx6ull 的串口别名

芯片级公共设备树在 [imx6ull.dtsi](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/arch/arm/boot/dts/imx6ull.dtsi#L18) 里定义了串口别名：

```dts
serial0 = &uart1;
serial1 = &uart2;
serial2 = &uart3;
serial3 = &uart4;
serial4 = &uart5;
serial5 = &uart6;
serial6 = &uart7;
serial7 = &uart8;
```

这一步的作用是给每路 UART 一个稳定编号。

### 2.2 为什么 `uart6` 对应 `/dev/ttymxc5`

当前内核串口驱动在 [imx.c](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/drivers/tty/serial/imx.c#L177) 里把设备名前缀定义为：

```c
#define DEV_NAME "ttymxc"
```

然后在 probe 阶段通过设备树 alias 取串口序号，见 [imx.c](/home/compile/workstation/project/codex/myplatform/third_party/linux/imx-linux4.9.88/drivers/tty/serial/imx.c#L2075)：

```c
ret = of_alias_get_id(np, "serial");
sport->port.line = ret;
```

所以：

- `uart1 -> serial0 -> /dev/ttymxc0`
- `uart3 -> serial2 -> /dev/ttymxc2`
- `uart6 -> serial5 -> /dev/ttymxc5`

这就是当前板子上 `uart6` 在 Linux 用户态看到 `/dev/ttymxc5` 的原因。

## 3. 当前板级 DTS 里 `uart6` 是怎么启用的

当前板级设备树在：
[100ask_imx6ull-14x14.dts](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts)

### 3.1 pinctrl_uart6

[100ask_imx6ull-14x14.dts#L513](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L513)

```dts
pinctrl_uart6: uart6grp {
    fsl,pins = <
        MX6UL_PAD_CSI_MCLK__UART6_DCE_TX      0x1b0b1
        MX6UL_PAD_CSI_PIXCLK__UART6_DCE_RX    0x1b0b1
    >;
};
```

这段的含义：

- `CSI_MCLK`
  这根 SoC pad 原本的名字偏向 camera/CSI 功能
- `__UART6_DCE_TX`
  表示当前把它复用成 `uart6` 的发送脚
- `CSI_PIXCLK`
  原本也是 camera/CSI 命名
- `__UART6_DCE_RX`
  当前把它复用成 `uart6` 的接收脚

所以，当前这份 DTS 的结论非常明确：

- `CSI_MCLK -> uart6 tx`
- `CSI_PIXCLK -> uart6 rx`

更严格地说，是：

- `CSI_MCLK -> UART6_DCE_TX`
- `CSI_PIXCLK -> UART6_DCE_RX`

### 3.2 uart6 节点本身

[100ask_imx6ull-14x14.dts#L852](/home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/linux/dts/100ask_imx6ull-14x14.dts#L852)

```dts
&uart6 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart6>;
    status = "okay";
};
```

这段的含义：

- `&uart6`
  修改 SoC 继承下来的 `uart6` 控制器节点
- `pinctrl-names = "default"`
  设备正常工作时采用默认引脚组
- `pinctrl-0 = <&pinctrl_uart6>`
  把上面的 `pinctrl_uart6` 真正绑定到 `uart6`
- `status = "okay"`
  启用这个 UART

少了这段，即使 `pinctrl_uart6` 存在，驱动也不会把这路串口跑起来。

## 4. `detect_gps` 里 UART 相关代码怎么理解

当前应用代码在：
[gps_read.c](/home/compile/workstation/project/codex/myplatform/apps/private/detect_gps/gps_read.c)

### 4.1 应用做了哪几件事

这份程序从 UART 角度看，只做了 5 件事：

1. 打开串口设备
2. 设置波特率、数据位、校验、停止位
3. 用 `select + read` 按字节读取
4. 等到一整行 NMEA 报文结束
5. 只解析 `GGA` 报文并打印经纬度

### 4.2 打开串口

[gps_read.c#L106](/home/compile/workstation/project/codex/myplatform/apps/private/detect_gps/gps_read.c#L106)

```c
fd = open(com, O_RDWR | O_NOCTTY);
```

这里的关键点：

- `O_RDWR`
  打开收发两个方向
- `O_NOCTTY`
  不要把这个串口当作当前进程的控制终端

这很重要，因为 `/dev/ttymxc5` 是业务串口，不应该让 shell/终端控制语义混进去。

### 4.3 串口参数设置

[gps_read.c#L42](/home/compile/workstation/project/codex/myplatform/apps/private/detect_gps/gps_read.c#L42)

`set_opt()` 的职责是把串口设成你要的通信参数。它用了标准 `termios` 接口：

- `tcgetattr`
  先拿旧参数
- `cfsetispeed/cfsetospeed`
  设输入输出波特率
- `CS8`
  8 位数据位
- `~PARENB`
  无校验
- `~CSTOPB`
  1 位停止位
- `CLOCAL | CREAD`
  本地连接、允许接收
- `tcsetattr`
  提交新参数

当前程序支持：

- `2400`
- `4800`
- `9600`
- `115200`

你现场排查时经常要改的就是这一段。

### 4.4 为什么现在不会再“完全静默”

旧版逻辑里：

- `VMIN=1`
- `VTIME=0`
- `read()` 永久阻塞

只要线上一字节都没有，程序就会看起来像“死住了”。

现在改成了：

- `select()` 先等可读
- 超时后返回 `GPS_READ_TIMEOUT`
- 主循环打印：

```text
read timeout: no GPS data within 3 sec
```

所以这版程序的价值不是“更高级”，而是“更适合现场排查”。

### 4.5 为什么只解析 `GGA`

[gps_read.c#L176](/home/compile/workstation/project/codex/myplatform/apps/private/detect_gps/gps_read.c#L176)

当前解析函数里写死了：

```c
else if (strncmp(buf+3, "GGA", 3) != 0)
    return -1;
```

也就是说：

- `$GPGGA`
- `$GNGGA`

这样的报文会进入解析

而：

- `RMC`
- `VTG`
- `GSA`
- `GSV`

这些即使收到，也只会打印原始数据，不会进入经纬度打印逻辑。

这也是一个很典型的“应用层协议解析”例子：

- UART 只负责把字节流送上来
- 真正理解报文内容的是你的用户态程序

## 5. UART 应用程序应该怎么写

### 5.1 最小正确步骤

如果你在 Linux 用户态写 UART 应用，建议固定按这个顺序：

1. `open("/dev/ttyXXX", O_RDWR | O_NOCTTY | O_NONBLOCK?)`
2. `tcgetattr`
3. 设置 `termios`
4. `tcsetattr`
5. `tcflush`
6. `select/poll/epoll`
7. `read/write`
8. 根据你的协议做分包、校验、状态机解析

### 5.2 不要把“串口收字节”和“协议解析”写混

更好的工程分层应该是：

- UART 层
  只负责收发字节流
- 协议层
  只负责根据换行符、帧头、长度、CRC 分包
- 业务层
  只负责解释字段含义

放到 GPS 上就是：

- UART 层
  从 `/dev/ttymxc5` 读字节
- 协议层
  按 `\r\n` 拼出 NMEA 句子
- 业务层
  解析 `GGA/RMC`

### 5.3 应用层常见坑

- 波特率设错
- `TX/RX` 接反
- 没共地
- 线上的并不是 TTL UART，而是 RS232/RS485
- 读函数永久阻塞，没有任何超时日志
- 协议解析只支持一种报文，现场看起来像“没收到”
- 忽略了设备上电、复位、使能引脚

## 6. UART 驱动应该怎么理解

### 6.1 先分清你写的是哪一类“UART 驱动”

工程里经常把“UART 驱动”这个词说得太粗。

实际上有 3 类东西：

1. UART 控制器驱动
   例如当前内核里的 `drivers/tty/serial/imx.c`
   这是 SoC 串口控制器本身的驱动

2. UART 挂载设备的驱动
   例如某个串口屏、GNSS、蓝牙、4G 模块
   它们不是 UART 控制器，只是挂在 UART 总线上的外设

3. UART 用户态应用
   例如当前的 `detect_gps`

大多数板级开发和业务开发，真正要写的不是第 1 类，而是第 2 或第 3 类。

### 6.2 什么时候需要写 UART 控制器驱动

只有当下面这些情况发生时，才会碰 SoC UART 控制器驱动：

- 新 SoC 没有现成串口驱动
- 你要改 DMA、FIFO、中断、RS485 控制等底层行为
- 你在调 tty/serial core 级别的问题

在这块板子上，一般不需要从零写 `imx` UART 控制器驱动，因为内核已经有了。

### 6.3 设备树在 UART 驱动里的角色

对控制器驱动来说，设备树主要提供：

- 设备节点是否启用
- 寄存器地址
- IRQ
- 时钟
- pinctrl
- 可选流控、RS485 参数

对挂在 UART 上的设备来说，设备树通常还会描述：

- `reset-gpios`
- `enable-gpios`
- `power-gpios`
- `wakeup-gpios`
- 模块上电时序

也就是说：

- UART 控制器让“这路串口能工作”
- GPIO/电源/复位控制让“挂在这路串口上的模块真正活起来”

### 6.4 UART 挂载设备常见编程模式

如果某个模块只是简单串口协议设备，通常有两种做法：

1. 用户态直接访问 `/dev/tty*`
   适合：
   - 调试工具
   - 简单模块
   - 业务协议变化频繁

2. 内核里做一个 platform 驱动或 serdev 驱动
   适合：
   - 设备要和内核子系统绑定
   - 需要内核态管理电源/中断/状态
   - 需要统一纳入驱动模型

### 6.5 这块板子学 UART 驱动最好的路线

对当前 `imx6ull` 板子，建议按这个梯度学：

1. 先把用户态 UART 用熟
   - `stty`
   - `hexdump`
   - `cat`
   - 自己写 `detect_gps`

2. 再读当前 UART 设备树
   - `pinctrl_uart6`
   - `&uart6`
   - `uart3` 的 RS485 属性

3. 再读 `imx` 串口控制器驱动
   - probe
   - alias 编号
   - 中断收发
   - `rs485_config`

4. 最后再写“串口挂载设备”的驱动或更完整的应用协议栈

## 7. 针对这块板子，现场排查 UART 的固定套路

### 7.1 先确认设备节点

```bash
ls -l /dev/ttymxc*
dmesg | grep -i ttymxc
```

### 7.2 再确认当前 DTS 确实启用了对应串口

重点检查：

- `status = "okay"`
- `pinctrl-0 = <...>`
- 复用脚是否冲突

### 7.3 再确认电气和接线

- `TX -> RX`
- `RX -> TX`
- `GND -> GND`
- 电压是不是 TTL 3.3V 兼容
- 模块是否需要额外 `enable/reset`

### 7.4 再确认波特率

不是所有模块都默认 `9600`。  
很多时候你以为是“模块坏了”，其实只是：

- 设备在 `38400`
- 你在按 `9600` 读

### 7.5 再看协议层

即使串口已经有数据：

- 如果你只认 `GGA`
- 而设备先发的是 `RMC`

你也会误以为“程序没工作”。

## 8. 你接下来该怎么学 UART

建议按这 4 个实验走：

1. `uart6` 回环实验
   板上把 `TX/RX` 短接，验证 `/dev/ttymxc5` 自己的收发

2. `stty + hexdump` 裸读实验
   不写程序，先看串口是否有原始字节流

3. `detect_gps` 解析实验
   先打印原始 NMEA，再做字段解析

4. `uart3 + rs485` 对比实验
   理解“都是 UART 协议，但物理层和设备树配置可以完全不同”

如果这 4 个实验你都做顺了，再去看内核里的 UART 控制器驱动，理解会扎实很多。
