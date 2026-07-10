# 本次云编译增强改动

## 没有修改的内容

以下原有内容全部保持字节级不变：

- 所有 `.swift` 文件
- `WiFiVault.xcodeproj`
- Xcode Scheme
- entitlements 文件
- Assets 和 App Icon
- 原有 README
- `.gitignore`
- 所有现有业务逻辑和 UI

可通过 `ORIGINAL-FILES-SHA256.txt` 核对原始文件 SHA-256。

## 只新增了四个文件

### `.github/workflows/build-unsigned-ipa.yml`

新增顶级云编译流程，包括：

- 手动运行与 main 分支路径过滤触发
- Release / Debug 选择
- macOS 15 Runner
- 最小仓库权限
- 并发取消和超时保护
- 环境、Xcode 与 SDK 记录
- Xcode 项目与共享 Scheme 验证
- Swift Package 条件缓存
- 真实 iPhoneOS 无签名构建
- 完整构建日志与 `.xcresult`
- App 包结构和设备架构验证
- 标准 IPA 封装
- SHA-256 校验
- IPA 与诊断包分离上传

### `WINDOWS-CLOUD-BUILD-GUIDE.md`

新增 Windows 上传、云编译、下载和签名说明。

### `CLOUD-BUILD-CHANGES.md`

记录本次新增内容。

### `ORIGINAL-FILES-SHA256.txt`

保存所有原始文件的 SHA-256，证明原文件未被修改。

## 重要说明

生成的是 **未签名 IPA**。它由 Xcode 针对 iPhoneOS 编译，
但仍需要你自己的签名才能安装。

Wi-Fi 自动连接需要的 Hotspot Configuration entitlement 是否可用，
最终由 Apple 开发者账号、App ID、provisioning profile 和签名决定。
