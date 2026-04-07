# apps

这个目录放用户态应用代码，不放 BSP 或第三方源码。

约定：

- `public/` 放可复用的公共应用和公共库
- `private/` 放项目私有应用和私有库

新增应用时，建议至少包含：

- `src/`
- `include/`
- `CMakeLists.txt`
- `package/buildroot/`

典型流程：

1. 在对应目录新增应用源码
2. 增加 Buildroot 包装文件
3. 在产品层决定是否装入 rootfs
4. 通过 `./build/build.sh <board> <product> app:<name>` 验证
