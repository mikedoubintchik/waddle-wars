import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import worker from '../leaderboard/src/worker.js';
import { handleAccountLifecycle, isSubjectRetired, requireActiveSubject,
  retireSubjectData, retryPendingIdentityDeletions } from '../leaderboard/src/account_lifecycle.mjs';
import { persistNativePurchase } from '../leaderboard/src/commerce.mjs';
import { PRODUCTS } from '../leaderboard/src/commerce_catalog.mjs';

const USER = 'synthetic-retired-player';
const OTHER = 'synthetic-active-player';
const ISSUER = 'https://synthetic-retirement.clerk.accounts.dev';
const ORIGIN = 'https://worker.example';
const PRODUCT = PRODUCTS[0].id;
const RECEIPT = '12'.repeat(32);
const OTHER_RECEIPT = 'ab'.repeat(32);
const receiptHash = (receipt) => createHash('sha256').update(receipt).digest('hex');
const RECEIPT_MIGRATION = new URL('../leaderboard/migrations/0007_deletion_receipts.sql', import.meta.url);
const PERSONAL_TABLES = ['scores', 'profiles', 'saves', 'commerce_native_auth_requests', 'commerce_native_auth_sessions'];
const RETAINED_TABLES = ['commerce_checkouts', 'commerce_purchases', 'commerce_store_accounts'];
const SUBJECT_TABLES = [...PERSONAL_TABLES, ...RETAINED_TABLES];
const httpMethod = (init) => init.method || 'GET';

// Real migrations, SQL constraints and rollback: no mocked SQL interpretation.
class D1 {
  constructor({ deletionReceipts = true } = {}) {
    this.db = new DatabaseSync(':memory:');
    this.pendingBatch = Promise.resolve();
    this.db.exec('PRAGMA foreign_keys = ON');
    this.db.exec(readFileSync(new URL('../leaderboard/schema.sql', import.meta.url), 'utf8'));
    for (const migration of ['0001_commerce.sql', '0002_native_auth.sql', '0003_store_notifications.sql',
      '0004_apple_snapshot_order.sql', '0005_native_auth_presentation.sql', '0006_account_retirement.sql']) {
      this.db.exec(readFileSync(new URL(`../leaderboard/migrations/${migration}`, import.meta.url), 'utf8'));
    }
    if (deletionReceipts) this.db.exec(readFileSync(RECEIPT_MIGRATION, 'utf8'));
  }
  prepare(sql) {
    const db = this.db;
    const make = (values = []) => {
      const statement = db.prepare(sql);
      statement.setAllowUnknownNamedParameters(true);
      const parameters = Object.fromEntries(values.map((value, index) => [String(index + 1), value]));
      return { bind: (...bound) => make(bound), first: async () => statement.get(parameters) || null,
        all: async () => ({ results: statement.all(parameters) }), run: async () => statement.run(parameters) };
    };
    return make();
  }
  async batch(statements) {
    // D1 serializes atomic batches; exercise concurrent requests without nesting
    // synthetic SQLite transactions or mocking SQL ownership decisions.
    const queued = this.pendingBatch.then(async () => {
      this.db.exec('BEGIN');
      try {
        const results = [];
        for (const statement of statements) results.push(await statement.run());
        this.db.exec('COMMIT');
        return results;
      } catch (error) {
        this.db.exec('ROLLBACK');
        throw error;
      }
    });
    this.pendingBatch = queued.catch(() => {});
    return queued;
  }
}

function environment() {
  return { DB: new D1(), CLERK_ISSUER: ISSUER, COMMERCE_ENABLED: 'true', COMMERCE_MODE: 'test',
    COMMERCE_ALLOWED_ORIGINS: ORIGIN };
}

function subjectInserts(user) {
  return [
    ['scores', 'INSERT INTO scores(user_id, name, mode, course, value) VALUES (?, ?, ?, ?, ?)',
      [user, 'Ice Waddler', 'time', 'glacier', 20000]],
    ['profiles', 'INSERT INTO profiles(user_id, name) VALUES (?, ?)', [user, 'Ice Waddler']],
    ['saves', 'INSERT INTO saves(user_id, data) VALUES (?, ?)', [user, '{"fish":875}']],
    ['commerce_store_accounts', 'INSERT INTO commerce_store_accounts(user_id, apple_account_token, google_account_id) VALUES (?, ?, ?)',
      [user, `${user}-apple`, `${user}-google`]],
    ['commerce_native_auth_requests', `INSERT INTO commerce_native_auth_requests(request_id, challenge, state, user_id,
      clerk_session_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [`${user}-request`, 'challenge', 'approved', user, 'sess_fixture', 2147483647, 1]],
    ['commerce_native_auth_sessions', `INSERT INTO commerce_native_auth_sessions(request_id, verifier_hash, user_id,
      clerk_session_id, expires_at) VALUES (?, ?, ?, ?, ?)`,
    [`${user}-request`, 'verifier-hash', user, 'sess_fixture', 2147483647]],
    ['commerce_checkouts', `INSERT INTO commerce_checkouts(request_id, user_id, product_id, stripe_session_id,
      payment_intent_id, state) VALUES (?, ?, ?, ?, ?, ?)`,
    [`${user}-order`, user, PRODUCT, `cs_${user}`, `pi_${user}`, 'paid']],
    ['commerce_purchases', `INSERT INTO commerce_purchases(provider, transaction_id, user_id, product_id,
      payment_reference, state, provider_signed_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ['apple', `${user}-transaction`, user, PRODUCT, `${user}-receipt`, 'active', 100]],
  ];
}

function seed(env, user = USER) {
  for (const [, sql, values] of subjectInserts(user)) env.DB.db.prepare(sql).run(...values);
}

function snapshot(env, user) {
  return Object.fromEntries(SUBJECT_TABLES.map((table) => [table,
    env.DB.db.prepare(`SELECT * FROM ${table} WHERE user_id = ?`).all(user)]));
}

function markRetired(env, user = USER) {
  env.DB.db.prepare('INSERT INTO account_retirements(user_id) VALUES (?)').run(user);
}

const retiredError = (error) => error.code === 'account_retired' && error.status === 403;

test('retirement atomically erases personal rows and retains financial evidence for only requested subject', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close());
  seed(env); seed(env, OTHER);
  const otherBefore = snapshot(env, OTHER);
  const retainedBefore = snapshot(env, USER);
  const marker = await retireSubjectData(env, USER);
  assert.equal(typeof marker.retired_at, 'string');
  assert.equal(marker.clerk_deleted_at, null);
  assert.equal(await isSubjectRetired(env, USER), true);
  assert.equal(await isSubjectRetired(env, OTHER), false);
  await assert.rejects(requireActiveSubject(env, USER), retiredError);
  await requireActiveSubject(env, OTHER);
  const after = snapshot(env, USER);
  for (const table of PERSONAL_TABLES) assert.deepEqual(after[table], [], `${table} must be erased`);
  for (const table of RETAINED_TABLES) assert.deepEqual(after[table], retainedBefore[table], `${table} proof must remain`);
  assert.deepEqual(snapshot(env, OTHER), otherBefore);
  assert.deepEqual(await retireSubjectData(env, USER), marker, 'Repeated retirement must preserve original marker');
});

test('failed personal erasure rolls back retirement marker and every earlier deletion', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env);
  const before = snapshot(env, USER);
  env.DB.db.exec(`CREATE TRIGGER fail_save_erasure BEFORE DELETE ON saves
    BEGIN SELECT RAISE(ABORT, 'synthetic_erasure_failure'); END;`);
  await assert.rejects(retireSubjectData(env, USER), /synthetic_erasure_failure/);
  assert.equal(await isSubjectRetired(env, USER), false);
  assert.deepEqual(snapshot(env, USER), before);
});

test('every subject table rejects retired inserts regardless of request-level checks', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); markRetired(env);
  for (const [table, sql, values] of subjectInserts(USER)) {
    assert.throws(() => env.DB.db.prepare(sql).run(...values), /account_retired/, table);
  }
  seed(env, OTHER);
  for (const table of SUBJECT_TABLES) assert.equal(snapshot(env, OTHER)[table].length, 1);
  for (const table of ['commerce_checkouts', 'commerce_purchases']) {
    const [, sql, values] = subjectInserts(USER).find(([name]) => name === table);
    for (const state of ['refunded', 'disputed']) {
      const attempt = [...values]; attempt[5] = state;
      assert.throws(() => env.DB.db.prepare(sql).run(...attempt), /account_retired/, `${table} new ${state} evidence`);
    }
  }
});

test('personal/auth/store updates cannot mutate or transfer retired identity in either direction', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER); markRetired(env);
  const checks = [
    ['scores', 'name', 'Changed'], ['profiles', 'name', 'Changed'], ['saves', 'data', '{}'],
    ['commerce_store_accounts', 'apple_account_token', 'changed-apple'],
    ['commerce_native_auth_requests', 'state', 'exchanged'], ['commerce_native_auth_sessions', 'revoked', 1],
  ];
  for (const [table, column, value] of checks) {
    assert.throws(() => env.DB.db.prepare(`UPDATE ${table} SET ${column} = ? WHERE user_id = ?`).run(value, USER),
      /account_retired/, `${table} retired update`);
    assert.throws(() => env.DB.db.prepare(`UPDATE ${table} SET user_id = ? WHERE user_id = ?`).run(USER, OTHER),
      /account_retired/, `${table} transfer into retired identity`);
    assert.throws(() => env.DB.db.prepare(`UPDATE ${table} SET user_id = ? WHERE user_id = ?`).run('new-player', USER),
      /account_retired/, `${table} transfer out of retired identity`);
  }
});

test('anonymous PKCE requests survive subject sweep but cannot approve retired identity later', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env);
  env.DB.db.prepare(`INSERT INTO commerce_native_auth_requests(request_id, challenge, expires_at, created_at)
    VALUES (?, ?, ?, ?)`).run('anonymous-request', 'challenge', 2147483647, 1);
  await retireSubjectData(env, USER);
  assert.throws(() => env.DB.db.prepare(`UPDATE commerce_native_auth_requests SET state = 'approved',
    user_id = ?, clerk_session_id = 'sess_fixture' WHERE request_id = 'anonymous-request'`).run(USER), /account_retired/);
  const anonymous = env.DB.db.prepare('SELECT user_id, state FROM commerce_native_auth_requests WHERE request_id = ?')
    .get('anonymous-request');
  assert.equal(anonymous.user_id, null); assert.equal(anonymous.state, 'pending');
  env.DB.db.prepare(`UPDATE commerce_native_auth_requests SET state = 'approved', user_id = ?,
    clerk_session_id = 'sess_other' WHERE request_id = 'anonymous-request'`).run(OTHER);
});

test('retired financial proof accepts same-subject refunds/disputes and refuses reactivation or ownership transfer', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER);
  await retireSubjectData(env, USER);
  for (const table of ['commerce_checkouts', 'commerce_purchases']) {
    const initial = table === 'commerce_checkouts' ? 'paid' : 'active';
    assert.throws(() => env.DB.db.prepare(`UPDATE ${table} SET state = ? WHERE user_id = ?`).run(initial, USER), /account_retired/);
    env.DB.db.prepare(`UPDATE ${table} SET state = 'disputed' WHERE user_id = ?`).run(USER);
    env.DB.db.prepare(`UPDATE ${table} SET state = 'refunded' WHERE user_id = ?`).run(USER);
    assert.throws(() => env.DB.db.prepare(`UPDATE ${table} SET state = ? WHERE user_id = ?`).run(initial, USER), /account_retired/);
    assert.throws(() => env.DB.db.prepare(`UPDATE ${table} SET user_id = ? WHERE user_id = ?`).run('new-player', USER), /account_retired/);
    env.DB.db.prepare(`UPDATE ${table} SET state = 'refunded' WHERE user_id = ?`).run(OTHER);
    assert.throws(() => env.DB.db.prepare(`UPDATE ${table} SET user_id = ? WHERE user_id = ?`).run(USER, OTHER), /account_retired/);
    env.DB.db.prepare(`UPDATE ${table} SET state = ? WHERE user_id = ?`).run(initial, OTHER);
  }
  assert.throws(() => env.DB.db.prepare(`UPDATE commerce_checkouts SET state = 'pending' WHERE user_id = ?`).run(USER), /account_retired/);
});

test('refund reversal tombstone deletion cannot remove retirement or recreate ownership', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env);
  env.DB.db.prepare("UPDATE commerce_purchases SET state = 'refunded', provider_signed_at = 200 WHERE user_id = ?").run(USER);
  env.DB.db.prepare('INSERT INTO commerce_revocations(provider, transaction_id, provider_signed_at) VALUES (?, ?, ?)')
    .run('apple', `${USER}-transaction`, 200);
  await retireSubjectData(env, USER);
  env.DB.db.prepare('DELETE FROM commerce_revocations WHERE provider = ? AND transaction_id = ?')
    .run('apple', `${USER}-transaction`);
  assert.equal(await isSubjectRetired(env, USER), true);
  assert.equal(await persistNativePurchase(env, { provider: 'apple', transaction_id: `${USER}-transaction`,
    user_id: USER, product_id: PRODUCT, payment_reference: `${USER}-receipt`, state: 'active', provider_signed_at: 300 },
  { appleRefundReversal: true }), 'retired');
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases WHERE user_id = ?').get(USER).state, 'refunded');
});

test('retirement racing verified refund reversal rolls back tombstone deletion and suppresses grant', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env);
  env.DB.db.prepare("UPDATE commerce_purchases SET state = 'refunded', provider_signed_at = 200 WHERE user_id = ?").run(USER);
  env.DB.db.prepare('INSERT INTO commerce_revocations(provider, transaction_id, provider_signed_at) VALUES (?, ?, ?)')
    .run('apple', `${USER}-transaction`, 200);
  const batch = env.DB.batch.bind(env.DB);
  env.DB.batch = async (statements) => {
    // Pause callback precisely after its preflight reads, before its SQL batch.
    env.DB.batch = batch;
    await retireSubjectData(env, USER);
    return batch(statements);
  };
  assert.equal(await persistNativePurchase(env, { provider: 'apple', transaction_id: `${USER}-transaction`,
    user_id: USER, product_id: PRODUCT, payment_reference: `${USER}-receipt`, state: 'active', provider_signed_at: 300 },
  { appleRefundReversal: true }), 'retired');
  assert.equal(env.DB.db.prepare('SELECT provider_signed_at FROM commerce_revocations WHERE transaction_id = ?')
    .get(`${USER}-transaction`).provider_signed_at, 200);
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases WHERE user_id = ?').get(USER).state, 'refunded');
});

test('retirement racing native fulfillment prevents new transaction and provider acknowledgment', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env);
  const batch = env.DB.batch.bind(env.DB);
  env.DB.batch = async (statements) => {
    env.DB.batch = batch;
    await retireSubjectData(env, USER);
    return batch(statements);
  };
  let acknowledgments = 0;
  assert.equal(await persistNativePurchase(env, { provider: 'google', transaction_id: 'delayed-google-token-hash',
    user_id: USER, product_id: PRODUCT, payment_reference: 'GPA.synthetic', state: 'active',
    acknowledge: async () => { acknowledgments++; } }), 'retired');
  assert.equal(acknowledgments, 0);
  assert.equal(env.DB.db.prepare("SELECT COUNT(*) AS n FROM commerce_purchases WHERE provider = 'google'").get().n, 0);
});

test('write authorized before retirement loses race at database fence and batch changes roll back', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER);
  await requireActiveSubject(env, USER);
  const delayedScore = env.DB.prepare('INSERT INTO scores(user_id, name, mode, course, value) VALUES (?1, ?2, ?3, ?4, ?5)')
    .bind(USER, 'Old pending request', 'endless', 'endless', 500);
  await retireSubjectData(env, USER);
  await assert.rejects(env.DB.batch([
    env.DB.prepare('UPDATE profiles SET name = ?2 WHERE user_id = ?1').bind(OTHER, 'Should rollback'), delayedScore,
  ]), /account_retired/);
  assert.equal(env.DB.db.prepare('SELECT name FROM profiles WHERE user_id = ?').get(OTHER).name, 'Ice Waddler');
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM scores WHERE user_id = ?').get(USER).n, 0);
});

const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
  publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const jwk = { ...await crypto.subtle.exportKey('jwk', key.publicKey), kid: 'synthetic-account-retirement' };
const encoded = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

async function signedToken(user, overrides = {}) {
  const unsigned = `${encoded({ alg: 'RS256', kid: jwk.kid })}.${encoded({
    sub: user, sid: 'sess_fixture', iss: ISSUER, iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 600, ...overrides,
  })}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key.privateKey, new TextEncoder().encode(unsigned));
  return `${unsigned}.${Buffer.from(signature).toString('base64url')}`;
}

function deletionRequest({ method = 'POST', path = 'delete', origin = ORIGIN,
  body = JSON.stringify({ confirm: 'DELETE_ACCOUNT', recovery_receipt: RECEIPT }), token = 'fixture-auth' } = {}) {
  return new Request(`${ORIGIN}/api/account/${path}`, { method,
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(origin ? { Origin: origin } : {}),
      'Content-Type': 'application/json' }, ...(method === 'POST' ? { body } : {}) });
}

function receiptRequest({ method = 'GET', receipt = RECEIPT, origin = ORIGIN, query = '', headers = {} } = {}) {
  return new Request(`${ORIGIN}/api/account/deletion/receipt${query}`, { method,
    headers: { ...(origin ? { Origin: origin } : {}),
      ...(receipt === null ? {} : { 'X-Waddle-Deletion-Receipt': receipt }), ...headers } });
}

function enableDeletion(env) {
  return Object.assign(env, { ACCOUNT_DELETION_ENABLED: 'true', CLERK_SECRET_KEY: 'synthetic-fixture-secret',
    ACCOUNT_DELETION_LIMITER: { limit: async () => ({ success: true }) } });
}

test('deletion gates reject before retirement or provider calls', async (t) => {
  const cases = [
    { name: 'disabled', overrides: { ACCOUNT_DELETION_ENABLED: 'false' }, status: 503 },
    { name: 'missing provider credential', overrides: { CLERK_SECRET_KEY: '' }, status: 503 },
    { name: 'unauthenticated', claims: null, status: 401 },
    { name: 'stale authentication', claims: { iat: Math.floor(Date.now() / 1000) - 301 }, status: 401 },
    { name: 'future authentication', claims: { iat: Math.floor(Date.now() / 1000) + 31 }, status: 401 },
    { name: 'missing authentication time', claims: { iat: undefined }, status: 401 },
    { name: 'unapproved origin', request: { origin: 'https://attacker.example' }, status: 403 },
    { name: 'rate limited', overrides: { ACCOUNT_DELETION_LIMITER: { limit: async () => ({ success: false }) } }, status: 429 },
    { name: 'bad confirmation', request: { body: '{"confirm":"delete"}' }, status: 400 },
    { name: 'extra body keys', request: { body: '{"confirm":"DELETE_ACCOUNT","user_id":"other-player"}' }, status: 400 },
    { name: 'missing receipt', request: { body: '{"confirm":"DELETE_ACCOUNT"}' }, status: 400 },
    { name: 'extra field with receipt', request: { body: JSON.stringify({ confirm: 'DELETE_ACCOUNT',
      recovery_receipt: RECEIPT, user_id: OTHER }) }, status: 400 },
    ...[null, 123, 'a'.repeat(63), 'a'.repeat(65), 'AB'.repeat(32), 'zz'.repeat(32), `${RECEIPT}\n`]
      .map((receipt) => ({ name: `invalid receipt ${JSON.stringify(receipt)}`, request: {
        body: JSON.stringify({ confirm: 'DELETE_ACCOUNT', recovery_receipt: receipt }) }, status: 400 })),
    { name: 'invalid JSON', request: { body: '{' }, status: 400 },
    { name: 'oversized body', request: { body: 'x'.repeat(4097) }, status: 413 },
  ];
  for (const entry of cases) {
    const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
    Object.assign(env, entry.overrides);
    const before = snapshot(env, USER);
    const claims = entry.claims === null ? null : { sub: USER, iat: Math.floor(Date.now() / 1000), ...entry.claims };
    let providerCalls = 0;
    const response = await handleAccountLifecycle(deletionRequest(entry.request), env, async () => claims,
      { fetcher: async () => { providerCalls++; throw new Error('Provider must not run'); } });
    assert.equal(response.status, entry.status, entry.name);
    assert.equal(providerCalls, 0, entry.name);
    assert.equal(await isSubjectRetired(env, USER), false, entry.name);
    assert.deepEqual(snapshot(env, USER), before, entry.name);
  }
});

test('receipt migration supports fresh and existing databases without inventing receipts for retired markers', async (t) => {
  for (const existing of [false, true]) {
    const env = enableDeletion(environment()); t.after(() => env.DB.db.close());
    if (existing) {
      env.DB.db.close();
      env.DB = new D1({ deletionReceipts: false });
      seed(env); seed(env, OTHER); markRetired(env, OTHER);
      const before = snapshot(env, OTHER);
      env.DB.db.exec(readFileSync(RECEIPT_MIGRATION, 'utf8'));
      assert.deepEqual(snapshot(env, OTHER), before);
      assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM account_deletion_receipts').get().n, 0);
    } else seed(env);
    // Reapplying the migration must preserve the same schema/data.
    env.DB.db.exec(readFileSync(RECEIPT_MIGRATION, 'utf8'));
    await retireSubjectData(env, USER, RECEIPT);
    assert.deepEqual({ ...env.DB.db.prepare('SELECT * FROM account_deletion_receipts').get() },
      { receipt_hash: receiptHash(RECEIPT), user_id: USER });
    assert.deepEqual(env.DB.db.prepare('PRAGMA foreign_key_check').all(), []);
    if (existing) {
      await assert.rejects(retireSubjectData(env, OTHER, OTHER_RECEIPT),
        (error) => error.code === 'deletion_receipt_conflict' && error.status === 409);
      assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM account_deletion_receipts').get().n, 1);
    }
  }
});

test('receipt hash, retirement marker and all personal erasure roll back together', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const before = snapshot(env, USER);
  env.DB.db.exec(`CREATE TRIGGER fail_receipt_save_erasure BEFORE DELETE ON saves
    BEGIN SELECT RAISE(ABORT, 'synthetic_receipt_erasure_failure'); END;`);
  let providerCalls = 0;
  const response = await handleAccountLifecycle(deletionRequest(), env,
    async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) }),
    { fetcher: async () => { providerCalls++; throw new Error('Provider must not run'); } });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'account_deletion_unavailable' });
  assert.equal(providerCalls, 0);
  assert.equal(await isSubjectRetired(env, USER), false);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM account_deletion_receipts').get().n, 0);
  assert.deepEqual(snapshot(env, USER), before);
});

test('receipt ownership is immutable and a digest collision cannot erase another subject', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER);
  await retireSubjectData(env, USER, RECEIPT);
  const marker = env.DB.db.prepare('SELECT * FROM account_retirements WHERE user_id = ?').get(USER);
  const otherBefore = snapshot(env, OTHER);
  const conflict = (error) => error.code === 'deletion_receipt_conflict' && error.status === 409;
  await assert.rejects(retireSubjectData(env, OTHER, RECEIPT), conflict);
  await assert.rejects(retireSubjectData(env, USER, OTHER_RECEIPT), conflict);
  assert.deepEqual(snapshot(env, OTHER), otherBefore);
  assert.equal(await isSubjectRetired(env, OTHER), false);
  assert.deepEqual(env.DB.db.prepare('SELECT * FROM account_retirements WHERE user_id = ?').get(USER), marker);
  assert.deepEqual({ ...env.DB.db.prepare('SELECT * FROM account_deletion_receipts').get() },
    { receipt_hash: receiptHash(RECEIPT), user_id: USER });
  assert.throws(() => env.DB.db.prepare('UPDATE account_deletion_receipts SET user_id = ?').run(OTHER), /deletion_receipt_conflict/);
  assert.throws(() => env.DB.db.prepare('UPDATE account_deletion_receipts SET receipt_hash = ?').run(receiptHash(OTHER_RECEIPT)),
    /deletion_receipt_conflict/);
  assert.throws(() => env.DB.db.prepare('INSERT INTO account_deletion_receipts(receipt_hash, user_id) VALUES (?, ?)')
    .run('NOT_A_SHA256', OTHER), /CHECK constraint failed/);
  assert.throws(() => env.DB.db.prepare('INSERT INTO account_deletion_receipts(receipt_hash, user_id) VALUES (?, ?)')
    .run(receiptHash(OTHER_RECEIPT), OTHER), /FOREIGN KEY constraint failed/);
});

test('concurrent same-owner receipts are idempotent and token rotation cannot win a second registration', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const authenticate = async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) });
  const fetcher = async () => new Response(null, { status: 503 });
  const responses = await Promise.all([0, 1].map(() =>
    handleAccountLifecycle(deletionRequest(), env, authenticate, { fetcher })));
  assert.deepEqual(responses.map((response) => response.status), [202, 202]);
  assert.deepEqual(await responses[0].json(), await responses[1].json());
  const marker = env.DB.db.prepare('SELECT * FROM account_retirements WHERE user_id = ?').get(USER);
  const rotated = await handleAccountLifecycle(deletionRequest({ body: JSON.stringify({
    confirm: 'DELETE_ACCOUNT', recovery_receipt: OTHER_RECEIPT }) }), env, authenticate, { fetcher });
  assert.equal(rotated.status, 409);
  assert.deepEqual(await rotated.json(), { error: 'deletion_receipt_conflict' });
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM account_deletion_receipts').get().n, 1);
  assert.deepEqual(env.DB.db.prepare('SELECT * FROM account_retirements WHERE user_id = ?').get(USER), marker);
});

test('cross-owner registration race has exactly one retirement and cannot steal its receipt', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER);
  const before = { [USER]: snapshot(env, USER), [OTHER]: snapshot(env, OTHER) };
  const responses = await Promise.all([USER, OTHER].map((user) => handleAccountLifecycle(deletionRequest(), env,
    async () => ({ sub: user, iat: Math.floor(Date.now() / 1000) }),
    { fetcher: async () => new Response(null, { status: 503 }) })));
  assert.deepEqual(responses.map((response) => response.status).sort(), [202, 409]);
  const owner = env.DB.db.prepare('SELECT user_id FROM account_deletion_receipts').get().user_id;
  const loser = owner === USER ? OTHER : USER;
  assert.equal(await isSubjectRetired(env, owner), true);
  assert.equal(await isSubjectRetired(env, loser), false);
  assert.deepEqual(snapshot(env, loser), before[loser]);
  for (const table of PERSONAL_TABLES) assert.deepEqual(snapshot(env, owner)[table], []);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM account_deletion_receipts').get().n, 1);
});

test('receipt status is read-only, hash-only, minimal and independent of JWT or provider credentials', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  await retireSubjectData(env, USER, RECEIPT);
  const stored = env.DB.db.prepare('SELECT * FROM account_deletion_receipts').get();
  assert.deepEqual(Object.keys(stored).sort(), ['receipt_hash', 'user_id']);
  assert.equal(stored.receipt_hash, receiptHash(RECEIPT));
  assert.notEqual(stored.receipt_hash, RECEIPT);
  env.CLERK_SECRET_KEY = ''; env.CLERK_ISSUER = 'invalid-provider-configuration';
  env.DB.batch = async () => { throw new Error('Status must not write'); };
  const authenticate = async () => { throw new Error('Status must not authenticate'); };
  const fetcher = async () => { throw new Error('Status must not call providers'); };
  for (const identityDeleted of [false, true]) {
    if (identityDeleted) env.DB.db.prepare("UPDATE account_retirements SET clerk_deleted_at = '2001-01-01' WHERE user_id = ?").run(USER);
    const response = await handleAccountLifecycle(receiptRequest(), env, authenticate, { fetcher });
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.deepEqual(JSON.parse(text), { requested: true, account_data_erased: true,
      identity_deleted: identityDeleted, state: identityDeleted ? 'identity_deleted_retention_pending' : 'identity_pending',
      deletion_complete: false, retention_review_required: true });
    for (const secret of [RECEIPT, stored.receipt_hash, USER, ISSUER, '2001-01-01', 'retired_at', 'clerk']) {
      assert.equal(text.includes(secret), false, secret);
      assert.equal(JSON.stringify([...response.headers]).includes(secret), false, secret);
    }
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
    assert.equal(response.headers.get('Set-Cookie'), null);
  }
  const unknown = await handleAccountLifecycle(receiptRequest({ receipt: OTHER_RECEIPT }), env, authenticate, { fetcher });
  assert.equal(unknown.status, 404);
  assert.deepEqual(await unknown.json(), { error: 'status_unavailable' });
});

test('receipt route strictly rejects method, query, credentials, malformed tokens and deployment gates', async (t) => {
  const cases = [
    { name: 'disabled', overrides: { ACCOUNT_DELETION_ENABLED: 'false' }, status: 503, error: 'account_deletion_unavailable' },
    { name: 'nonexact flag', overrides: { ACCOUNT_DELETION_ENABLED: true }, status: 503, error: 'account_deletion_unavailable' },
    { name: 'missing limiter', overrides: { ACCOUNT_DELETION_LIMITER: null }, status: 503, error: 'account_deletion_unavailable' },
    { name: 'invalid limiter', overrides: { ACCOUNT_DELETION_LIMITER: {} }, status: 503, error: 'account_deletion_unavailable' },
    { name: 'origin', request: { origin: 'https://attacker.example' }, status: 403, error: 'origin_not_allowed' },
    { name: 'POST', request: { method: 'POST' }, status: 404, error: 'not_found' },
    { name: 'query token', request: { query: `?receipt=${RECEIPT}` }, status: 400, error: 'invalid_deletion_receipt_request' },
    { name: 'any query', request: { query: '?unrelated=1' }, status: 400, error: 'invalid_deletion_receipt_request' },
    ...['', 'Bearer expired', 'Bearer other-account'].map((authorization) => ({ name: `Authorization ${authorization}`,
      request: { headers: { Authorization: authorization } }, status: 400, error: 'invalid_deletion_receipt_request' })),
    { name: 'proxy credentials', request: { headers: { 'Proxy-Authorization': 'Bearer invalid' } },
      status: 400, error: 'invalid_deletion_receipt_request' },
    { name: 'limited', overrides: { ACCOUNT_DELETION_LIMITER: { limit: async () => ({ success: false }) } },
      status: 429, error: 'account_deletion_rate_limited' },
    { name: 'malformed limiter result', overrides: { ACCOUNT_DELETION_LIMITER: { limit: async () => ({ success: 'true' }) } },
      status: 429, error: 'account_deletion_rate_limited' },
    { name: 'absent limiter result', overrides: { ACCOUNT_DELETION_LIMITER: { limit: async () => null } },
      status: 429, error: 'account_deletion_rate_limited' },
    ...[null, '', 'a'.repeat(63), 'a'.repeat(65), 'AB'.repeat(32), 'zz'.repeat(32), `${RECEIPT}, ${OTHER_RECEIPT}`]
      .map((receipt) => ({ name: `bad token ${JSON.stringify(receipt)}`, request: { receipt }, status: 400,
        error: 'invalid_deletion_receipt' })),
  ];
  for (const entry of cases) {
    const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
    await retireSubjectData(env, USER, RECEIPT);
    Object.assign(env, entry.overrides);
    const before = env.DB.db.prepare('SELECT * FROM account_retirements').all();
    const response = await handleAccountLifecycle(receiptRequest(entry.request), env,
      async () => { throw new Error('Receipt route must not authenticate'); },
      { fetcher: async () => { throw new Error('Receipt route must not call providers'); } });
    assert.equal(response.status, entry.status, entry.name);
    assert.deepEqual(await response.json(), { error: entry.error }, entry.name);
    assert.deepEqual(env.DB.db.prepare('SELECT * FROM account_retirements').all(), before, entry.name);
    assert.equal(response.headers.get('Cache-Control'), 'no-store', entry.name);
    assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer', entry.name);
    assert.equal(response.headers.get('Set-Cookie'), null, entry.name);
  }
});

test('receipt CORS preflight permits capability header only for approved origins', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close());
  const authenticate = async () => { throw new Error('Preflight must not authenticate'); };
  const allowed = await handleAccountLifecycle(receiptRequest({ method: 'OPTIONS', receipt: null, headers: {
    'Access-Control-Request-Method': 'GET', 'Access-Control-Request-Headers': 'X-Waddle-Deletion-Receipt' } }), env, authenticate);
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), ORIGIN);
  assert.equal(allowed.headers.get('Access-Control-Allow-Credentials'), null);
  assert.ok(allowed.headers.get('Access-Control-Allow-Headers').split(', ').includes('X-Waddle-Deletion-Receipt'));
  const blocked = await handleAccountLifecycle(receiptRequest({ method: 'OPTIONS', origin: 'https://attacker.example' }), env, authenticate);
  assert.equal(blocked.status, 403); assert.equal(blocked.headers.get('Access-Control-Allow-Origin'), null);
  const disabled = await handleAccountLifecycle(receiptRequest({ method: 'OPTIONS' }),
    { ...env, ACCOUNT_DELETION_ENABLED: 'false' }, authenticate);
  assert.equal(disabled.status, 503);
});

test('rotating guessed receipts does not rotate limiter bucket or leak capabilities in keys', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close());
  const keys = [];
  env.ACCOUNT_DELETION_LIMITER = { limit: async ({ key }) => { keys.push(key); return { success: true }; } };
  for (const receipt of [RECEIPT, OTHER_RECEIPT]) {
    const response = await handleAccountLifecycle(receiptRequest({ receipt, headers: { 'CF-Connecting-IP': '192.0.2.7' } }),
      env, async () => { throw new Error('Receipt route must not authenticate'); });
    assert.equal(response.status, 404); assert.deepEqual(await response.json(), { error: 'status_unavailable' });
  }
  assert.deepEqual(keys, ['account-deletion-receipt:192.0.2.7', 'account-deletion-receipt:192.0.2.7']);
  for (const receipt of [RECEIPT, OTHER_RECEIPT, receiptHash(RECEIPT), receiptHash(OTHER_RECEIPT)]) {
    assert.equal(keys.some((key) => key.includes(receipt)), false);
  }
});

test('provider failure preserves retirement and permits truthful idempotent deletion retry', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER);
  const beforeOther = snapshot(env, OTHER);
  const authenticate = async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) });
  let providerCalls = 0;
  let deletes = 0;
  const fetcher = async (url, init) => {
    providerCalls++;
    assert.equal(url, `https://api.clerk.com/v1/users/${USER}`);
    assert.equal(await isSubjectRetired(env, USER), true, 'Durable retirement must precede provider deletion');
    for (const table of PERSONAL_TABLES) assert.equal(snapshot(env, USER)[table].length, 0);
    if (httpMethod(init) === 'GET') return new Response(JSON.stringify({ id: USER }));
    assert.equal(init.method, 'DELETE');
    assert.equal(typeof env.DB.db.prepare('SELECT clerk_identity_seen_at FROM account_retirements WHERE user_id = ?')
      .get(USER).clerk_identity_seen_at, 'string', 'Identity proof must precede destructive provider call');
    deletes++;
    return new Response(null, { status: deletes === 1 ? 503 : 404 });
  };
  const first = await handleAccountLifecycle(deletionRequest(), env, authenticate, { fetcher });
  assert.equal(first.status, 202);
  assert.deepEqual(await first.json(), { requested: true, account_data_erased: true, identity_deleted: false,
    state: 'identity_pending', deletion_complete: false, retention_review_required: true });
  const retry = await handleAccountLifecycle(deletionRequest(), env, authenticate, { fetcher });
  assert.equal(retry.status, 202);
  const completeIdentity = await retry.json();
  assert.equal(completeIdentity.identity_deleted, true);
  assert.equal(completeIdentity.state, 'identity_deleted_retention_pending');
  assert.equal(completeIdentity.deletion_complete, false);
  assert.equal(completeIdentity.retention_review_required, true);
  const third = await handleAccountLifecycle(deletionRequest(), env, authenticate, { fetcher });
  assert.equal(third.status, 202); assert.equal(providerCalls, 3);
  const status = await handleAccountLifecycle(deletionRequest({ method: 'GET', path: 'deletion' }), env, authenticate, { fetcher });
  assert.deepEqual(await status.json(), completeIdentity); assert.equal(providerCalls, 3);
  assert.deepEqual(snapshot(env, OTHER), beforeOther);
  for (const table of RETAINED_TABLES) assert.equal(snapshot(env, USER)[table].length, 1);
});

test('network failure leaves identity pending without undoing personal erasure', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const response = await handleAccountLifecycle(deletionRequest(), env,
    async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) }),
    { fetcher: async () => { throw new Error('Synthetic provider network failure'); } });
  assert.equal(response.status, 202);
  const payload = await response.json();
  assert.equal(payload.identity_deleted, false); assert.equal(payload.deletion_complete, false);
  assert.equal(await isSubjectRetired(env, USER), true);
  for (const table of PERSONAL_TABLES) assert.equal(snapshot(env, USER)[table].length, 0);
});

test('initial provider absence, mismatched identity or bad response remains pending without DELETE', async (t) => {
  for (const response of [() => new Response(null, { status: 404 }), () => new Response(null, { status: 503 }),
    () => new Response(JSON.stringify({ id: OTHER })), () => new Response('invalid JSON')]) {
    const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
    const methods = [];
    const fetcher = async (_url, init) => { methods.push(httpMethod(init)); return response(); };
    const pending = await handleAccountLifecycle(deletionRequest(), env,
      async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) }), { fetcher });
    assert.equal(pending.status, 202);
    const payload = await pending.json();
    assert.equal(payload.identity_deleted, false); assert.equal(payload.state, 'identity_pending');
    assert.equal(payload.deletion_complete, false);
    const row = env.DB.db.prepare('SELECT clerk_identity_seen_at, clerk_deleted_at FROM account_retirements WHERE user_id = ?').get(USER);
    assert.equal(row.clerk_identity_seen_at, null); assert.equal(row.clerk_deleted_at, null);
    assert.deepEqual(await retryPendingIdentityDeletions(env, { fetcher }),
      { attempted: 1, identity_deleted: 0, pending: 1, deletion_complete: false });
    assert.deepEqual(methods, ['GET', 'GET']);
    assert.equal(await isSubjectRetired(env, USER), true);
    for (const table of PERSONAL_TABLES) assert.equal(snapshot(env, USER)[table].length, 0);
  }
});

test('first matching GET records identity proof before DELETE404 is accepted', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const methods = [];
  const fetcher = async (_url, init) => {
    methods.push(httpMethod(init));
    if (httpMethod(init) === 'GET') return new Response(JSON.stringify({ id: USER }));
    assert.equal(typeof env.DB.db.prepare('SELECT clerk_identity_seen_at FROM account_retirements WHERE user_id = ?')
      .get(USER).clerk_identity_seen_at, 'string');
    return new Response(null, { status: 404 });
  };
  const response = await handleAccountLifecycle(deletionRequest(), env,
    async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) }), { fetcher });
  assert.equal(response.status, 202);
  const payload = await response.json();
  assert.equal(payload.identity_deleted, true); assert.equal(payload.deletion_complete, false);
  assert.deepEqual(methods, ['GET', 'DELETE']);
});

test('lost DELETE reply after identity proof retries safely through provider404 without client JWT', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const methods = [];
  const response = await handleAccountLifecycle(deletionRequest(), env,
    async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) }), { fetcher: async (_url, init) => {
      methods.push(httpMethod(init));
      if (httpMethod(init) === 'GET') return new Response(JSON.stringify({ id: USER }));
      throw new DOMException('Synthetic lost provider reply', 'AbortError');
    } });
  assert.equal(response.status, 202); assert.equal((await response.json()).identity_deleted, false);
  const row = env.DB.db.prepare('SELECT clerk_identity_seen_at, clerk_deleted_at FROM account_retirements WHERE user_id = ?').get(USER);
  assert.equal(typeof row.clerk_identity_seen_at, 'string'); assert.equal(row.clerk_deleted_at, null);
  const fetcher = async (_url, init) => { methods.push(httpMethod(init)); return new Response(null, { status: 404 }); };
  assert.deepEqual(await retryPendingIdentityDeletions(env, { fetcher }),
    { attempted: 1, identity_deleted: 1, pending: 0, deletion_complete: false });
  assert.deepEqual(await retryPendingIdentityDeletions(env, { fetcher }),
    { attempted: 0, identity_deleted: 0, pending: 0, deletion_complete: false });
  assert.deepEqual(methods, ['GET', 'DELETE', 'DELETE']);
});

test('rotated synthetic Clerk key requires new identity proof and GET404 cannot complete deletion', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  await handleAccountLifecycle(deletionRequest(), env,
    async () => ({ sub: USER, iat: Math.floor(Date.now() / 1000) }), { fetcher: async (_url, init) => {
      if (httpMethod(init) === 'GET') return new Response(JSON.stringify({ id: USER }));
      return new Response(null, { status: 503 });
    } });
  env.CLERK_SECRET_KEY = 'synthetic-rotated-fixture-secret';
  const methods = [];
  const result = await retryPendingIdentityDeletions(env,
    { fetcher: async (_url, init) => { methods.push(httpMethod(init)); return new Response(null, { status: 404 }); } });
  assert.deepEqual(result, { attempted: 1, identity_deleted: 0, pending: 1, deletion_complete: false });
  assert.deepEqual(methods, ['GET']);
  assert.equal(env.DB.db.prepare('SELECT clerk_deleted_at FROM account_retirements WHERE user_id = ?').get(USER).clerk_deleted_at, null);
  assert.equal(await isSubjectRetired(env, USER), true);
});

test('bounded retry queue persists failures, completes oldest pending identities, and needs no client token', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER);
  await retireSubjectData(env, USER); await retireSubjectData(env, OTHER);
  env.DB.db.prepare('UPDATE account_retirements SET retired_at = ? WHERE user_id = ?').run('2000-01-01 00:00:00', USER);
  env.DB.db.prepare('UPDATE account_retirements SET retired_at = ? WHERE user_id = ?').run('2001-01-01 00:00:00', OTHER);
  const calls = [];
  let deletes = 0;
  const fetcher = async (url, init) => {
    calls.push(`${httpMethod(init)} ${url}`);
    if (httpMethod(init) === 'GET') return new Response(JSON.stringify({ id: String(url).split('/').pop() }));
    assert.equal(init.method, 'DELETE'); deletes++;
    return new Response(null, { status: deletes === 1 ? 503 : 404 });
  };
  assert.deepEqual(await retryPendingIdentityDeletions(env, { fetcher, limit: 1 }),
    { attempted: 1, identity_deleted: 0, pending: 1, deletion_complete: false });
  assert.equal(env.DB.db.prepare('SELECT clerk_deleted_at FROM account_retirements WHERE user_id = ?').get(USER).clerk_deleted_at, null);
  assert.deepEqual(await retryPendingIdentityDeletions(env, { fetcher, limit: 1 }),
    { attempted: 1, identity_deleted: 1, pending: 0, deletion_complete: false });
  assert.deepEqual(await retryPendingIdentityDeletions(env, { fetcher, limit: 5 }),
    { attempted: 1, identity_deleted: 1, pending: 0, deletion_complete: false });
  assert.deepEqual(await retryPendingIdentityDeletions(env, { fetcher }),
    { attempted: 0, identity_deleted: 0, pending: 0, deletion_complete: false });
  assert.deepEqual(calls, [`GET https://api.clerk.com/v1/users/${USER}`, `DELETE https://api.clerk.com/v1/users/${USER}`,
    `DELETE https://api.clerk.com/v1/users/${USER}`, `GET https://api.clerk.com/v1/users/${OTHER}`,
    `DELETE https://api.clerk.com/v1/users/${OTHER}`]);
  for (const user of [USER, OTHER]) {
    assert.equal(await isSubjectRetired(env, user), true);
    for (const table of PERSONAL_TABLES) assert.equal(snapshot(env, user)[table].length, 0);
  }
});

test('retry queue rejects disabled configuration and out-of-range limits without provider calls', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); markRetired(env);
  let calls = 0;
  const fetcher = async () => { calls++; throw new Error('Provider must not run'); };
  for (const override of [{ ACCOUNT_DELETION_ENABLED: 'false' }, { CLERK_SECRET_KEY: '' }]) {
    await assert.rejects(retryPendingIdentityDeletions({ ...env, ...override }, { fetcher }),
      (error) => error.code === 'account_deletion_unavailable' && error.status === 503);
  }
  for (const limit of [0, 6, 1.5, Infinity, '1']) {
    await assert.rejects(retryPendingIdentityDeletions(env, { fetcher, limit }),
      (error) => error.code === 'invalid_retry_limit' && error.status === 400);
  }
  assert.equal(calls, 0);
  assert.equal(env.DB.db.prepare('SELECT clerk_deleted_at FROM account_retirements WHERE user_id = ?').get(USER).clerk_deleted_at, null);
});

test('actual worker deletion verifies signed JWT, completes identity once, and permits raw-auth retry', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const token = await signedToken(USER);
  const previousFetch = globalThis.fetch;
  let identityCalls = 0;
  globalThis.fetch = async (url, init) => {
    if (String(url) === `${ISSUER}/.well-known/jwks.json`) return new Response(JSON.stringify({ keys: [jwk] }));
    assert.equal(String(url), `https://api.clerk.com/v1/users/${USER}`);
    assert.equal(await isSubjectRetired(env, USER), true);
    if (httpMethod(init) === 'GET') return new Response(JSON.stringify({ id: USER }));
    assert.equal(init.method, 'DELETE');
    identityCalls++;
    return new Response(null, { status: 204 });
  };
  t.after(() => { globalThis.fetch = previousFetch; });
  const first = await worker.fetch(deletionRequest({ token }), env);
  assert.equal(first.status, 202);
  const payload = await first.json();
  assert.equal(payload.identity_deleted, true); assert.equal(payload.deletion_complete, false);
  const retry = await worker.fetch(deletionRequest({ token }), env);
  assert.equal(retry.status, 202); assert.equal(identityCalls, 1);
  assert.deepEqual(await retry.json(), payload);
});

test('lost client deletion reply recovers status after JWT expires without any authentication or provider fetch', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const freshToken = await signedToken(USER);
  const expiredToken = await signedToken(USER, { exp: Math.floor(Date.now() / 1000) - 600 });
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    if (String(url) === `${ISSUER}/.well-known/jwks.json`) return new Response(JSON.stringify({ keys: [jwk] }));
    assert.equal(String(url), `https://api.clerk.com/v1/users/${USER}`);
    if (httpMethod(init) === 'GET') return new Response(JSON.stringify({ id: USER }));
    throw new DOMException('Synthetic lost provider reply', 'AbortError');
  };
  t.after(() => { globalThis.fetch = previousFetch; });
  // The client never receives this response, but its token was persisted before
  // dispatch. Durable receipt/retirement/erasure already committed together.
  await worker.fetch(deletionRequest({ token: freshToken }), env);
  assert.equal(await isSubjectRetired(env, USER), true);
  globalThis.fetch = async () => { throw new Error('Recovery must not fetch JWT keys or providers'); };
  const expired = await worker.fetch(deletionRequest({ method: 'GET', path: 'deletion', token: expiredToken }), env);
  assert.equal(expired.status, 401);
  const recovered = await worker.fetch(receiptRequest(), env);
  assert.equal(recovered.status, 200);
  assert.deepEqual(await recovered.json(), { requested: true, account_data_erased: true, identity_deleted: false,
    state: 'identity_pending', deletion_complete: false, retention_review_required: true });
  const guessed = await worker.fetch(receiptRequest({ receipt: OTHER_RECEIPT }), env);
  assert.equal(guessed.status, 404); assert.deepEqual(await guessed.json(), { error: 'status_unavailable' });
  const wrongAccount = await worker.fetch(receiptRequest({ headers: { Authorization: `Bearer ${await signedToken(OTHER)}` } }), env);
  assert.equal(wrongAccount.status, 400);
  assert.deepEqual(await wrongAccount.json(), { error: 'invalid_deletion_receipt_request' });
});

test('authenticated deletion status retains authoritative requested:false for active account', async (t) => {
  const env = enableDeletion(environment()); t.after(() => env.DB.db.close()); seed(env);
  const response = await handleAccountLifecycle(deletionRequest({ method: 'GET', path: 'deletion' }), env,
    async () => ({ sub: USER }), { fetcher: async () => { throw new Error('Status must not call providers'); } });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { requested: false, deletion_complete: false });
  assert.equal(await isSubjectRetired(env, USER), false);
});

test('valid old Clerk JWT cannot read or recreate personal data, store binding or entitlements', async (t) => {
  const env = environment(); t.after(() => env.DB.db.close()); seed(env); seed(env, OTHER);
  const token = await signedToken(USER);
  const otherToken = await signedToken(OTHER);
  const previousFetch = globalThis.fetch;
  const unexpected = [];
  globalThis.fetch = async (url) => {
    if (String(url) === `${ISSUER}/.well-known/jwks.json`) return new Response(JSON.stringify({ keys: [jwk] }));
    unexpected.push(String(url)); throw new Error('Retired route must not call providers');
  };
  t.after(() => { globalThis.fetch = previousFetch; });
  await retireSubjectData(env, USER);
  for (const [path, method, body] of [
    ['/api/save', 'GET'], ['/api/save', 'PUT', '{"fish":999}'],
    ['/api/profile', 'POST', '{"name":"Resurrected"}'],
    ['/api/scores', 'POST', '{"mode":"time","course":"glacier","value":15000,"name":"Resurrected"}'],
    ['/api/commerce/account', 'GET'], ['/api/commerce/entitlements', 'GET'],
  ]) {
    const response = await worker.fetch(new Request(`${ORIGIN}${path}`, { method,
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, ...(body ? { body } : {}) }), env);
    assert.equal(response.status, 403, `${method} ${path}`);
    assert.equal((await response.json()).error, 'account_retired', `${method} ${path}`);
  }
  const active = await worker.fetch(new Request(`${ORIGIN}/api/save`, { headers: { Authorization: `Bearer ${otherToken}` } }), env);
  assert.equal(active.status, 200); assert.equal((await active.json()).exists, true);
  for (const table of PERSONAL_TABLES) assert.equal(snapshot(env, USER)[table].length, 0);
  assert.deepEqual(unexpected, []);
});
