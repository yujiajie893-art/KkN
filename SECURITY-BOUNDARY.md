# Security boundary

## 允许的数据流

1. App 从签名资源包读取公开词根。
2. 用户在生成器中选择来源、规则和数量上限。
3. 引擎在后台逐行读取词根并逐批写入临时 TXT。
4. 用户主动通过 iOS 文档选择器把 TXT 保存到“文件”App。
5. 其他独立工具只能由用户主动选择该 TXT 后再导入。

## 明确禁止的代码耦合

- 生成器不能引用验证器、连接管理器或候选尝试状态机。
- 生成结果不能通过内存队列、通知、URL scheme、App Group、剪贴板或隐藏缓存自动交给验证器。
- 本 target 不得加入 NetworkExtension、Hotspot Configuration、Access Wi-Fi Information、定位或辅助功能自动化代码。
- 不得把分析输入或生成结果发送到网络。

## 资源约束

- `manifest.json` 固定声明 schema、ID、条目数、字节数、SHA-256、来源与许可证。
- App 启动后在后台校验每个文件；未通过校验的数据源不可选。
- `test_dataset` 仅用于项目方真机性能测试，默认关闭，不加入常见词根分析索引。
- 公共姓名数据只包含聚合首名 token，不含可关联个人的记录。

## 日志与隐私

- 密码输入只存在于当前内存状态；不写日志、不持久化。
- 生成文件只有用户主动保存后才离开 App 临时目录。
- 隐私清单声明不追踪、不采集数据；仅为 App 自身外观偏好使用 UserDefaults，并声明 Required Reason `CA92.1`。
