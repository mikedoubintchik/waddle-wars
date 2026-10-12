// Run the exact release artifact in workerd with an isolated local D1 database.
// No external requests are permitted. All identities and scores are synthetic.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { Miniflare } = require('../../leaderboard/node_modules/miniflare');
const [workerArgument, schemaArgument, receiptArgument] = process.argv.slice(2);
if (!workerArgument || !schemaArgument || !receiptArgument) {
  throw new Error('Usage: node verify_leaderboard_runtime.mjs WORKER SCHEMA RECEIPT');
}
const workerPath = resolve(workerArgument), schemaPath = resolve(schemaArgument);
const issuer = 'https://synthetic-leaderboard-runtime.example.invalid';
const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
  publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const jwk = { ...await crypto.subtle.exportKey('jwk', key.publicKey), kid: 'synthetic-runtime' };
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
async function tokenFor(sub) {
  const unsigned = `${encode({ alg: 'RS256', kid: jwk.kid })}.${encode({
    sub, iss: issuer, exp: Math.floor(Date.now() / 1000) + 600,
    name: 'Private provider name', email: 'synthetic-private@example.invalid',
  })}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key.privateKey,
    new TextEncoder().encode(unsigned));
  return `${unsigned}.${Buffer.from(signature).toString('base64url')}`;
}
const token = await tokenFor('synthetic-runtime-player');
const checked = [];
const outgoing = [];
const mf = new Miniflare({ modules: true, scriptPath: workerPath, compatibilityDate: '2026-08-01',
  d1Databases: { DB: 'isolated-leaderboard-release-check' },
  bindings: { CLERK_ISSUER: issuer },
  outboundService: async request => {
    outgoing.push(request.url);
    assert.equal(request.url, `${issuer}/.well-known/jwks.json`, 'external provider traffic forbidden');
    return new Response(JSON.stringify({ keys: [jwk] }), { headers: { 'Content-Type': 'application/json' } });
  },
});
const api = (path, { method = 'GET', body, signed = false } = {}) => mf.dispatchFetch(
  `https://worker.example${path}`, { method, headers: {
    Origin: 'https://play.waddlewars.io', ...(signed ? { Authorization: `Bearer ${token}` } : {}),
    ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
  }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
async function post(mode, course, value) {
  const response = await api('/api/scores', { method: 'POST', signed: true, body: { mode, course, value } });
  assert.equal(response.status, 200);
  return response.json();
}
try {
  const DB = await mf.getD1Database('DB');
  // D1 exec accepts multiple statements on one line. Preserve source bytes in
  // the receipt while stripping comments for this local initialization only.
  const schema = readFileSync(schemaPath, 'utf8').replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');
  await DB.exec(schema);
  const health = await api('/api/health');
  assert.equal(health.status, 200); assert.deepEqual(await health.json(), { ok: true });
  const preflight = await api('/api/scores', { method: 'OPTIONS' });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), '*');
  checked.push('health and browser CORS preflight');
  const denied = await api('/api/scores', { method: 'POST', body: { mode: 'runner', course: 'runner', value: 20 } });
  assert.equal(denied.status, 401);
  checked.push('unsigned score rejected');
  for (const [mode, course, value] of [
    ...['glacier', 'aurora', 'iceberg', 'cinder', 'hollow'].map(course => ['time', course, 25000]),
    ['runner', 'runner', 12345], ['endless', 'endless', 987],
  ]) {
    const posted = await post(mode, course, value);
    assert.equal(posted.best, value); assert.equal(posted.improved, true);
    assert.equal(posted.name, 'Penguin');
    const publicResponse = await api(`/api/leaderboard?mode=${mode}&course=${course}`);
    assert.equal(publicResponse.status, 200);
    const board = await publicResponse.json();
    assert.deepEqual(board.entries, [{ rank: 1, name: 'Penguin', value, is_me: false }]);
    assert.equal(board.me, null);
    checked.push(`${mode}/${course}: verified JWT, submit, public fetch`);
  }
  const own = await (await api('/api/leaderboard?mode=runner&course=runner', { signed: true })).json();
  assert.equal(own.entries[0].is_me, true); assert.deepEqual(own.me, { rank: 1, value: 12345 });
  checked.push('signed-in rank and ownership');
  await Promise.all([post('runner', 'runner', 90000), post('runner', 'runner', 1000)]);
  await Promise.all([post('time', 'glacier', 20000), post('time', 'glacier', 90000)]);
  assert.equal((await post('runner', 'runner', 2000)).best, 90000);
  assert.equal((await post('time', 'glacier', 90000)).best, 20000);
  checked.push('concurrent score writes and retries preserve best');
  for (const value of [true, '10000', 1.5, null, 1_000_000_001]) {
    const response = await api('/api/scores', { method: 'POST', signed: true,
      body: { mode: 'runner', course: 'runner', value } });
    assert.equal(response.status, 400);
  }
  assert.equal((await api('/api/leaderboard?mode=runner&course=glacier')).status, 400);
  checked.push('integer bounds and mode separation');
  const profile = await api('/api/profile', { method: 'POST', signed: true, body: { name: 'Ice Explorer' } });
  assert.equal(profile.status, 200);
  assert.deepEqual(await (await api('/api/profile', { signed: true })).json(), { name: 'Ice Explorer' });
  assert.equal((await (await api('/api/leaderboard?mode=runner&course=runner')).json()).entries[0].name, 'Ice Explorer');
  checked.push('custom public name save, read and board update');
  const localSave = { fish: 35, legacy_fixture: { unknown_field: true } };
  assert.equal((await api('/api/save', { method: 'PUT', signed: true, body: localSave })).status, 200);
  const restored = await (await api('/api/save', { signed: true })).json();
  assert.equal(restored.exists, true); assert.deepEqual(JSON.parse(restored.data), localSave);
  checked.push('unchanged deployed legacy save roundtrip');
  assert.ok(outgoing.length >= 1);
  const receipt = { worker: workerPath,
    worker_sha256: createHash('sha256').update(readFileSync(workerPath)).digest('hex'),
    schema: schemaPath, schema_sha256: createHash('sha256').update(readFileSync(schemaPath)).digest('hex'),
    runtime: 'Miniflare/workerd with real isolated D1', passed: checked.length, failed: 0, skipped: 0,
    production_writes: 0, checks: checked, outbound_requests: outgoing };
  writeFileSync(receiptArgument, JSON.stringify(receipt, null, 2) + '\n');
  console.log(JSON.stringify({ passed: receipt.passed, failed: 0, skipped: 0, receipt: receiptArgument }));
} finally {
  await mf.dispose();
}
