# Performance verification

## 已自动化的测试

`PatternLabTests/PatternLabCoreTests.swift` 使用 Release 优化编译后，会从 101 个临时词根生成并写出 1,000,000 行，要求：

- 精确生成 1,000,000 行；
- 达到上限时正确标记截断；
- 预览只保留 200 条；
- 文件真实存在且字节数合理；
- 平均速度高于 10,000 条/秒。

这个测试由 macOS CI 在每次 IPA 构建前执行。

`Tools/reference-stream-benchmark.mjs` 可在没有 Swift/Xcode 的主机上测试同样的 64 KiB 读取、256 KiB 缓冲写入和百万行上限。它只证明数据与 I/O 方案，不代替 Swift 真机结果。

```bash
node Tools/reference-stream-benchmark.mjs
```

## 真机验收

建议在最低支持档设备和当前主力设备上各跑一次：

1. 选择“测试来源”。
2. 只开启“数字后缀”，范围 1–9999，关闭大小写和特殊字符，单次上限 1,000,000。
3. 记录界面显示的数量、耗时、平均速度和 TXT 字节数。
4. 用 Xcode Memory Graph 或 Instruments 的 Allocations 记录峰值物理内存。
5. 保存到“文件”App，再逐行检查文件行数。
6. 生成过程中点击停止，确认不完整临时文件被删除。

验收门槛：速度 >10,000 条/秒、峰值内存 <50 MB、无 UI 长时间冻结、导出文件为 1,000,000 行。

内存上限必须以真机 Instruments 为准；仅根据源码结构或桌面进程 RSS 宣称达标是不严谨的。
