# imx6ull_100ask_pro drivers

驱动按下面方式组织：

- `patches/`
  内核内驱动改动，最终以 patch 形式进入 kernel 树
- `out-of-tree/`
  独立内核模块源码
- `dkms/`
  宿主侧独立管理模块的预留目录

建议规则：

- 改 vendor kernel 里的驱动逻辑时，优先做 patch
- 能独立成模块的，不优先继续堆在 kernel patch 里
- 用户态适配层不要放这里，放 `apps/public/libs/libhal/` 或私有库
