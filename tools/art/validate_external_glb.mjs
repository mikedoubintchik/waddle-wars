#!/usr/bin/env node
// Khronos validation with local-only external image resolution. No network.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const validator = createRequire(import.meta.url)('gltf-validator');
if (validator.version() !== '2.0.0-dev.3.10' || process.argv.length !== 3) {
  throw new Error('Expected pinned glTF Validator and one GLB argument');
}
const asset = path.resolve(process.argv[2]);
const directory = path.dirname(asset);
const resolved = [];
const report = await validator.validateBytes(new Uint8Array(fs.readFileSync(asset)), {
  uri: path.basename(asset), maxIssues: 1000,
  externalResourceFunction: async (uri) => {
    const filename = decodeURIComponent(uri);
    const target = path.resolve(directory, filename);
    if (path.dirname(target) !== directory || /[:\\]/.test(filename) || path.extname(target) !== '.png') {
      throw new Error(`External URI must be a same-directory PNG: ${uri}`);
    }
    if (path.dirname(fs.realpathSync(target)) !== fs.realpathSync(directory)) {
      throw new Error(`External image symlink leaves package: ${uri}`);
    }
    resolved.push(filename);
    return new Uint8Array(fs.readFileSync(target));
  },
});
console.log(JSON.stringify({ asset, resolved_images: resolved, issues: report.issues }, null, 2));
if (report.issues.numErrors || report.issues.numWarnings || new Set(resolved).size !== 3) process.exit(1);
