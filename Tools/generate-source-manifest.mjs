#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv[2] ?? ".");
const outputName = "SOURCE-MANIFEST.sha256";
const excludedDirectories = new Set([".git", ".build", "build-patternlab", "DerivedData", "Payload"]);

function collect(directory, result = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && excludedDirectories.has(entry.name)) continue;
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      collect(absolute, result);
    } else if (entry.isFile()) {
      const relative = path.relative(root, absolute).split(path.sep).join("/");
      if (relative === outputName || relative.endsWith(".zip") || relative.endsWith(".ipa")) continue;
      result.push({ absolute, relative });
    }
  }
  return result;
}

const files = collect(root).sort((left, right) => left.relative.localeCompare(right.relative));
const lines = files.map(({ absolute, relative }) => {
  const digest = crypto.createHash("sha256").update(fs.readFileSync(absolute)).digest("hex");
  return `${digest}  ${relative}`;
});
fs.writeFileSync(path.join(root, outputName), `${lines.join("\n")}\n`, "utf8");
process.stdout.write(`Wrote ${outputName} for ${files.length} files\n`);
