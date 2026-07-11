# PatternLab 3.0

PatternLab 3.0 是一个 iOS 16+ 的纯离线密码结构教学与健康度测试工具。它把 2.5 的模式生成器与 2.4.1 中可安全复用的离线评分思路合并到一个干净的单目标工程中，同时移除网络连接、SSID 读取、自动填充与连续口令尝试链路。

## 3.0 功能

- `PatternLabPublicPack.bundle` 内置公开资源并通过 `manifest.json` 注册、计数与 SHA-256 校验。
- 按英文词根、拼音词根、全球城市、常见英文名或项目测试集选择生成来源。
- 生成规则：年份、1–9999 数字后缀、有效月日、键盘相邻模式、大小写与特殊字符变体。
- 单次上限可选 10,000、100,000、500,000 或 1,000,000 条。
- 流式读取词根并以 256 KiB 缓冲直接写入临时 TXT；内存只保留前 200 条预览，不保留百万条结果数组。
- 通过系统文档选择器把完整 TXT 保存到用户可访问的“文件”App。
- 本地分析常见词根、年份、有效日期、键盘序列、重复字符与连续数字，并给出 0–100 结构评分和改进建议。
- 输入不落盘、不保存历史、不上传。
- 内置壁纸与可读性调节沿用 2.5 的视觉资源。

## 内置数据

| ID | 内容 | 条目 | 默认 | 分析索引 |
| --- | --- | ---: | --- | --- |
| `english_words` | 英文词根 | 200,000 | 开 | 是 |
| `pinyin_roots` | 拼音词根 | 50,000 | 关 | 是 |
| `global_cities` | 全球城市名 | 20,000 | 关 | 是 |
| `common_names` | SSA 常见英文名 | 20,000 | 关 | 是 |
| `keyboard_patterns` | 键盘模式 | 500 | 辅助 | 是 |
| `test_dataset` | 项目方性能测试来源 | 187,896 | 关 | 否 |

数据文件合计 478,396 个逻辑行、5,148,735 bytes。各文件来源、转换方式、许可证和再分发注意事项见 `WiFiVaultPatternLab/Resources/PatternLabPublicPack.bundle/ATTRIBUTIONS.md`。

“GB 级资源包”和上述条目规模并不相符：这些紧凑纯文本原始数据只有约 5.15 MB，压入 IPA 后通常还会更小。工程没有为了凑 50–80 MB 人为填充无意义数据。

## 安全边界

生成器和任何验证工具只允许通过用户主动导出/导入的 TXT 文件交换数据。本工程：

- 不含 `NetworkExtension`；
- 不调用 `NEHotspotConfigurationManager`；
- 不读取 SSID、路由器信息、位置或通讯录；
- 不含自动连接、连续验证、辅助功能填充或候选传递接口；
- 不含泄露密码库或个人身份记录；
- 不声明 Wi-Fi、网络、定位或 Keychain entitlement。

详见 `SECURITY-BOUNDARY.md`。

## 验证

```bash
chmod +x Tools/validate-source.sh Tools/run-core-tests.sh
./Tools/validate-source.sh
./Tools/run-core-tests.sh
```

第二个命令需要 Swift 工具链，并会实际生成 1,000,000 行临时 TXT、校验结果数与吞吐量。

构建和签名方法见 `BUILD-AND-INSTALL.md`。
