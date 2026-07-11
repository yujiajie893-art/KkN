#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

node Tools/validate-public-pack.mjs

if rg -n \
  'NEHotspot|NetworkExtension|AutoConnectManager|ContinuousVerificationManager|AccessibilityAutoFillManager|PasswordTesterManager|URLSession|NWConnection' \
  WiFiVaultPatternLab WiFiVault.xcodeproj; then
  echo "Forbidden network or verification symbol found"
  exit 1
fi

test "$(find WiFiVaultPatternLab -name '*.swift' | wc -l | tr -d ' ')" -eq 19

while IFS= read -r source; do
  basename="$(basename "$source")"
  rg -q "path = $basename;" WiFiVault.xcodeproj/project.pbxproj || {
    echo "Project does not reference $source"
    exit 1
  }
done < <(find WiFiVaultPatternLab -name '*.swift' | sort)

rg -q 'MARKETING_VERSION = 3.0.0;' WiFiVault.xcodeproj/project.pbxproj
rg -q 'IPHONEOS_DEPLOYMENT_TARGET = 16.0;' WiFiVault.xcodeproj/project.pbxproj
rg -q 'PatternLabPublicPack.bundle in Resources' WiFiVault.xcodeproj/project.pbxproj
rg -q 'PrivacyInfo.xcprivacy in Resources' WiFiVault.xcodeproj/project.pbxproj

if [[ -f SOURCE-MANIFEST.sha256 ]]; then
  sha256sum --check --quiet SOURCE-MANIFEST.sha256
fi

if find . -name '.DS_Store' -o -name '__MACOSX' | grep -q .; then
  echo "Archive metadata found"
  exit 1
fi

echo "PatternLab 3.0 source validation: passed"
