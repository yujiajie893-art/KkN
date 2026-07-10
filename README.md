# WiFiVault

一个完全本地运行的 SwiftUI Wi‑Fi 密码管理示例应用。

## 功能

- 添加、编辑、删除 Wi‑Fi 记录
- 按网络名称或备注搜索
- 显示/隐藏密码
- 一键复制当前显示的密码
- 网络名称、备注和时间保存在 UserDefaults
- 密码保存在 iOS Keychain
- 不联网、不扫描网络、不读取系统 Wi‑Fi 密码

## 环境

- Xcode 15 或更高版本
- iOS 16.0 或更高版本
- SwiftUI

## 运行

1. 双击 `WiFiVault.xcodeproj`
2. 选择 `WiFiVault` Target
3. 在 Signing & Capabilities 中选择你的 Team
4. 如需安装到真机，将 Bundle Identifier 改成你自己的唯一标识
5. 选择模拟器或 iPhone，点击 Run

## 说明

iOS 普通第三方应用不能读取“设置”中已经保存的 Wi‑Fi 密码。本项目只管理用户手动录入的、本人拥有或获准保存的网络凭据。


## 安全版自动连接

此版本新增：

- `AutoConnectManager.swift`
- `AutoConnectSheet.swift`
- 自动连接入口、进度条和停止按钮
- 连接成功提示
- 老人找回密码的系统引导

安全边界：

- 用户必须明确选择一条已经保存的 Wi-Fi 记录
- 每次只提交这一组 SSID 与密码
- 不扫描附近网络
- 不运行弱密码字典
- 不批量尝试不同凭据

## Xcode 必做设置

1. 选择 WiFiVault Target。
2. 打开 Signing & Capabilities。
3. 点击 `+ Capability`。
4. 添加 `Hotspot Configuration`。
5. 选择有效的开发者 Team。
6. 使用真机测试；模拟器不能实际连接 Wi-Fi。

即使项目已包含 entitlement 文件，也必须保证签名所用的
Provisioning Profile 拥有对应能力。


## TXT 密码强度审计

新增文件：

- `Services/PasswordTesterManager.swift`
- `Views/PasswordTesterSheet.swift`

功能：

- 使用 SwiftUI `fileImporter` 导入 TXT
- 每行读取一个密码
- 自动去空行、去重
- 最多导入 20,000 条，避免过度占用内存
- 离线检测长度、字符类型、重复模式、常见弱密码、SSID 关联和估算熵
- 显示当前分析项、进度百分比和停止按钮
- 结果按风险排序
- 日志只写入本机 Application Support
- 日志不保存密码明文，仅保存 SHA-256 截断指纹
- 用户可以手动选中一个候选密码，并进行一次明确的连接验证

安全限制：

- 不扫描附近 Wi-Fi
- 不按 TXT 列表自动轮询连接
- 不批量猜测密码
- 不上传密码、结果或日志


## 无障碍辅助填充

新增：

- `Services/AccessibilityAutoFillManager.swift`
- VoiceOver 友好的候选位置播报
- 未开启 VoiceOver 时使用 `AVSpeechSynthesizer`
- 每 3 秒自动选择并朗读下一个候选密码
- 每次最多载入 50 个候选
- 可选择是否朗读密码内容
- 可调整语速、音调和音量
- 大尺寸固定“验证当前密码”按钮
- VoiceOver 自定义操作：重复朗读、选择下一个
- 连接成功后自动停止并播报
- 失败后自动移动到下一个候选，但不会自动提交连接

重要边界：

候选密码可以自动朗读和切换，但每一次调用
`NEHotspotConfigurationManager.apply` 都必须由用户明确激活
“验证当前密码”按钮。盲人用户无需浏览或手动挑选列表，可以让
VoiceOver 焦点停留在固定按钮上重复双击，或者使用 iOS 语音控制、
切换控制及兼容的外接开关。
