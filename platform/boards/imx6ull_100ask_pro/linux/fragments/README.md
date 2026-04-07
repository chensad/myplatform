# linux fragments

这里预留给内核配置碎片。

当同一 SoC 下需要多个板共享大部分配置、只保留少量差异时，优先把差异拆成 fragment，而不是复制整份 defconfig。
