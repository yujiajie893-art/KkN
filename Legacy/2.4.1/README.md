# PatternLab 2.4.1 legacy managers

The seven original manager source files are preserved byte-for-byte in `Services/` and are deliberately excluded from the PatternLab 3.0 app target. They may import NetworkExtension and other historical frameworks, but the 3.0 target neither compiles nor links them.

`LegacyCompatibilityTypes.swift` supplies the historical model/parser symbols required for a separate legacy integration target. No legacy file is included in the main application's PBX Sources phase.
