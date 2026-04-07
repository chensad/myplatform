# build

这个目录只放构建入口和本地构建工作区，不放长期维护源码。

内容划分：

- `build.sh` 统一编译入口
- `out/` 板级输出目录
- `downloads/` Buildroot 下载缓存
- `dl/` 兼容旧脚本的下载目录
- `ccache/` 编译缓存
- `logs/` 本地构建日志

统一入口：

```bash
./build/build.sh imx6ull_100ask_pro demo_console buildroot
```

说明：

- `build/` 下大部分内容都是生成物，已在 `.gitignore` 中排除
- 需要保留到仓库的只有入口脚本和说明文档
