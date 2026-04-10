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

如果是一台全新的 Ubuntu，想直接通过 Docker 环境开始编译，建议按下面顺序执行。

1. 先确认宿主机已经安装 Docker 和 Docker Compose：

```bash
docker --version
docker compose version
```

2. 拉取 `myplatform` 仓库并同步子模块：

```bash
git clone <your-myplatform-repo>
cd myplatform
git submodule update --init --recursive
```

3. 构建这块板的 Docker 镜像：

```bash
cd platform/boards/imx6ull_100ask_pro/env
docker compose build
```

这一步会读取当前目录下的 `Dockerfile` 和 `docker-compose.yml`，生成镜像 `myplatform/imx6ull_100ask_pro:latest`。

4. 回到仓库根目录并进入容器环境：

```bash
cd /path/to/myplatform
./platform/boards/imx6ull_100ask_pro/scripts/enter-env.sh --docker
```

这一步会启动容器，并把当前仓库挂载到容器内的 `/workspace/myplatform`。

5. 在容器里执行统一构建入口：

```bash
./tools/bootstrap.sh imx6ull_100ask_pro
./build/build.sh imx6ull_100ask_pro demo_console buildroot
```

常见单项构建命令：

```bash
./build/build.sh imx6ull_100ask_pro demo_console app:app_demo
./build/build.sh imx6ull_100ask_pro demo_console linux
./build/build.sh imx6ull_100ask_pro demo_console uboot
```

注意：

- 当前容器入口会把仓库目录直接挂载进去，所以容器内外看到的是同一份源码和 `build/` 输出。
- 当前实现没有做宿主机 UID/GID 映射，容器里生成的文件可能显示为 `root` 属主。

## Host Fakeroot Note

当前这块板的 Buildroot 仍然是 2020.02 基线。

在较新的 Ubuntu / WSL 宿主机上，Buildroot 自带的 `host-fakeroot 1.20.2`
可能无法正确伪造 rootfs owner，典型现象是：

- 最终 `rootfs.ext2` / `rootfs.tar` 里的文件 owner 变成宿主用户 UID/GID
- `/bin/login` 不是 `0:0` 的 setuid root 程序
- 启动后 root 登录报：
  `login: can't set groups: Operation not permitted`

当前仓库在板级 `buildroot/board/local.mk` 里把 `host-fakeroot`
切到了宿主系统安装的 `fakeroot 1.33 sysv`。

如果后续换机器后又遇到同类问题，先检查：

```bash
ls -l build/out/imx6ull_100ask_pro/demo_console/buildroot/host/bin/fakeroot
build/out/imx6ull_100ask_pro/demo_console/buildroot/host/bin/fakeroot -v
debugfs -R 'stat /bin/login' build/out/imx6ull_100ask_pro/demo_console/buildroot/images/rootfs.ext2
```

预期至少应满足：

- `host/bin/fakeroot` 指向系统 `fakeroot-sysv`
- 版本不低于 `1.33`
- 镜像里的 `/bin/login` owner 为 `0:0`
