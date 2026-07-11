# Validation report — 2026-07-11

## Passed in the current workspace

- Public pack schema and ID validation: passed.
- Dataset file existence: 6/6 passed.
- Declared versus actual logical line counts: 6/6 passed.
- Declared versus actual byte counts: 6/6 passed.
- SHA-256 integrity: 6/6 passed.
- Required counts: 200,000 English; 50,000 pinyin; 20,000 cities; 20,000 names; 500 keyboard; 187,896 test rows.
- Xcode project references all 17 Swift source files and all three resource entries.
- Marketing version 3.0.0, build 300 and iOS 16.0 deployment target detected.
- No `NEHotspot`, `NetworkExtension`, old connection manager, continuous verification manager, accessibility candidate filler, password tester manager, `URLSession`, or `NWConnection` symbol exists in the App source or project.
- Privacy manifest and resource-bundle Info.plist parse successfully.
- Shared Xcode scheme XML parses successfully.

Commands:

```bash
bash Tools/validate-source.sh
node Tools/validate-public-pack.mjs
```

## Host reference streaming result

The non-Swift reference implementation read the packaged English source in 64 KiB chunks and wrote one million generated rows with a 256 KiB buffer:

- Generated: 1,000,000 rows
- Output: 12,208,860 bytes
- Time: 0.0547 seconds
- Host throughput: 18,289,504 rows/second
- Incremental process RSS during the run: 25,116,672 bytes

This confirms that the packaged data and streaming I/O design are not the bottleneck. It is not an iPhone benchmark and must not be reported as iOS performance.

## Prepared but not executable in this workspace

- `PatternLabTests/PatternLabCoreTests.swift` contains 8 optimized core tests, including a real 1,000,000-row Swift streaming test with a >10,000 rows/second assertion.
- `.github/workflows/build-unsigned-ipa.yml` runs those tests on macOS, builds the Release iPhoneOS target, inspects the Mach-O for forbidden frameworks/symbols, packages an unsigned IPA, and records exact IPA bytes and SHA-256.

The current host is Linux and contains neither `swiftc` nor `xcodebuild`. Therefore Swift compilation, iOS signing, Instruments peak-memory measurement, and a truthful IPA size cannot be completed locally. An IPA was intentionally not fabricated from source files.
