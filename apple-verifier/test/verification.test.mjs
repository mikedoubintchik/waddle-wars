import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, X509Certificate } from 'node:crypto';
import { SignedDataVerifier, Environment, VerificationException, VerificationStatus }
  from '@apple/app-store-server-library';
import { configuration, createHandler } from '../src/verification.mjs';

const bundleId = 'com.blubberandbyte.waddlewars';
const transactionId = '123456789012345';
const env = { APPLE_VERIFIER_ENABLED: 'true', COMMERCE_MODE: 'test',
  APPLE_BUNDLE_ID: bundleId, APPLE_KEY_ID: 'ABCDEFGHIJ',
  APPLE_ISSUER_ID: '93c6a0b4-3600-4dfe-9bda-e62e15b2df76',
  APPLE_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\nfixture only\n-----END PRIVATE KEY-----' };

function request(body = { transaction_id: transactionId }, extra = {}) {
  return new Request('https://apple-verifier.internal/verify', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body), ...extra,
  });
}

function fixture(change = {}) {
  const calls = [];
  const transaction = { transactionId, bundleId, environment: Environment.SANDBOX,
    productId: `${bundleId}.cozy_expedition`, type: 'Non-Consumable', quantity: 1,
    ...change };
  const handler = createHandler(() => ({
    config: { bundleId, environment: Environment.SANDBOX },
    api: { async getTransactionInfo(id) { calls.push(['fetch', id]);
      return { signedTransactionInfo: 'authoritative-apple-jws' }; } },
    verifier: { async verifyAndDecodeTransaction(jws) {
      calls.push(['verify', jws]); return transaction; } },
  }));
  return { handler, calls, transaction };
}

test('configuration rejects missing credentials, arbitrary app and mixed environments', () => {
  assert.equal(configuration(env).environment, Environment.SANDBOX);
  for (const change of [{ APPLE_VERIFIER_ENABLED: 'false' }, { COMMERCE_MODE: 'development' },
    { APPLE_BUNDLE_ID: 'other.app' }, { APPLE_KEY_ID: '' }, { APPLE_ISSUER_ID: '' },
    { APPLE_PRIVATE_KEY: '' }, { COMMERCE_MODE: 'live' },
    { COMMERCE_MODE: 'live', APPLE_APP_ID: '0' }]) {
    assert.throws(() => configuration({ ...env, ...change }), /verifier_unavailable/);
  }
  assert.equal(configuration({ ...env, COMMERCE_MODE: 'live', APPLE_APP_ID: '123456' }).appAppleId, 123456);
});

test('fetches transaction from Apple and verifies JWS before returning success', async () => {
  const f = fixture();
  const result = await f.handler(request(), env);
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { verified: true, transaction: f.transaction });
  assert.deepEqual(f.calls, [['fetch', transactionId], ['verify', 'authoritative-apple-jws']]);
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.equal(result.headers.get('access-control-allow-origin'), null);
});

test('never accepts client success flags, signed payloads or oversized request bodies', async () => {
  const f = fixture();
  for (const body of [{ transaction_id: transactionId, verified: true },
    { transaction_id: transactionId, signedTransactionInfo: 'forged' }, {}, [],
    { transaction_id: 123456789 }, { transaction_id: '../other' }]) {
    assert.equal((await f.handler(request(body), env)).status, 400);
  }
  assert.equal((await f.handler(request({ transaction_id: '1'.repeat(3000) }), env)).status, 413);
  assert.deepEqual(f.calls, []);
});

test('bounds streamed bodies even when Content-Length is absent or false', async () => {
  const f = fixture();
  const stream = new ReadableStream({ start(controller) {
    controller.enqueue(new Uint8Array(2049)); controller.close();
  } });
  const result = await f.handler(request(undefined, { body: stream, duplex: 'half' }), env);
  assert.equal(result.status, 413);
  assert.deepEqual(f.calls, []);
});

test('private routing and browser origins rejected before verification', async () => {
  const f = fixture();
  assert.equal((await f.handler(new Request('https://public.example/verify'), env)).status, 404);
  assert.equal((await f.handler(new Request('https://apple-verifier.internal/verify'), env)).status, 405);
  assert.equal((await f.handler(request(undefined, { headers: {
    'Content-Type': 'application/json', Origin: 'https://game.example' } }), env)).status, 403);
  assert.deepEqual(f.calls, []);
});

test('verified transaction still must match requested ID, app and environment', async () => {
  for (const change of [{ transactionId: '999999999' }, { bundleId: 'another.app' },
    { environment: Environment.PRODUCTION }]) {
    const f = fixture(change);
    assert.equal((await f.handler(request(), env)).status, 400);
  }
});

test('provider and signature failures cannot leak credentials or receipt contents', async () => {
  const failFetch = createHandler(() => ({ api: { async getTransactionInfo() {
    throw new Error('private-key-and-receipt');
  } } }));
  const result = await failFetch(request(), env);
  assert.equal(result.status, 503);
  assert.deepEqual(await result.json(), { error: 'verifier_unavailable' });
  const failVerification = createHandler(() => ({
    api: { async getTransactionInfo() { return { signedTransactionInfo: 'forged' }; } },
    verifier: { async verifyAndDecodeTransaction() { throw new Error('invalid-signature'); } },
  }));
  const unverified = await failVerification(request(), env);
  assert.equal(unverified.status, 400);
  assert.deepEqual(await unverified.json(), { error: 'unverified_transaction' });
});

test('bundled trust anchors are self-signed Apple roots and actual verifier rejects forged JWS', async () => {
  const roots = ['AppleIncRootCertificate.cer', 'AppleRootCA-G2.cer', 'AppleRootCA-G3.cer']
    .map((name) => readFileSync(new URL(`../certificates/${name}`, import.meta.url)));
  for (const root of roots) {
    const cert = new X509Certificate(root);
    assert.equal(cert.ca, true);
    assert.match(cert.subject, /Apple/);
    assert.equal(cert.subject, cert.issuer);
    assert.equal(cert.verify(cert.publicKey), true);
    assert.equal(createHash('sha256').update(root).digest('hex').length, 64);
  }
  const verifier = new SignedDataVerifier(roots, true, Environment.SANDBOX, bundleId);
  const fake = [Buffer.from(JSON.stringify({ alg: 'ES256', x5c: [] })).toString('base64url'),
    Buffer.from(JSON.stringify({ transactionId, bundleId, environment: 'Sandbox' })).toString('base64url'),
    Buffer.alloc(64).toString('base64url')].join('.');
  await assert.rejects(verifier.verifyAndDecodeTransaction(fake));
});

test('notifications verify outer and nested signatures before reconciliation', async () => {
  const calls = [];
  const transaction = { bundleId, environment: Environment.SANDBOX, transactionId };
  const notification = { notificationUUID: 'fixture', notificationType: 'REFUND',
    data: { signedTransactionInfo: 'nested-signed-data' } };
  const handler = createHandler(() => ({ config: { bundleId, environment: Environment.SANDBOX },
    verifier: {
      async verifyAndDecodeNotification(value) { calls.push(value); return notification; },
      async verifyAndDecodeTransaction(value) { calls.push(value); return transaction; },
    },
  }));
  const result = await handler(new Request('https://apple-verifier.internal/notification', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ signed_payload: 'outer-signed-data' }),
  }), env);
  assert.deepEqual(await result.json(), { verified: true, notification, transaction });
  assert.deepEqual(calls, ['outer-signed-data', 'nested-signed-data']);
});

test('temporary certificate status failure is retryable and never grants ownership', async () => {
  const handler = createHandler(() => ({
    api: { async getTransactionInfo() { return { signedTransactionInfo: 'signed-data' }; } },
    verifier: { async verifyAndDecodeTransaction() {
      throw new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE);
    } },
  }));
  const result = await handler(request(), env);
  assert.equal(result.status, 503);
  assert.deepEqual(await result.json(), { error: 'verifier_unavailable' });
});
