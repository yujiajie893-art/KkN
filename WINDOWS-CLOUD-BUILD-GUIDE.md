# WiFiVault：Windows + GitHub Actions 云编译指南

本项目的原有 Swift、Xcode 工程、资源和配置文件没有被修改。
新增的 GitHub Actions 工作流会使用 GitHub 提供的 macOS 运行器和
Xcode，生成一个真实的 **未签名 iPhone IPA**。

## 一、上传到 GitHub

不要把压缩包原样上传。先在 Windows 中解压，然后把解压后项目文件夹
中的全部内容上传到仓库根目录。

仓库根目录必须能直接看到：

```text
.github
WiFiVault
WiFiVault.xcodeproj
README.md
WINDOWS-CLOUD-BUILD-GUIDE.md
```

最关键的是：

```text
.github/workflows/build-unsigned-ipa.yml
```

上传完毕后点击 **Commit changes**。

## 二、启动云编译

打开 GitHub 仓库，依次进入：

```text
Actions
→ Build Unsigned iOS IPA
→ Run workflow
```

建议选择：

```text
Configuration: Release
```

然后点击绿色的 **Run workflow**。

工作流也会在 `main` 分支中的项目文件发生变化时自动运行。
它带有路径过滤和并发控制，不相关文件变化不会浪费 macOS 构建时间，
同一分支重复触发时会自动取消旧任务。

## 三、下载 IPA

等待构建出现绿色对勾后，点开本次运行，在页面底部找到：

```text
Artifacts
```

下载：

```text
WiFiVault-Unsigned-IPA-运行编号
```

解压后会得到：

```text
WiFiVault-Release-unsigned-运行编号.ipa
WiFiVault-Release-unsigned-运行编号.ipa.sha256
build-metadata.txt
```

其中：

- `.ipa`：未签名安装包
- `.sha256`：安装包完整性校验值
- `build-metadata.txt`：版本、Bundle ID、架构和构建环境摘要

## 四、在 Windows 签名并安装到 iPhone

未签名 IPA 不能直接安装。

可在 Windows 使用你信任的签名工具，通过你自己的 Apple Account
完成签名和安装。不要把 Apple Account 密码、验证码、P12 证书或
provisioning profile 上传到 GitHub。

## 五、Hotspot Configuration 权限

项目中的 Wi-Fi 自动连接部分依赖 Apple 的
`Hotspot Configuration` entitlement。

云端生成的是未签名 IPA。最终该能力能否工作，取决于签名时使用的：

- App ID
- provisioning profile
- Apple 开发者账号权限
- 最终代码签名中的 entitlement

普通免费签名可能无法授予这一能力。即使应用可以安装和打开，
自动加入 Wi-Fi 的功能仍可能被系统拒绝。

## 六、构建失败时怎么处理

每一次运行都会额外生成：

```text
WiFiVault-Build-Diagnostics-运行编号
```

其中包含：

- macOS 与 Xcode 版本
- iPhoneOS SDK 版本
- 项目和 Scheme 检查结果
- Build Settings
- 完整 xcodebuild 日志
- Xcode Result Bundle

## 七、工作流优化

- 最小权限：`contents: read`
- 不需要 Apple ID、证书或 GitHub Secret
- 不在 pull request 中自动执行未知代码
- 35 分钟超时保护
- 并发控制，避免重复浪费 macOS 时间
- Swift Package 条件缓存
- 构建前验证共享 Scheme
- 真实 `iphoneos` SDK 和设备架构
- 构建后校验 Info.plist、可执行文件和 CPU 架构
- 标准 `Payload/*.app` IPA 结构
- ZIP 完整性测试
- SHA-256 校验
- IPA 与诊断日志分开保存
