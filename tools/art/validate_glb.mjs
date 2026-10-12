#!/usr/bin/env node
// Thin deterministic CLI around KhronosGroup/glTF-Validator's official npm
// build. Runtime game builds never invoke or ship this authoring dependency.

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const validator = require("gltf-validator");
const EXPECTED_VERSION = "2.0.0-dev.3.10";

function fail(message, code = 1) {
  console.error(`[gltf-validator] FAIL ${message}`);
  process.exit(code);
}

const args = process.argv.slice(2);
const foundVersion = String(validator.version());
if (foundVersion !== EXPECTED_VERSION) {
  fail(`expected ${EXPECTED_VERSION}, found ${foundVersion}`, 3);
}
if (args.length === 1 && args[0] === "--version") {
  console.log(`[gltf-validator] PASS ${foundVersion}`);
  process.exit(0);
}
if (args.length === 0) {
  fail("usage: validate_glb.mjs FILE.glb [FILE.glb ...]", 2);
}

let failures = 0;
for (const rawPath of [...new Set(args)].sort()) {
  const assetPath = path.resolve(rawPath);
  if (path.extname(assetPath).toLowerCase() !== ".glb" || !fs.existsSync(assetPath)) {
    console.error(`[gltf-validator] FAIL missing GLB: ${assetPath}`);
    failures += 1;
    continue;
  }
  try {
    const bytes = new Uint8Array(fs.readFileSync(assetPath));
    const report = await validator.validateBytes(bytes, {
      uri: path.basename(assetPath),
      maxIssues: 1000,
    });
    const errors = Number(report.issues?.numErrors ?? 0);
    const warnings = Number(report.issues?.numWarnings ?? 0);
    const infos = Number(report.issues?.numInfos ?? 0);
    const hints = Number(report.issues?.numHints ?? 0);
    if (errors > 0 || warnings > 0) {
      console.error(
        `[gltf-validator] FAIL ${assetPath}: errors=${errors} warnings=${warnings} ` +
          `infos=${infos} hints=${hints}`,
      );
      for (const message of report.issues?.messages ?? []) {
        if (Number(message.severity) <= 1) {
          console.error(
            `[gltf-validator] ${message.code}: ${message.message} ` +
              `${JSON.stringify(message.pointer ?? "")}`,
          );
        }
      }
      failures += 1;
    } else {
      console.log(
        `[gltf-validator] PASS ${assetPath}: errors=0 warnings=0 ` +
          `infos=${infos} hints=${hints}`,
      );
    }
  } catch (error) {
    console.error(`[gltf-validator] FAIL ${assetPath}: ${error}`);
    failures += 1;
  }
}

process.exit(failures === 0 ? 0 : 1);
