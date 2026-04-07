# scripts

这里放 `imx6ull_100ask_pro` 的板级脚本。

当前关键脚本：

- `build-buildroot.sh`
- `build-linux.sh`
- `build-uboot.sh`
- `build-apps.sh`
- `enter-env.sh`

这些脚本负责把顶层 `build/build.sh` 的请求翻译成具体板级构建动作。
