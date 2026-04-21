# env

这个目录定义 `myir_imx8m_plus` 的 Docker 编译环境。

目标很直接：

- 参考 `Imx8mp` 原厂文档固化 `Ubuntu 18.04 64bit` Yocto 主机环境
- 避免继续依赖宿主机 `Ubuntu 24.04 + Python 3.12`
- 下次直接 `docker load` 后进容器编译

## 文档依据

主机环境要求来自原厂：

- [MYD-JX8MPQ Software Development Guide.pdf](/home/compile/workstation/project/codex/Imx8mp/Linux%205.10.9%20Distribution%20V2.0.0/01-Doc(EN)/01-Doc(EN)/MYD-JX8MPQ%20Software%20Development%20Guide.pdf)

文档里明确写了两点：

- 推荐主机系统：`Ubuntu 18.04 64bit desktop`
- Yocto 构建依赖包：`gawk wget git-core diffstat unzip texinfo gcc-multilib build-essential chrpath socat cpio python python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev pylint3 xterm rsync curl libssl-dev`

当前 `Dockerfile` 以这组依赖为主，再补了 `ca-certificates`、`file`、`locales`、`vim`、`zstd`、`liblz4-tool` 这些容器里常用且实际构建会用到的基础包。

## 当前基线

- Base image: `ubuntu:18.04`
- Container locale: `en_US.UTF-8`
- Image tag: `myplatform/myir_imx8m_plus:ubuntu18.04`

说明：

- 截至 `2026-04-21`，`archive.ubuntu.com` 仍然保留 `bionic` 仓库
- 当前 `Dockerfile` 保持 `bionic` 标准仓库，但把 `security.ubuntu.com` 统一到 `archive.ubuntu.com`，并开启 `apt` 重试，避免容器构建时单个安全仓库节点抖动
- 容器运行时会把工程挂载到和宿主机一致的绝对路径，避免 Yocto 因 `TMPDIR` 路径变化拒绝继续

## 构建镜像

在仓库根目录执行：

```bash
cd /path/to/myplatform

docker build \
  --build-arg UID="$(id -u)" \
  --build-arg GID="$(id -g)" \
  -t myplatform/myir_imx8m_plus:ubuntu18.04 \
  -f platform/boards/myir_imx8m_plus/env/Dockerfile \
  .
```

或者在本目录下：

```bash
cd platform/boards/myir_imx8m_plus/env
UID="$(id -u)" GID="$(id -g)" docker compose build
```

或者直接用封装脚本：

```bash
cd /path/to/myplatform
./platform/boards/myir_imx8m_plus/env/build-image.sh
```

## 进入容器

推荐直接：

```bash
cd /path/to/myplatform
./platform/boards/myir_imx8m_plus/scripts/enter-env.sh --docker
```

这个命令现在会：

- 启动或复用常驻容器 `myir_imx8m_plus_yocto_env`
- 把工程目录按宿主机原路径挂进去
- 直接 `docker exec` 进入这个常驻容器

进入容器后继续统一入口：

```bash
make BOARD=myir_imx8m_plus yocto
```

如果要直接在常驻容器里执行 `bitbake`，推荐用封装脚本：

```bash
./platform/boards/myir_imx8m_plus/env/run-yocto.sh
```

如果只想启动或停止常驻容器：

```bash
./platform/boards/myir_imx8m_plus/env/start-container.sh
./platform/boards/myir_imx8m_plus/env/stop-container.sh
```

如果不走脚本，也可以手工执行：

```bash
cd /path/to/myplatform

docker run -d \
  --name myir_imx8m_plus_yocto_env \
  -v "$PWD":"$PWD" \
  -w "$PWD" \
  myplatform/myir_imx8m_plus:ubuntu18.04 \
  tail -f /dev/null

docker exec -it myir_imx8m_plus_yocto_env bash
```

如果希望保留缓存和输出目录，建议这样挂载：

```bash
mkdir -p build/downloads build/sstate-cache build/out build/logs

docker run --rm -it \
  -v "$PWD":"$PWD" \
  -v "$PWD/build/downloads":"$PWD/build/downloads" \
  -v "$PWD/build/sstate-cache":"$PWD/build/sstate-cache" \
  -v "$PWD/build/out":"$PWD/build/out" \
  -v "$PWD/build/logs":"$PWD/build/logs" \
  -w "$PWD" \
  myplatform/myir_imx8m_plus:ubuntu18.04
```

进入容器后继续：

```bash
make BOARD=myir_imx8m_plus vars
make BOARD=myir_imx8m_plus yocto
```

## 保存与恢复

构建好镜像后导出：

```bash
docker save -o myir_imx8m_plus-yocto-env_ubuntu18.04.tar \
  myplatform/myir_imx8m_plus:ubuntu18.04
```

说明：

- 这个导出的 `.tar` 只作为本地环境包使用，不提交到 git 仓库
- 当前目录的 `.gitignore` 已忽略 `myir_imx8m_plus-yocto-env_ubuntu18.04.tar`

或者直接：

```bash
./platform/boards/myir_imx8m_plus/env/save-image.sh
```

下次恢复：

```bash
docker load -i myir_imx8m_plus-yocto-env_ubuntu18.04.tar
```

或者直接：

```bash
./platform/boards/myir_imx8m_plus/env/load-image.sh
```

恢复后直接进容器编译：

```bash
./platform/boards/myir_imx8m_plus/scripts/enter-env.sh --docker
make BOARD=myir_imx8m_plus yocto
```

或者直接：

```bash
./platform/boards/myir_imx8m_plus/env/run-yocto.sh
```

## Docker 权限

如果 `docker build` 或 `docker run` 报：

```text
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

说明当前用户还不能直接访问 Docker socket。先执行：

```bash
sudo usermod -aG docker $USER
newgrp docker
```

重新开终端后验证：

```bash
id
docker ps
```

## Why This Exists

当前这套 Yocto / BitBake 比较老，宿主机在 `Ubuntu 24.04 + Python 3.12` 上已经反复出现
`bitbake-worker` 多线程 `fork()` 兼容问题，表现为 worker 消失、前台会话假活着。

这个 Docker 环境的目的，就是把构建主机固定回原厂推荐的 `Ubuntu 18.04`，尽量避免继续踩宿主机兼容坑。
