# env

这个目录定义 `imx6ull_100ask_pro` 的构建环境。

包含：

- `toolchain.env` 宿主环境变量约定
- `Dockerfile` 容器镜像定义
- `docker-compose.yml` 容器启动配置

宿主机直接构建：

```bash
cd /home/compile/workstation/project/codex/myplatform
./tools/bootstrap.sh imx6ull_100ask_pro
./tools/fetch.sh
./build/build.sh imx6ull_100ask_pro demo_console buildroot
```

容器构建：

```bash
cd /home/compile/workstation/project/codex/myplatform/platform/boards/imx6ull_100ask_pro/env
docker compose build
cd /home/compile/workstation/project/codex/myplatform
./platform/boards/imx6ull_100ask_pro/scripts/enter-env.sh --docker
```

进入容器后，继续执行统一入口即可。
