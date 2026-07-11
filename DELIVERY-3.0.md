# PatternLab 3.0 delivery report

## 合并结果

- 以 2.5 的独立 PatternLab target、SwiftUI 生成/分析界面和壁纸资产为视觉基础。
- 从 2.4.1 仅吸收纯离线能力：长度/字符集/熵估算、风险分层、可取消后台任务与结构化改进建议。
- 删除旧 WiFiVault target 及其自动连接、连续验证、候选自动填充、SSID 相关服务和 entitlement，最终工程只有一个 App target。
- 生成器与外部验证工具只通过用户可见 TXT 文件交换，不存在代码接口。

## 新增实现

- Resource Pack v1：独立 bundle、manifest、数据归因、许可证、行数/字节/SHA-256 校验。
- 六个数据源开关，其中 `test_dataset` 按要求注册为“测试来源”。
- 最高 1,000,000 条的流式组合与 256 KiB 缓冲写盘。
- 全局只记录词根 64-bit 指纹以去除跨数据源重复，完整候选不入内存集合。
- 200 条预览、实时进度、速率、已写字节、取消与不完整文件清理。
- 使用 `UIDocumentPickerViewController(forExporting:asCopy:)` 保存到“文件”App，避免把百万行拼成一个 Swift `String`。
- 本地公共词根指纹索引；最长匹配策略降低短词误报。
- 年份、闰年日期、键盘、重复字符、连续数字检测和 0–100 评分。
- 数据来源页显示条目数、体积、许可证、完整性和 SHA 摘要。
- iOS 16 部署目标、版本 3.0.0、build 300、隐私清单 Required Reason 补全。

## 已提供的验证

- `Tools/validate-public-pack.mjs`：逐文件重新计算条目、字节与 SHA-256。
- `Tools/validate-source.sh`：检查单目标工程、版本、资源引用和禁止符号。
- `PatternLabTests/PatternLabCoreTests.swift`：8 组核心测试，含实际 1,000,000 行流式基准。
- macOS CI：编译、百万行基准、Release 构建、可执行文件隔离检查、IPA 打包与精确体积记录。

## 体积说明

- 数据文本精确体积：5,148,735 bytes。
- 完整资源 bundle 与源码压缩包体积可在交付时本地精确计算。
- IPA 必须由 Xcode 编译出 ARM64 可执行文件后才能得到真实体积；Linux 工作环境不能生成或签名 iOS Mach-O。不要把源码 ZIP 或手工 Payload ZIP 冒充 IPA。
