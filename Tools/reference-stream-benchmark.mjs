#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { performance } from "node:perf_hooks";

const input = path.resolve(
  process.argv[2]
    ?? "WiFiVaultPatternLab/Resources/PatternLabPublicPack.bundle/Data/english_words.txt"
);
const output = path.join(os.tmpdir(), `patternlab-reference-${process.pid}.txt`);
const maximumResults = 1_000_000;
const inputHandle = fs.openSync(input, "r");
const outputHandle = fs.openSync(output, "w");

let leftover = "";
let generated = 0;
let pendingOutput = "";
let peakRSS = process.memoryUsage().rss;
const baselineRSS = peakRSS;
const startedAt = performance.now();

function flush() {
  if (!pendingOutput) return;
  fs.writeSync(outputHandle, pendingOutput, null, "utf8");
  pendingOutput = "";
}

function consumeRoot(root) {
  if (!root || generated >= maximumResults) return;
  for (let suffix = 1; suffix <= 9_999 && generated < maximumResults; suffix += 1) {
    pendingOutput += `${root}${suffix}\n`;
    generated += 1;
    if (pendingOutput.length >= 256 * 1_024) flush();
    if (generated % 10_000 === 0) {
      peakRSS = Math.max(peakRSS, process.memoryUsage().rss);
    }
  }
}

try {
  const buffer = Buffer.allocUnsafe(64 * 1_024);
  while (generated < maximumResults) {
    const bytesRead = fs.readSync(inputHandle, buffer, 0, buffer.length, null);
    if (bytesRead === 0) break;
    const text = leftover + buffer.toString("utf8", 0, bytesRead);
    const lines = text.split("\n");
    leftover = lines.pop() ?? "";
    for (const line of lines) {
      consumeRoot(line.endsWith("\r") ? line.slice(0, -1) : line);
      if (generated >= maximumResults) break;
    }
  }
  if (generated < maximumResults && leftover) consumeRoot(leftover);
  flush();
} finally {
  fs.closeSync(inputHandle);
  fs.closeSync(outputHandle);
}

const durationSeconds = Math.max((performance.now() - startedAt) / 1_000, 0.000_001);
const bytes = fs.statSync(output).size;
fs.rmSync(output, { force: true });

const result = {
  generated,
  durationSeconds,
  linesPerSecond: generated / durationSeconds,
  outputBytes: bytes,
  baselineRSSBytes: baselineRSS,
  peakRSSBytes: peakRSS,
  incrementalRSSBytes: peakRSS - baselineRSS,
};
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);

if (generated !== maximumResults) throw new Error("Did not reach one million lines");
if (result.linesPerSecond <= 10_000) throw new Error("Reference throughput is below target");
