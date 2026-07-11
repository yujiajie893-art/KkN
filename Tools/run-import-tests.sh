#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.swift" <<'SWIFT'
import Foundation
@main struct Tests { static func main() throws {
 let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
 defer { try? FileManager.default.removeItem(at: dir) }
 let long = String(repeating: "x", count: 257)
 let text = "alpha\n\n beta \nalpha\n\(long)\n中文\n" + (0..<20005).map { "item\($0)" }.joined(separator: "\n")
 let u8 = dir.appendingPathComponent("u8.txt"); try Data([0xEF,0xBB,0xBF] + Array(text.utf8)).write(to: u8)
 let r1 = try TextDatasetImporter.importFile(at: u8, destinationDirectory: dir.appendingPathComponent("o1"))
 precondition(r1.acceptedCount == 20000 && r1.duplicateCount == 1 && r1.ignoredBlankCount == 1 && r1.skippedLongLineCount == 1 && r1.wasTruncated)
 var d = Data([0xFF,0xFE]); d.append("甲\n乙\n甲\n".data(using: .utf16LittleEndian)!)
 let u16 = dir.appendingPathComponent("u16.txt"); try d.write(to: u16)
 let r2 = try TextDatasetImporter.importFile(at: u16, destinationDirectory: dir.appendingPathComponent("o2")); precondition(r2.acceptedCount == 2)
 print("TXT importer: UTF-8 BOM, UTF-16 LE, filters, dedupe, truncation passed")
}}
SWIFT
swiftc "$ROOT/WiFiVaultPatternLab/Import/TextDatasetImporter.swift" "$TMP/test.swift" -o "$TMP/test"
"$TMP/test"
printf '中文\n测试\n中文\n' | iconv -f UTF-8 -t GB2312 > "$TMP/gb.txt"
cat > "$TMP/gb.swift" <<SWIFT
import Foundation
@main struct GB { static func main() throws { let d=try Data(contentsOf: URL(fileURLWithPath:"$TMP/gb.txt")); let x=try TextDatasetImporter.decode(d); precondition(x.text.contains("中文")); print("TXT importer: GB2312 passed") } }
SWIFT
swiftc "$ROOT/WiFiVaultPatternLab/Import/TextDatasetImporter.swift" "$TMP/gb.swift" -o "$TMP/gb"
"$TMP/gb"
