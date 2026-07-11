#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const bundle = path.resolve(process.argv[2] ?? "WiFiVaultPatternLab/Resources/PatternLabPublicPack.bundle");
const manifest = JSON.parse(fs.readFileSync(path.join(bundle, "manifest.json"), "utf8"));
if (manifest.schemaVersion !== 1 || manifest.packId !== "PatternLabPublicPack") {
  throw new Error("Invalid manifest identity");
}

const expectedCounts = {
  english_words: 200000,
  pinyin_roots: 50000,
  global_cities: 20000,
  common_names: 20000,
  keyboard_patterns: 500,
  test_dataset: 187896,
};

for (const dataset of manifest.datasets) {
  const filePath = path.resolve(bundle, dataset.file);
  if (!filePath.startsWith(`${bundle}${path.sep}`)) throw new Error(`Unsafe path: ${dataset.file}`);
  const data = fs.readFileSync(filePath);
  let lines = 0;
  for (const byte of data) if (byte === 0x0a) lines += 1;
  if (data.length > 0 && data.at(-1) !== 0x0a) lines += 1;
  const digest = crypto.createHash("sha256").update(data).digest("hex");

  if (dataset.lineCount !== lines) throw new Error(`${dataset.id}: manifest line count mismatch`);
  if (dataset.byteCount !== data.length) throw new Error(`${dataset.id}: byte count mismatch`);
  if (dataset.sha256 !== digest) throw new Error(`${dataset.id}: digest mismatch`);
  if (expectedCounts[dataset.id] !== lines) throw new Error(`${dataset.id}: target count mismatch`);
  process.stdout.write(`${dataset.id}: ${lines} lines, SHA-256 OK\n`);
}

if (manifest.datasets.length !== Object.keys(expectedCounts).length) {
  throw new Error("Unexpected dataset count");
}
process.stdout.write("Public pack validation: passed\n");
