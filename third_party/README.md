# third_party

这里放第三方源码入口，不放板级业务逻辑。

当前子模块：

- `buildroot/buildroot-2020.02`
- `linux/imx-linux4.9.88`
- `uboot/imx-uboot2017.03`

原则：

- 第三方源码保持尽量原始
- 板级 patch、overlay、脚本不要直接堆进这里
- 版本锁定通过 `platform/manifests/sources.lock` 和 git submodule 完成

拉取方式：

```bash
git submodule update --init --recursive
```
