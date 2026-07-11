#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_FILE="WiFiVault.xcodeproj/project.pbxproj"
ACTIVE_SOURCE_DIR="WiFiVaultPatternLab"
SOURCE_MANIFEST="SOURCE-MANIFEST.sha256"

fail() {
  echo "❌ Validation failed: $*" >&2
  exit 1
}

echo "========================================"
echo " PatternLab 3.0 source validation"
echo "========================================"

# ------------------------------------------------------------
# 1. 检查必要目录和工程文件
# ------------------------------------------------------------

[[ -d "$ACTIVE_SOURCE_DIR" ]] \
  || fail "Active source directory is missing: $ACTIVE_SOURCE_DIR"

[[ -f "$PROJECT_FILE" ]] \
  || fail "Xcode project file is missing: $PROJECT_FILE"

[[ -f "WiFiVaultPatternLab/PrivacyInfo.xcprivacy" ]] \
  || fail "PrivacyInfo.xcprivacy is missing"

[[ -d "WiFiVaultPatternLab/Resources/PatternLabPublicPack.bundle" ]] \
  || fail "PatternLabPublicPack.bundle is missing"

echo "✅ Required project paths exist"

# ------------------------------------------------------------
# 2. 验证公开资源包
# ------------------------------------------------------------

node Tools/validate-public-pack.mjs

# ------------------------------------------------------------
# 3. 主 App 安全边界检查
#
# 只扫描真正进入 3.0 App 的 Swift 源码。
# Legacy/2.4.1 可以完整保留，但不能污染主 App。
#
# 使用 grep -E：
#   -E 让 | 代表正则“或”
#   -n 显示行号
#
# 不再依赖 GitHub Runner 未必安装的 ripgrep。
# ------------------------------------------------------------

FORBIDDEN_PATTERN='NEHotspot|NetworkExtension|AutoConnectManager|ContinuousVerificationManager|AccessibilityAutoFillManager|PasswordTesterManager|URLSession|NWConnection'

if find "$ACTIVE_SOURCE_DIR" \
    -type f \
    -name '*.swift' \
    -print0 \
    | xargs -0 grep -nE "$FORBIDDEN_PATTERN"
then
  fail "Forbidden network or legacy verification symbol found in active App sources"
fi

echo "✅ Active App sources contain no forbidden network or legacy symbols"

# ------------------------------------------------------------
# 4. 生成稳定的 Swift 源文件清单
#
# 不再硬编码“必须等于 19 个文件”。
# 以后增加合法 Swift 文件时，只要正确加入 Target 就能通过。
# ------------------------------------------------------------

SOURCE_LIST="$(mktemp)"
trap 'rm -f "$SOURCE_LIST"' EXIT

find "$ACTIVE_SOURCE_DIR" \
  -type f \
  -name '*.swift' \
  -print \
  | LC_ALL=C sort \
  > "$SOURCE_LIST"

SOURCE_COUNT="$(wc -l < "$SOURCE_LIST" | tr -d '[:space:]')"

[[ "$SOURCE_COUNT" -gt 0 ]] \
  || fail "No Swift source files were found under $ACTIVE_SOURCE_DIR"

echo "Found $SOURCE_COUNT active Swift source files"

# ------------------------------------------------------------
# 5. 提取 Xcode 的 Sources Build Phase
#
# 验证不能只看 PBXFileReference。
# 一个文件必须同时：
#
#   A. 存在 PBXFileReference
#   B. 存在 PBXBuildFile
#   C. 出现在 PBXSourcesBuildPhase
#
# 否则文件可能只显示在 Xcode 左侧，却没有参与编译。
# ------------------------------------------------------------

SOURCES_PHASE_FILE="$(mktemp)"
trap 'rm -f "$SOURCE_LIST" "$SOURCES_PHASE_FILE"' EXIT

awk '
  /\/\* Begin PBXSourcesBuildPhase section \*\// {
    inside = 1
  }

  inside {
    print
  }

  /\/\* End PBXSourcesBuildPhase section \*\// {
    inside = 0
  }
' "$PROJECT_FILE" > "$SOURCES_PHASE_FILE"

[[ -s "$SOURCES_PHASE_FILE" ]] \
  || fail "PBXSourcesBuildPhase section was not found in $PROJECT_FILE"

# ------------------------------------------------------------
# 6. 逐个验证 Swift 文件
# ------------------------------------------------------------

while IFS= read -r source; do
  [[ -n "$source" ]] || continue

  basename="$(basename "$source")"

  # A. 文件引用存在
  if ! grep -Fq \
      "path = $basename;" \
      "$PROJECT_FILE"
  then
    fail "Missing PBXFileReference for $source"
  fi

  # B. Build File 引用存在
  if ! grep -Fq \
      "$basename in Sources */ = {isa = PBXBuildFile;" \
      "$PROJECT_FILE"
  then
    fail "Missing PBXBuildFile entry for $source"
  fi

  # C. 真正进入 Sources Build Phase
  if ! grep -Fq \
      "$basename in Sources" \
      "$SOURCES_PHASE_FILE"
  then
    fail "$source is referenced by Xcode but is not included in Sources Build Phase"
  fi

  echo "✅ Target source: $source"
done < "$SOURCE_LIST"

echo "✅ All $SOURCE_COUNT Swift files are referenced and compiled by the target"

# ------------------------------------------------------------
# 7. 工程版本和资源配置
# ------------------------------------------------------------

grep -Fq \
  'MARKETING_VERSION = 3.0.0;' \
  "$PROJECT_FILE" \
  || fail "MARKETING_VERSION is not 3.0.0"

grep -Fq \
  'IPHONEOS_DEPLOYMENT_TARGET = 16.0;' \
  "$PROJECT_FILE" \
  || fail "iOS Deployment Target is not 16.0"

grep -Fq \
  'PatternLabPublicPack.bundle in Resources' \
  "$PROJECT_FILE" \
  || fail "PatternLabPublicPack.bundle is not included in Resources"

grep -Fq \
  'PrivacyInfo.xcprivacy in Resources' \
  "$PROJECT_FILE" \
  || fail "PrivacyInfo.xcprivacy is not included in Resources"

echo "✅ Version, deployment target and resources are configured"

# ------------------------------------------------------------
# 8. SHA-256 源码完整性
#
# Linux 通常提供 sha256sum。
# macOS 默认提供 shasum。
# 自动选择，不再依赖单一平台命令。
# ------------------------------------------------------------

if [[ -f "$SOURCE_MANIFEST" ]]; then
  echo "Checking $SOURCE_MANIFEST..."

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum \
      --check \
      --quiet \
      "$SOURCE_MANIFEST" \
      || fail "$SOURCE_MANIFEST is stale or a source file was modified"

  elif command -v shasum >/dev/null 2>&1; then
    shasum \
      -a 256 \
      -c "$SOURCE_MANIFEST" \
      >/dev/null \
      || fail "$SOURCE_MANIFEST is stale or a source file was modified"

  else
    fail "Neither sha256sum nor shasum is available"
  fi

  echo "✅ Source SHA-256 manifest passed"
fi

# ------------------------------------------------------------
# 9. 压缩包垃圾文件检查
# ------------------------------------------------------------

ARCHIVE_METADATA="$(
  find . \
    -path './.git' -prune \
    -o \( \
      -name '.DS_Store' \
      -o -name '__MACOSX' \
    \) \
    -print \
    -quit
)"

[[ -z "$ARCHIVE_METADATA" ]] \
  || fail "Archive metadata found: $ARCHIVE_METADATA"

echo "✅ No macOS archive metadata found"

echo
echo "========================================"
echo " PatternLab 3.0 source validation passed"
echo "========================================"
