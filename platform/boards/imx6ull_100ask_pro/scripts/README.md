# scripts

这里放 `imx6ull_100ask_pro` 的板级脚本。

当前关键脚本：

- `build-buildroot.sh`
- `build-linux.sh`
- `build-uboot.sh`
- `build-apps.sh`
- `enter-env.sh`

当前这些脚本主要是兼容层。

真实构建调度已经切到仓库根目录 `Makefile`：

```bash
make BOARD=imx6ull_100ask_pro buildroot
make BOARD=imx6ull_100ask_pro linux
make BOARD=imx6ull_100ask_pro uboot
make BOARD=imx6ull_100ask_pro app APP=app_demo
```

这些脚本现在只负责把旧入口转发到 `make`，避免已有使用方式立即失效。
