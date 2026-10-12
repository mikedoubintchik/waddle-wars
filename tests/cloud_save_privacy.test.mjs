import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import worker from '../leaderboard/src/worker.js';

const ISSUER = 'https://synthetic-cloud-save-privacy.clerk.accounts.dev';
const USER_A = 'synthetic-cloud-player-a';
const USER_B = 'synthetic-cloud-player-b';
const MAX_SAVE_BYTES = 128 * 1024;
const DELETION_FIELDS = ['account_deletion', 'account_deletion_receipt',
  'account_deletion_receipts', 'account_deletion_recovery_owner'];
const DELETION_RECEIPT = 'ab'.repeat(32);
const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5',
  modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
true, ['sign', 'verify']);
const jwk = { ...await crypto.subtle.exportKey('jwk', key.publicKey), kid: 'synthetic-cloud-save-privacy' };
const b64 = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

async function signedToken(user) {
  const unsigned = `${b64({ alg: 'RS256', kid: jwk.kid })}.${b64({
    sub: user, iss: ISSUER, exp: Math.floor(Date.now() / 1000) + 600,
  })}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key.privateKey,
    new TextEncoder().encode(unsigned));
  return `${unsigned}.${Buffer.from(signature).toString('base64url')}`;
}

const tokens = new Map(await Promise.all([USER_A, USER_B].map(async (user) => [user, await signedToken(user)])));

class D1 {
  constructor() {
    this.db = new DatabaseSync(':memory:');
    this.db.exec(readFileSync(new URL('../leaderboard/schema.sql', import.meta.url), 'utf8'));
  }
  prepare(sql) {
    const db = this.db;
    const make = (values = []) => {
      const statement = db.prepare(sql);
      statement.setAllowUnknownNamedParameters(true);
      const args = Object.fromEntries(values.map((value, index) => [String(index + 1), value]));
      return { bind: (...bound) => make(bound), first: async () => statement.get(args) || null,
        run: async () => statement.run(args), all: async () => ({ results: statement.all(args) }) };
    };
    return make();
  }
}

async function fixture(run) {
  const DB = new D1();
  const previousFetch = globalThis.fetch;
  const providerRequests = [];
  globalThis.fetch = async (url) => {
    if (String(url) === `${ISSUER}/.well-known/jwks.json`) {
      return new Response(JSON.stringify({ keys: [jwk] }));
    }
    providerRequests.push(String(url));
    throw new Error('Cloud-save fixture forbids external provider calls');
  };
  const env = { DB, CLERK_ISSUER: ISSUER };
  const request = (method, { user = USER_A, raw, query = '' } = {}) => worker.fetch(new Request(
    `https://worker.example/api/save${query}`, {
      method, headers: { ...(user ? { Authorization: `Bearer ${tokens.get(user)}` } : {}),
        ...(raw !== undefined ? { 'Content-Type': 'application/json' } : {}) },
      ...(raw !== undefined ? { body: raw } : {}),
    }), env);
  const put = (data, options = {}) => request('PUT', { ...options, raw: JSON.stringify(data) });
  const seed = (user, raw) => DB.db.prepare('INSERT INTO saves (user_id, data) VALUES (?, ?)').run(user, raw);
  const stored = (user = USER_A) => DB.db.prepare('SELECT data FROM saves WHERE user_id = ?').get(user)?.data;
  try {
    await run({ DB: DB.db, request, put, seed, stored });
    assert.deepEqual(providerRequests, [], 'Cloud saves must not call account or payment providers');
  } finally {
    globalThis.fetch = previousFetch;
    DB.db.close();
  }
}

const progress = () => ({
  version: 3, fish: 875, xp: 1200, unlocked_cosmetics: ['body_classic', 'hat_earned'],
  equipped: { body: 'body_classic', hat: 'hat_earned', scarf: '', goggles: '', trail: '' },
  achievements: { first_win: true }, stats: { races_finished: 7, races_won: 2, items_used: { snowball: 4 } },
  tutorial_complete: true, best_times: { glacier: 23456 }, endless_high_score: 456,
  daily_last_day: 20728, daily_last_time: 31234, daily_streak: 3, daily_best_streak: 5,
  gp_records: { aurora: { best_points: 18 } }, settings: { audio: { music: 0.4 }, controls: ['left', 'right'] },
  settings_migrated: true,
});

const commerceCache = () => ({
  last_account: USER_B,
  accounts: { [USER_A]: { product_ids: ['synthetic-paid-bundle'], verified_at: '2026-10-02T12:00:00Z' },
    [USER_B]: { product_ids: ['synthetic-other-bundle'], verified_at: '2026-10-01T12:00:00Z' } },
});

const deletionJournal = () => ({
  account_deletion: { [USER_A]: 'pending', [USER_B]: 'retired' },
  account_deletion_receipt: DELETION_RECEIPT,
  account_deletion_receipts: { [USER_A]: DELETION_RECEIPT, [USER_B]: 'cd'.repeat(32) },
  account_deletion_recovery_owner: USER_A,
});

test('cloud-save GET and PUT require authentication and leave stored data unchanged', async () => {
  await fixture(async ({ request, seed, stored }) => {
    const original = JSON.stringify(progress());
    seed(USER_A, original);
    for (const method of ['GET', 'PUT']) {
      const response = await request(method, { user: null, ...(method === 'PUT' ? { raw: '{"fish":1}' } : {}) });
      assert.equal(response.status, 401);
      assert.deepEqual(await response.json(), { error: 'unauthorized' });
    }
    assert.equal(stored(), original);
  });
});

test('PUT strips per-account commerce cache before storage and GET preserves earned progress', async () => {
  await fixture(async ({ put, request, stored }) => {
    const earned = progress();
    const response = await put({ ...earned, commerce: commerceCache() });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
    assert.deepEqual(JSON.parse(stored()), earned);
    assert.equal(stored().includes(USER_A), false);
    assert.equal(stored().includes(USER_B), false);
    const read = await request('GET');
    assert.equal(read.status, 200);
    const body = await read.json();
    assert.equal(body.exists, true);
    assert.equal(typeof body.updated_at, 'string');
    assert.deepEqual(JSON.parse(body.data), earned);
    assert.equal(body.data.includes('synthetic-paid-bundle'), false);
    assert.equal(body.data.includes('synthetic-other-bundle'), false);
  });
});

test('object saves without commerce round-trip nested gameplay and settings fields', async () => {
  await fixture(async ({ put, request, stored }) => {
    const earned = progress();
    assert.equal((await put(earned)).status, 200);
    assert.deepEqual(JSON.parse(stored()), earned);
    assert.deepEqual(JSON.parse((await (await request('GET')).json()).data), earned);
    assert.equal((await put({})).status, 200);
    assert.deepEqual(JSON.parse(stored()), {});
  });
});

test('commerce is excluded regardless of cache value shape', async () => {
  await fixture(async ({ put, stored }) => {
    for (const commerce of [null, [], 'synthetic-cache', 7, true]) {
      assert.equal((await put({ fish: 15, commerce })).status, 200);
      assert.deepEqual(JSON.parse(stored()), { fish: 15 });
    }
  });
});

test('PUT excludes local deletion owners and raw recovery receipts from storage and response', async () => {
  await fixture(async ({ put, request, stored }) => {
    const earned = progress();
    const response = await put({ ...earned, commerce: commerceCache(), ...deletionJournal() });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
    const saved = stored();
    assert.deepEqual(JSON.parse(saved), earned);
    for (const privateValue of [...DELETION_FIELDS, USER_A, USER_B, DELETION_RECEIPT, 'cd'.repeat(32)]) {
      assert.equal(saved.includes(privateValue), false, privateValue);
    }
    const read = await request('GET');
    assert.equal(read.status, 200);
    assert.deepEqual(JSON.parse((await read.json()).data), earned);
  });
});

test('GET excludes every deletion field from legacy responses without rewriting stored row', async () => {
  await fixture(async ({ seed, request, stored, DB }) => {
    const earned = progress();
    const original = JSON.stringify({ ...earned, ...deletionJournal() });
    seed(USER_A, original);
    const rowBefore = DB.prepare('SELECT * FROM saves WHERE user_id = ?').get(USER_A);
    const response = await request('GET');
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.exists, true);
    assert.deepEqual(JSON.parse(body.data), earned);
    for (const privateValue of [...DELETION_FIELDS, USER_A, USER_B, DELETION_RECEIPT, 'cd'.repeat(32)]) {
      assert.equal(body.data.includes(privateValue), false, privateValue);
    }
    assert.equal(stored(), original, 'Response filtering must not perform legacy database purge');
    assert.deepEqual(DB.prepare('SELECT * FROM saves WHERE user_id = ?').get(USER_A), rowBefore,
      'GET must preserve data and updated_at exactly');
  });
});

test('reserved deletion fields are excluded on PUT and legacy GET regardless of JSON value shape', async () => {
  await fixture(async ({ put, request, seed, stored, DB }) => {
    for (const field of DELETION_FIELDS) {
      for (const value of [null, [], {}, DELETION_RECEIPT, 7, true, false, { [USER_A]: DELETION_RECEIPT }]) {
        const data = { fish: 15, [field]: value };
        assert.equal((await put(data)).status, 200, field);
        assert.deepEqual(JSON.parse(stored()), { fish: 15 }, field);
        const original = JSON.stringify(data);
        DB.prepare('DELETE FROM saves WHERE user_id = ?').run(USER_A);
        seed(USER_A, original);
        const read = await request('GET');
        assert.equal(read.status, 200, field);
        assert.deepEqual(JSON.parse((await read.json()).data), { fish: 15 }, field);
        assert.equal(stored(), original, field);
      }
    }
  });
});

test('deletion filtering is top-level only and preserves earned nested gameplay exactly', async () => {
  await fixture(async ({ put, request, stored }) => {
    const earned = progress();
    earned.achievements.account_deletion = { earned: true };
    earned.stats.account_deletion_receipt = 5;
    earned.settings.account_deletion_receipts = ['earned-setting'];
    earned.gp_records.account_deletion_recovery_owner = { best_points: 18 };
    assert.equal((await put({ ...earned, ...deletionJournal() })).status, 200);
    assert.deepEqual(JSON.parse(stored()), earned);
    assert.deepEqual(JSON.parse((await (await request('GET')).json()).data), earned);
  });
});

test('authenticated subjects cannot read or overwrite another account save', async () => {
  await fixture(async ({ put, request, stored, DB }) => {
    const first = { ...progress(), fish: 101 };
    const second = { ...progress(), fish: 202 };
    assert.equal((await put(first, { user: USER_A })).status, 200);
    assert.equal((await put(second, { user: USER_B, query: `?user_id=${USER_A}` })).status, 200);
    assert.deepEqual(JSON.parse(stored(USER_A)), first);
    assert.deepEqual(JSON.parse(stored(USER_B)), second);
    assert.equal(DB.prepare('SELECT COUNT(*) AS n FROM saves').get().n, 2);
    const readA = await request('GET', { user: USER_A, query: `?user_id=${USER_B}` });
    const readB = await request('GET', { user: USER_B, query: `?user_id=${USER_A}` });
    assert.equal(readA.status, 200);
    assert.equal(readB.status, 200);
    assert.deepEqual(JSON.parse((await readA.json()).data), first);
    assert.deepEqual(JSON.parse((await readB.json()).data), second);
  });
});

test('a different authenticated account sees no save when only another subject has one', async () => {
  await fixture(async ({ put, request }) => {
    assert.equal((await put(progress())).status, 200);
    const response = await request('GET', { user: USER_B, query: `?user_id=${USER_A}` });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { exists: false });
  });
});

test('PUT rejects arrays, null and primitive JSON without replacing valid progress', async () => {
  await fixture(async ({ put, seed, stored }) => {
    const original = JSON.stringify(progress());
    seed(USER_A, original);
    for (const value of [[], [progress()], null, 'synthetic-private-save', 42, true, false]) {
      const response = await put(value);
      assert.equal(response.status, 400, `Reject ${JSON.stringify(value)}`);
      assert.equal(typeof (await response.json()).error, 'string');
      assert.equal(stored(), original);
    }
  });
});

test('PUT rejects malformed JSON without inserting a save', async () => {
  await fixture(async ({ request, stored }) => {
    for (const raw of ['', '{', '{"fish":}', '{"fish":2} trailing']) {
      const response = await request('PUT', { raw });
      assert.equal(response.status, 400);
      assert.equal(typeof (await response.json()).error, 'string');
      assert.equal(stored(), undefined);
    }
  });
});

test('PUT rejects save bodies over 128 KiB measured as UTF-8 bytes', async () => {
  await fixture(async ({ request, seed, stored }) => {
    const original = JSON.stringify(progress());
    seed(USER_A, original);
    for (const raw of [JSON.stringify({ notes: 'x'.repeat(MAX_SAVE_BYTES) }),
      JSON.stringify({ notes: '🐧'.repeat(MAX_SAVE_BYTES / 4) })]) {
      assert.ok(Buffer.byteLength(raw, 'utf8') > MAX_SAVE_BYTES);
      const response = await request('PUT', { raw });
      assert.equal(response.status, 413);
      assert.equal(typeof (await response.json()).error, 'string');
      assert.equal(stored(), original);
    }
  });
});

test('GET removes commerce from legacy responses while leaving existing database row intact', async () => {
  await fixture(async ({ seed, request, stored }) => {
    const earned = progress();
    const original = JSON.stringify({ ...earned, commerce: commerceCache() });
    seed(USER_A, original);
    const response = await request('GET');
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.exists, true);
    assert.deepEqual(JSON.parse(body.data), earned);
    assert.equal(body.data.includes(USER_A), false);
    assert.equal(body.data.includes(USER_B), false);
    assert.equal(stored(), original, 'Response filtering must not claim or perform legacy database purge');
  });
});

test('invalid legacy stored JSON returns a safe error without exposing or erasing raw data', async () => {
  await fixture(async ({ seed, request, stored, DB }) => {
    for (const raw of ['[]', '[{"commerce":{"private":"synthetic-secret-cache"}}]', 'null',
      '42', 'true', '"synthetic-secret-cache"', '{"commerce":"synthetic-secret-cache"']) {
      DB.prepare('DELETE FROM saves WHERE user_id = ?').run(USER_A);
      seed(USER_A, raw);
      const response = await request('GET');
      assert.ok(response.status >= 400 && response.status <= 599, 'Invalid legacy data must return an error status');
      const body = await response.json();
      assert.equal(typeof body.error, 'string');
      assert.ok(body.error.length > 0);
      assert.equal(Object.hasOwn(body, 'data'), false);
      assert.equal(JSON.stringify(body).includes('synthetic-secret-cache'), false);
      assert.equal(stored(), raw, 'Read-time error must leave stored legacy row unchanged');
    }
  });
});

test('revisioned sync advertises capability and protects first-write races', async () => {
  await fixture(async ({ request, put, stored }) => {
    assert.deepEqual(await (await request('GET', { query: '?sync=2' })).json(),
      { exists: false, sync_protocol: 2, revision: 'absent' });
    const responses = await Promise.all([100, 200].map((fish) => put({ sync_protocol: 2,
      base_revision: 'absent', progress: { fish, cloud_sync_version: 2 } })));
    assert.deepEqual(responses.map((r) => r.status).sort(), [200, 409]);
    assert.ok([100, 200].includes(JSON.parse(stored()).fish));
  });
});

test('conditional updates reject stale revisions without losing the winning save', async () => {
  await fixture(async ({ request, put, seed, stored }) => {
    seed(USER_A, JSON.stringify({ fish: 100 }));
    const read = await (await request('GET', { query: '?sync=2' })).json();
    assert.match(read.revision, /^[a-f0-9]{64}$/);
    const winner = { fish: 30, cloud_sync_version: 2, unlocked_cosmetics: ['hat_earned'] };
    const update = await put({ sync_protocol: 2, base_revision: read.revision, progress: winner });
    assert.equal(update.status, 200);
    const ack = await update.json();
    assert.notEqual(ack.revision, read.revision);
    const stale = await put({ sync_protocol: 2, base_revision: read.revision, progress: { fish: 999 } });
    assert.equal(stale.status, 409);
    assert.deepEqual(await stale.json(), { error: 'save_revision_conflict' });
    assert.deepEqual(JSON.parse(stored()), winner);
    assert.equal((await (await request('GET', { query: '?sync=2' })).json()).revision, ack.revision);
  });
});

test('concurrent conditional writes cannot both replace the same revision', async () => {
  await fixture(async ({ request, put, seed }) => {
    seed(USER_A, JSON.stringify({ fish: 100 }));
    const { revision } = await (await request('GET', { query: '?sync=2' })).json();
    const responses = await Promise.all([30, 50].map((fish) => put({ sync_protocol: 2,
      base_revision: revision, progress: { fish, cloud_sync_version: 2 } })));
    assert.deepEqual(responses.map((r) => r.status).sort(), [200, 409]);
  });
});

test('upgraded save rejects legacy overwrite and excludes device ownership marker', async () => {
  await fixture(async ({ request, put, stored }) => {
    const response = await put({ sync_protocol: 2, base_revision: 'absent', progress: {
      fish: 10, cloud_sync_version: 2, _cloud_owner: 'private-account-hash', commerce: commerceCache(), ...deletionJournal(),
    } });
    assert.equal(response.status, 200);
    assert.deepEqual(JSON.parse(stored()), { fish: 10, cloud_sync_version: 2 });
    assert.equal((await put({ fish: 999 })).status, 409);
    assert.deepEqual(JSON.parse(stored()), { fish: 10, cloud_sync_version: 2 });
    const get = await (await request('GET', { query: '?sync=2' })).json();
    assert.equal(JSON.stringify(get).includes('private-account-hash'), false);
  });
});

test('bad conditional requests never replace an existing save', async () => {
  await fixture(async ({ put, seed, stored }) => {
    const raw = JSON.stringify({ fish: 200 }); seed(USER_A, raw);
    for (const base_revision of [null, 4, '', 'AB'.repeat(32), {}]) {
      assert.equal((await put({ sync_protocol: 2, base_revision, progress: { fish: 2 } })).status, 400);
      assert.equal(stored(), raw);
    }
    for (const progress of [null, [], 42, 'private']) {
      assert.equal((await put({ sync_protocol: 2, base_revision: 'absent', progress })).status, 400);
      assert.equal(stored(), raw);
    }
  });
});

test('revisioned save uses authenticated account even with another user in query', async () => {
  await fixture(async ({ put, request, stored }) => {
    await put({ sync_protocol: 2, base_revision: 'absent', progress: { fish: 10, cloud_sync_version: 2 } });
    const response = await put({ sync_protocol: 2, base_revision: 'absent', progress: { fish: 20, cloud_sync_version: 2 } },
      { user: USER_B, query: `?user_id=${USER_A}` });
    assert.equal(response.status, 200);
    assert.equal(JSON.parse(stored(USER_A)).fish, 10);
    assert.equal(JSON.parse(stored(USER_B)).fish, 20);
    assert.equal(JSON.parse((await (await request('GET', { user: USER_B, query: '?sync=2' })).json()).data).fish, 20);
  });
});
