#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
mkdir -p "$BUILD_DIR"

swiftc -O \
  "$ROOT_DIR/WiFiVaultPatternLab/Models/PatternLabModels.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Models/PublicDatasetManifest.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Core/StableHash64.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Core/UTF8LineReader.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Core/PatternRuleExpander.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Core/StreamingGenerationEngine.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Core/CommonRootIndex.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Core/PasswordStructureAnalyzer.swift" \
  "$ROOT_DIR/WiFiVaultPatternLab/Core/RiskScoringEngine.swift" \
  "$ROOT_DIR/PatternLabTests/PatternLabCoreTests.swift" \
  -o "$BUILD_DIR/patternlab-3-core-tests"

"$BUILD_DIR/patternlab-3-core-tests"
