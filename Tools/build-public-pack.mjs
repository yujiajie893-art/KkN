#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const TARGET_COUNTS = Object.freeze({
  english_words: 200_000,
  pinyin_roots: 50_000,
  global_cities: 20_000,
  common_names: 20_000,
  keyboard_patterns: 500,
});

function parseArguments(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) {
      throw new Error(`Invalid argument near ${key ?? "<end>"}`);
    }
    values.set(key.slice(2), value);
  }

  const required = ["output", "english", "pinyin", "cities", "names", "test"];
  for (const key of required) {
    if (!values.has(key)) throw new Error(`Missing --${key}`);
  }
  return values;
}

function normalizeAsciiRoot(value, minimumLength = 3, maximumLength = 32) {
  const normalized = value
    .normalize("NFKD")
    .replace(/\p{Mark}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
  if (normalized.length < minimumLength || normalized.length > maximumLength) return null;
  return normalized;
}

function uniqueLimited(values, limit) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    if (!value || seen.has(value)) continue;
    seen.add(value);
    result.push(value);
    if (result.length === limit) break;
  }
  if (result.length !== limit) {
    throw new Error(`Expected ${limit.toLocaleString()} unique values, got ${result.length.toLocaleString()}`);
  }
  return result;
}

function buildEnglishWords(sourcePath) {
  const source = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
  const roots = source
    .map((word) => normalizeAsciiRoot(String(word), 3, 24))
    .filter(Boolean);
  const unique = [...new Set(roots)];
  const limit = TARGET_COUNTS.english_words;
  if (unique.length < limit) {
    throw new Error(`Expected at least ${limit.toLocaleString()} English words, got ${unique.length.toLocaleString()}`);
  }

  // Even sampling keeps deterministic alphabetical ordering while covering the
  // entire A–Z source instead of dropping the tail of the dictionary.
  return Array.from({ length: limit }, (_, index) => {
    const sourceIndex = Math.round(index * (unique.length - 1) / (limit - 1));
    return unique[sourceIndex];
  });
}

async function buildPinyinRoots(sourcePath) {
  const module = await import(`${pathToFileURL(sourcePath).href}?build=${Date.now()}`);
  const entries = module.default?.all ?? module.all;
  if (!Array.isArray(entries)) throw new Error("CC-CEDICT source does not contain an all array");

  const ranked = [];
  const seen = new Set();
  for (let index = 0; index < entries.length; index += 1) {
    const raw = String(entries[index]?.[2] ?? "").trim();
    if (!raw) continue;
    const syllables = raw.split(/\s+/).filter(Boolean);
    if (syllables.length < 2 || syllables.length > 5) continue;

    const value = raw
      .toLowerCase()
      .replaceAll("u:", "v")
      .replaceAll("ü", "v")
      .replace(/[1-5]/g, "")
      .replace(/[^a-zv]/g, "");
    if (!/^[a-zv]{4,32}$/.test(value) || seen.has(value)) continue;
    seen.add(value);
    ranked.push({ value, syllableCount: syllables.length, sourceIndex: index });
  }

  ranked.sort((left, right) =>
    left.syllableCount - right.syllableCount
      || left.value.length - right.value.length
      || left.sourceIndex - right.sourceIndex
  );
  return uniqueLimited(ranked.map((item) => item.value), TARGET_COUNTS.pinyin_roots);
}

function buildCities(sourcePath) {
  const lines = fs.readFileSync(sourcePath, "utf8").split(/\r?\n/);
  const candidates = [];
  for (const line of lines) {
    if (!line) continue;
    const fields = line.split("\t");
    if (fields.length < 15) continue;
    const root = normalizeAsciiRoot(fields[2] || fields[1], 3, 32);
    const population = Number.parseInt(fields[14], 10) || 0;
    if (root) candidates.push({ root, population });
  }
  candidates.sort((left, right) => right.population - left.population || left.root.localeCompare(right.root));
  return uniqueLimited(candidates.map((item) => item.root), TARGET_COUNTS.global_cities);
}

function buildNames(sourceDirectory) {
  const totals = new Map();
  const files = fs.readdirSync(sourceDirectory)
    .filter((name) => /^yob\d{4}\.txt$/.test(name))
    .sort();
  if (files.length === 0) throw new Error("No SSA yob*.txt files found");

  for (const fileName of files) {
    const lines = fs.readFileSync(path.join(sourceDirectory, fileName), "utf8").split(/\r?\n/);
    for (const line of lines) {
      if (!line) continue;
      const [rawName, , rawCount] = line.split(",");
      const root = normalizeAsciiRoot(rawName ?? "", 3, 24);
      const count = Number.parseInt(rawCount, 10);
      if (!root || !Number.isFinite(count)) continue;
      totals.set(root, (totals.get(root) ?? 0) + count);
    }
  }

  const ranked = [...totals.entries()]
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .map(([name]) => name);
  return uniqueLimited(ranked, TARGET_COUNTS.common_names);
}

function buildKeyboardPatterns() {
  const values = [];
  const seen = new Set();
  const append = (value) => {
    const normalized = value.toLowerCase();
    if (normalized.length < 4 || normalized.length > 12 || seen.has(normalized)) return;
    seen.add(normalized);
    values.push(normalized);
  };

  [
    "qwerty", "qwertyuiop", "asdf", "asdfgh", "asdfghjkl", "zxcv", "zxcvbn", "zxcvbnm",
    "1234", "123456", "1234567890", "0987654321", "1qaz", "2wsx", "3edc", "4rfv",
    "5tgb", "6yhn", "7ujm", "qazwsx", "wsxedc", "edcrfv", "rfvtgb", "tgbyhn",
    "yhnujm", "poiuy", "lkjhg", "mnbvc", "q1w2e3", "1q2w3e", "zaq12wsx",
  ].forEach(append);

  const rows = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"];
  for (const row of rows) {
    for (const direction of [row, [...row].reverse().join("")]) {
      for (let length = 4; length <= direction.length; length += 1) {
        for (let start = 0; start + length <= direction.length; start += 1) {
          append(direction.slice(start, start + length));
        }
      }
    }
  }

  const positionedRows = [
    { keys: "1234567890", offset: 0 },
    { keys: "qwertyuiop", offset: 0.25 },
    { keys: "asdfghjkl", offset: 0.55 },
    { keys: "zxcvbnm", offset: 1.05 },
  ];
  const points = [];
  positionedRows.forEach((row, y) => {
    [...row.keys].forEach((key, x) => points.push({ key, x: x + row.offset, y }));
  });
  const neighbors = new Map(points.map(({ key }) => [key, []]));
  for (const left of points) {
    for (const right of points) {
      if (left.key === right.key) continue;
      const distance = Math.hypot(left.x - right.x, left.y - right.y);
      if (distance <= 1.16) neighbors.get(left.key).push(right.key);
    }
    neighbors.get(left.key).sort();
  }

  function walk(current, targetLength) {
    if (values.length >= TARGET_COUNTS.keyboard_patterns) return;
    if (current.length === targetLength) {
      append(current);
      return;
    }
    const options = neighbors.get(current.at(-1)) ?? [];
    for (const next of options) {
      if (current.length >= 2 && current.at(-2) === next) continue;
      walk(current + next, targetLength);
      if (values.length >= TARGET_COUNTS.keyboard_patterns) return;
    }
  }

  for (let length = 4; length <= 7 && values.length < TARGET_COUNTS.keyboard_patterns; length += 1) {
    for (const { key } of points) {
      walk(key, length);
      if (values.length >= TARGET_COUNTS.keyboard_patterns) break;
    }
  }

  return uniqueLimited(values, TARGET_COUNTS.keyboard_patterns);
}

function writeLines(filePath, values) {
  fs.writeFileSync(filePath, `${values.join("\n")}\n`, "utf8");
}

function fileMetadata(filePath) {
  const data = fs.readFileSync(filePath);
  let lineCount = 0;
  for (const byte of data) if (byte === 0x0a) lineCount += 1;
  if (data.length > 0 && data.at(-1) !== 0x0a) lineCount += 1;
  return {
    lineCount,
    byteCount: data.length,
    sha256: crypto.createHash("sha256").update(data).digest("hex"),
  };
}

const argumentsMap = parseArguments(process.argv.slice(2));
const outputBundle = path.resolve(argumentsMap.get("output"));
const dataDirectory = path.join(outputBundle, "Data");
fs.mkdirSync(dataDirectory, { recursive: true });

const generated = {
  english_words: buildEnglishWords(path.resolve(argumentsMap.get("english"))),
  pinyin_roots: await buildPinyinRoots(path.resolve(argumentsMap.get("pinyin"))),
  global_cities: buildCities(path.resolve(argumentsMap.get("cities"))),
  common_names: buildNames(path.resolve(argumentsMap.get("names"))),
  keyboard_patterns: buildKeyboardPatterns(),
};

for (const [id, values] of Object.entries(generated)) {
  writeLines(path.join(dataDirectory, `${id}.txt`), values);
}
fs.copyFileSync(path.resolve(argumentsMap.get("test")), path.join(dataDirectory, "test_dataset.txt"));

const definitions = [
  {
    id: "english_words", displayName: "英文词根", category: "english", role: "root",
    file: "Data/english_words.txt", defaultEnabled: true, analyzerEnabled: true,
    sourceName: "an-array-of-english-words 2.0.0", sourceURL: "https://github.com/words/an-array-of-english-words",
    license: "MIT",
  },
  {
    id: "pinyin_roots", displayName: "中文拼音词根", category: "pinyin", role: "root",
    file: "Data/pinyin_roots.txt", defaultEnabled: false, analyzerEnabled: true,
    sourceName: "CC-CEDICT via cc-cedict 1.1.1 (tone-stripped derivative)", sourceURL: "https://www.mdbg.net/chinese/dictionary?page=cedict",
    license: "CC BY-SA 4.0",
  },
  {
    id: "global_cities", displayName: "全球城市名", category: "city", role: "root",
    file: "Data/global_cities.txt", defaultEnabled: false, analyzerEnabled: true,
    sourceName: "GeoNames cities15000 via cities-15000-structured 1.0.1", sourceURL: "https://download.geonames.org/export/dump/",
    license: "CC BY 4.0",
  },
  {
    id: "common_names", displayName: "常见英文名", category: "name", role: "root",
    file: "Data/common_names.txt", defaultEnabled: false, analyzerEnabled: true,
    sourceName: "U.S. Social Security Administration national baby names (1880-2021)", sourceURL: "https://www.ssa.gov/oact/babynames/limits.html",
    license: "CC0-1.0 / U.S. government open data",
  },
  {
    id: "keyboard_patterns", displayName: "键盘模式", category: "keyboard", role: "auxiliary",
    file: "Data/keyboard_patterns.txt", defaultEnabled: false, analyzerEnabled: true,
    sourceName: "PatternLab deterministic QWERTY adjacency generator", sourceURL: "",
    license: "Project-generated",
  },
  {
    id: "test_dataset", displayName: "测试来源", category: "test", role: "root",
    file: "Data/test_dataset.txt", defaultEnabled: false, analyzerEnabled: false,
    sourceName: "Project-owner supplied performance fixture", sourceURL: "",
    license: "User supplied; verify redistribution terms before public release",
  },
];

const datasets = definitions.map((definition) => ({
  ...definition,
  ...fileMetadata(path.join(outputBundle, definition.file)),
}));

const manifest = {
  schemaVersion: 1,
  packId: "PatternLabPublicPack",
  packVersion: "3.0.0",
  generatedAt: argumentsMap.get("generated-at") ?? new Date().toISOString(),
  datasets,
};
fs.writeFileSync(path.join(outputBundle, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

for (const dataset of datasets) {
  process.stdout.write(`${dataset.id}: ${dataset.lineCount} lines, ${dataset.byteCount} bytes, ${dataset.sha256}\n`);
}
