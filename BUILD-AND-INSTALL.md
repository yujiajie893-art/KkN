# Build and install

## 本机 Xcode 构建

要求：macOS、Xcode 16 或更新版本，部署目标 iOS 16.0。

1. 打开 `WiFiVault.xcodeproj`。
2. 选择共享 Scheme：`WiFiVaultPatternLab`。
3. 在 target 的 Signing & Capabilities 中填写自己的 Team，并把示例 Bundle ID `com.example.WiFiVaultPatternLab` 改成唯一 ID。
4. 连接 iPhone，选择真机并运行。

工程没有额外 entitlement；不要从旧的 WiFiVault target 复制 Hotspot、Wi-Fi Information 或定位权限。

## 生成可安装 IPA

正式签名包：在 Xcode 选择 Product → Archive，再从 Organizer 使用 Development、Ad Hoc 或 App Store Connect 方式导出。最终体积以 Organizer 导出的 IPA 为准。

未签名测试包：仓库内 `.github/workflows/build-unsigned-ipa.yml` 会在 macOS runner 上完成以下工作：

- 校验全部资源行数、大小与 SHA-256；
- 编译并运行核心测试与百万行性能基准；
- 构建 Release iPhoneOS app；
- 检查可执行文件没有链接 NetworkExtension 或包含旧验证模块符号；
- 打包 `PatternLab-3.0-unsigned.ipa`；
- 输出 IPA 精确字节数和 SHA-256。

未签名 IPA 不能直接替代 Apple 正式签名；安装方式取决于你的开发者证书或自签工具。

## 命令行构建

```bash
xcodebuild \
  -project WiFiVault.xcodeproj \
  -scheme WiFiVaultPatternLab \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build-patternlab \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

构建产物位于：

`build-patternlab/Build/Products/Release-iphoneos/WiFiVaultPatternLab.app`
