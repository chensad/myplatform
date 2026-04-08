# imx6ull_100ask_pro

这是 `imx6ull_100ask_pro` 板卡的 BSP 根目录。

当前状态：

- 已经映射旧 SDK 的 Buildroot、Linux、U-Boot 关键配置
- 已经能从 `myplatform` 入口完整编译出镜像
- 仍然保留旧 `100ask_imx6ull-sdk/` 作为对照和兼容来源

目录分工：

- `board.env` 兼容旧脚本使用的板级路径变量
- `board.mk` Makefile 侧的板级路径真源
- `model.mk` 机型功能、third_party 选择和 app 宏真源
- `scripts/` 板级兼容脚本
- `linux/` 内核 defconfig、patch、fragment
- `uboot/` U-Boot defconfig、patch、fragment
- `buildroot/` Buildroot defconfig、board 资源、external 层
- `drivers/` 板级驱动补丁和外置模块
- `env/` 宿主机和容器环境
- `image/` 预留给板级镜像模板和说明

当前关键入口：

```bash
make BOARD=imx6ull_100ask_pro buildroot
```

常用目标：

```bash
make BOARD=imx6ull_100ask_pro vars
make BOARD=imx6ull_100ask_pro app APP=app_demo
make BOARD=imx6ull_100ask_pro linux
make BOARD=imx6ull_100ask_pro uboot
make BOARD=imx6ull_100ask_pro buildroot
```

`model.mk` 当前控制：

- `MODEL_THIRD_PARTY_*`：决定实际使用的 Buildroot/Linux/U-Boot 源码目录
- `MODEL_FEATURE_*`：机型功能开关
- `MODEL_APP_CPPFLAGS`：注入 app 的 `CONFIG_*` 宏
- `MODEL_BUILDROOT_EXTRA_CONFIGS`：追加 Buildroot 配置片段

迁移来源：

- 内核配置来自 `100ask_imx6ull-sdk/Linux-4.9.88`
- U-Boot 配置来自 `100ask_imx6ull-sdk/Uboot-2017.03`
- Buildroot 配置和 board 资源来自 `100ask_imx6ull-sdk/Buildroot_2020.02.x`

这块板已经完成“从 `myplatform` 统一入口出镜像”的第一阶段迁移，当前统一入口以根目录 `Makefile` 为主，`scripts/` 仅保留兼容包装。
