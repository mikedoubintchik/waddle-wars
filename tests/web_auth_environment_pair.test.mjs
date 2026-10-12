import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const preset = readFileSync(new URL('../export_presets.cfg', import.meta.url), 'utf8');
const worker = readFileSync(new URL('../leaderboard/wrangler.toml', import.meta.url), 'utf8');
// Public values read from Waddle Wars' own Clerk production instance. This is
// staging evidence only: do not switch either live consumer until account
// continuity and the paired frontend/backend rollout pass their gates.
const PRODUCTION_ISSUER = 'https://clerk.waddlewars.io';
const PRODUCTION_PUBLISHABLE_KEY = 'pk_live_Y2xlcmsud2FkZGxld2Fycy5pbyQ';

function onlyMatch(source, pattern, label) {
  const matches = [...source.matchAll(pattern)];
  assert.equal(matches.length, 1, `expected one ${label}`);
  return matches[0][1];
}

function validatePair(presetText, workerText) {
  const key = onlyMatch(presetText, /data-clerk-publishable-key', '([^']+)'/g, 'Clerk publishable key');
  const src = onlyMatch(presetText, /s\.src = '(https:\/\/[^']+\/npm\/@clerk\/clerk-js@5\/dist\/clerk\.browser\.js)'/g, 'Clerk script URL');
  const issuer = onlyMatch(workerText, /^CLERK_ISSUER = "([^"]+)"$/gm, 'backend Clerk issuer');
  const keyMatch = /^pk_(test|live)_([A-Za-z0-9_-]+)$/.exec(key);
  assert.ok(keyMatch, 'Clerk publishable key format');
  const hostBytes = Buffer.from(keyMatch[2], 'base64url');
  assert.equal(hostBytes.toString('base64url'), keyMatch[2], 'canonical Clerk key encoding');
  const decoded = hostBytes.toString('utf8');
  assert.ok(decoded.endsWith('$'), 'Clerk key host terminator');
  const host = decoded.slice(0, -1);
  const issuerUrl = new URL(issuer);
  assert.equal(issuerUrl.protocol, 'https:');
  assert.equal(issuerUrl.origin, issuer, 'issuer must be origin only');
  assert.equal(new URL(src).origin, issuer, 'frontend and backend must use same issuer');
  assert.equal(issuerUrl.hostname, host, 'publishable key must name issuer host');
  if (keyMatch[1] === 'test') assert.ok(host.endsWith('.clerk.accounts.dev'), 'test key needs development issuer');
  else assert.ok(!host.endsWith('.clerk.accounts.dev'), 'live key needs production issuer');
  return { environment: keyMatch[1], issuer };
}

test('current web shell and leaderboard use same Clerk instance', () => {
  assert.deepEqual(validatePair(preset, worker), {
    environment: 'test', issuer: 'https://stunning-hen-13.clerk.accounts.dev',
  });
});

test('observed Waddle Wars production public pair is internally consistent', () => {
  const candidatePreset = preset
    .replace(/data-clerk-publishable-key', '[^']+'/,
      `data-clerk-publishable-key', '${PRODUCTION_PUBLISHABLE_KEY}'`)
    .replace(/s\.src = 'https:\/\/[^']+\/npm\/@clerk\/clerk-js@5\/dist\/clerk\.browser\.js'/,
      `s.src = '${PRODUCTION_ISSUER}/npm/@clerk/clerk-js@5/dist/clerk.browser.js'`);
  const candidateWorker = worker.replace(/^CLERK_ISSUER = "[^"]+"$/m,
    `CLERK_ISSUER = "${PRODUCTION_ISSUER}"`);
  assert.deepEqual(validatePair(candidatePreset, candidateWorker), {
    environment: 'live', issuer: PRODUCTION_ISSUER,
  });
  assert.throws(() => validatePair(candidatePreset, worker), /frontend and backend must use same issuer/);
  assert.throws(() => validatePair(preset, candidateWorker), /frontend and backend must use same issuer/);
});

test('backend-only Clerk cutover fails closed', () => {
  assert.throws(() => validatePair(preset, worker.replace(
    'https://stunning-hen-13.clerk.accounts.dev',
    PRODUCTION_ISSUER,
  )), /frontend and backend must use same issuer/);
});

test('frontend-only Clerk cutover fails closed', () => {
  const changed = preset.replace(
    "s.src = 'https://stunning-hen-13.clerk.accounts.dev/npm/@clerk/clerk-js@5/dist/clerk.browser.js'",
    `s.src = '${PRODUCTION_ISSUER}/npm/@clerk/clerk-js@5/dist/clerk.browser.js'`,
  );
  assert.notEqual(changed, preset);
  assert.throws(() => validatePair(changed, worker), /frontend and backend must use same issuer/);
});
