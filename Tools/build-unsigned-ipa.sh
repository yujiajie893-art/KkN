#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${PRODUCT_BUNDLE_IDENTIFIER:?Set PRODUCT_BUNDLE_IDENTIFIER, e.g. com.company.PatternLab3}"
OUT="${1:-$ROOT/BuildArtifacts}"
DERIVED="$OUT/DerivedData"
APP="$DERIVED/Build/Products/Release-iphoneos/WiFiVaultPatternLab.app"
mkdir -p "$OUT"
xcodebuild -project WiFiVault.xcodeproj -scheme WiFiVaultPatternLab -configuration Release \
  -sdk iphoneos -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  PRODUCT_BUNDLE_IDENTIFIER="$PRODUCT_BUNDLE_IDENTIFIER" \
  clean build | tee "$OUT/xcodebuild-release.log"
rm -rf "$OUT/Payload" "$OUT/PatternLab-3.0-unsigned.ipa"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && /usr/bin/zip -qry PatternLab-3.0-unsigned.ipa Payload)
/usr/bin/codesign -dv --verbose=4 "$APP" >"$OUT/codesign-check.txt" 2>&1 || true
shasum -a 256 "$OUT/PatternLab-3.0-unsigned.ipa" | tee "$OUT/PatternLab-3.0-unsigned.ipa.sha256"
stat -f '%z bytes' "$OUT/PatternLab-3.0-unsigned.ipa" | tee "$OUT/PatternLab-3.0-unsigned.ipa.size.txt"
