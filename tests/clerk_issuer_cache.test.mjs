import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
const worker = (await import(process.env.WADDLE_LEADERBOARD_WORKER
  ? pathToFileURL(process.env.WADDLE_LEADERBOARD_WORKER).href
  : '../leaderboard/src/worker.js')).default;

const issuers = [
  'https://synthetic-development.clerk.accounts.dev',
  'https://synthetic-production.example.invalid',
];
const kid = 'same-kid-across-instances';
const encoder = new TextEncoder();
const encoded = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

test('JWKS cache follows issuer when authentication context changes', async () => {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(process.env.WADDLE_LEADERBOARD_SCHEMA
    || new URL('../leaderboard/schema.sql', import.meta.url), 'utf8'));
  const DB = {
    prepare(sql) {
      const statement = db.prepare(sql);
      return {
        bind(...values) {
          const args = Object.fromEntries(values.map((value, index) => [String(index + 1), value]));
          return { first: async () => statement.get(args) || null };
        },
      };
    },
  };
  const keys = await Promise.all(issuers.map(() => crypto.subtle.generateKey({
    name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256',
  }, true, ['sign', 'verify'])));
  const jwks = await Promise.all(keys.map(async (key) => ({
    ...await crypto.subtle.exportKey('jwk', key.publicKey), kid,
  })));
  const calls = [];
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    const issuer = String(url).replace('/.well-known/jwks.json', '');
    const index = issuers.indexOf(issuer);
    assert.notEqual(index, -1, 'unexpected JWKS issuer');
    calls.push(issuer);
    return new Response(JSON.stringify({ keys: [jwks[index]] }));
  };
  try {
    for (const index of [0, 1, 0]) {
      const payload = { sub: `synthetic-player-${index}`, iss: issuers[index],
        exp: Math.floor(Date.now() / 1000) + 600 };
      const unsigned = `${encoded({ alg: 'RS256', kid })}.${encoded(payload)}`;
      const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', keys[index].privateKey,
        encoder.encode(unsigned));
      const token = `${unsigned}.${Buffer.from(signature).toString('base64url')}`;
      const response = await worker.fetch(new Request('https://worker.example/api/save', {
        headers: { Authorization: `Bearer ${token}` },
      }), { DB, CLERK_ISSUER: issuers[index] });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), { exists: false });
    }
    assert.deepEqual(calls, [issuers[0], issuers[1], issuers[0]]);
  } finally {
    globalThis.fetch = previousFetch;
    db.close();
  }
});
