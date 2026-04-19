# env

这个目录定义 `imx6ull_100ask_pro` 的 Docker 构建环境。

包含：

- `Dockerfile` 容器镜像定义
- `docker-compose.yml` 容器启动配置
- `toolchain.env` 额外环境变量约定
- `host-manual-packages.txt` 当前宿主机的手工安装包记录

当前目标不是做宿主机的字节级快照，而是固化一份可重建、可 `docker save/load` 的编译环境。

## 当前基线

- Host OS: `Ubuntu 24.04.4 LTS`
- 已验证可编译：
  - `make BOARD=imx6ull_100ask_pro app`
  - `make BOARD=imx6ull_100ask_pro buildroot`

## 构建镜像

在仓库根目录执行：

```bash
docker build \
  --build-arg UID="$(id -u)" \
  --build-arg GID="$(id -g)" \
  -t myplatform/imx6ull_100ask_pro:latest \
  -f platform/boards/imx6ull_100ask_pro/env/Dockerfile \
  .
```

或者在本目录下直接：

```bash
docker compose build
```

## WSL / Proxy Notes

如果宿主机在 WSL 里，并且终端已经配置了：

```bash
env | grep -i proxy
```

例如：

```bash
HTTP_PROXY=http://127.0.0.1:7892
HTTPS_PROXY=http://127.0.0.1:7892
```

但 `curl https://registry-1.docker.io/v2/` 正常、`docker pull ubuntu:24.04`
超时或拒绝连接，这通常不是镜像名问题，而是 Docker daemon 没继承 shell
里的代理。

可以给 Docker service 单独配置代理：

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7892"
Environment="HTTPS_PROXY=http://127.0.0.1:7892"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

确认是否生效：

```bash
systemctl show --property=Environment docker
```

预期类似：

```text
Environment=HTTP_PROXY=http://127.0.0.1:7892 HTTPS_PROXY=http://127.0.0.1:7892 NO_PROXY=localhost,127.0.0.1,::1
```

然后再验证：

```bash
sudo docker pull ubuntu:24.04
```

说明：

- `curl` 走的是当前 shell 网络
- `docker pull` / `docker build` 拉取 `FROM ubuntu:24.04` 走的是 Docker daemon
- 所以 shell 代理正常，不代表 Docker daemon 代理已经正常

## Docker 权限

如果 `docker pull` 报：

```text
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

说明当前用户还不能直接访问 Docker socket。可执行：

```bash
sudo usermod -aG docker $USER
newgrp docker
```

重新开一个终端后验证：

```bash
id
docker ps
```

预期 `id` 输出里包含 `docker` 组。

## 进入容器

```bash
cd /path/to/myplatform
./platform/boards/imx6ull_100ask_pro/scripts/enter-env.sh --docker
```

进入容器后继续走统一入口：

```bash
make BOARD=imx6ull_100ask_pro buildroot
```

如果不走 `enter-env.sh`，也可以直接挂载工程目录进入：

```bash
cd /path/to/myplatform

docker run --rm -it \
  -v "$PWD":/workspace/myplatform \
  -w /workspace/myplatform \
  myplatform/imx6ull_100ask_pro:latest
```

如果希望保留常用缓存和输出目录，建议先准备：

```bash
mkdir -p build/downloads build/ccache build/out build/logs
```

再执行：

```bash
docker run --rm -it \
  -v "$PWD":/workspace/myplatform \
  -v "$PWD/build/downloads":/workspace/myplatform/build/downloads \
  -v "$PWD/build/ccache":/workspace/myplatform/build/ccache \
  -v "$PWD/build/out":/workspace/myplatform/build/out \
  -v "$PWD/build/logs":/workspace/myplatform/build/logs \
  -w /workspace/myplatform \
  myplatform/imx6ull_100ask_pro:latest
```

进入容器后继续走统一入口：

```bash
make BOARD=imx6ull_100ask_pro vars
make BOARD=imx6ull_100ask_pro buildroot
```

## Build Context Note

当前仓库根目录已经提供 `.dockerignore`，默认忽略全部，只放行这次构建镜像
所需的 `platform/boards/imx6ull_100ask_pro/env/Dockerfile`。

这样做的原因是当前 `Dockerfile` 不需要 `COPY` 仓库源码，源码会在
`docker run -v ...` 时再挂进去。这样可以避免把整个仓库作为 build context
发送给 Docker daemon，尤其是在 `third_party/`、`build/` 很大的情况下。

## 导出为 tar

构建好镜像后导出：

```bash
docker save -o imx6ull_100ask_pro-env_ubuntu24.04.tar myplatform/imx6ull_100ask_pro:latest
```

恢复：

```bash
docker load -i imx6ull_100ask_pro-env_ubuntu24.04.tar
```

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
