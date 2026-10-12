import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { handleCommerce, persistNativePurchase } from '../leaderboard/src/commerce.mjs';
import { accountBinding, sha256 } from '../leaderboard/src/commerce_providers.mjs';
import { verifyGooglePush } from '../leaderboard/src/commerce_notifications.mjs';
import { PRODUCTS } from '../leaderboard/src/commerce_catalog.mjs';

class D1 {
  constructor() {
    this.db = new DatabaseSync(':memory:');
    this.db.exec(readFileSync(new URL('../leaderboard/schema.sql', import.meta.url), 'utf8'));
    for (const name of readdirSync(new URL('../leaderboard/migrations/', import.meta.url)).filter((name) => name.endsWith('.sql')).sort()) {
      this.db.exec(readFileSync(new URL(`../leaderboard/migrations/${name}`, import.meta.url), 'utf8'));
    }
  }
  prepare(sql) {
    const db = this.db;
    const make = (values = []) => {
      const statement = db.prepare(sql); statement.setAllowUnknownNamedParameters(true);
      const args = Object.fromEntries(values.map((value, index) => [String(index + 1), value]));
      return { bind: (...values) => make(values), first: async () => statement.get(args) || null,
        all: async () => ({ results: statement.all(args) }), run: async () => statement.run(args) };
    }; return make();
  }
  async batch(statements) {
    this.db.exec('BEGIN'); try { for (const statement of statements) await statement.run(); this.db.exec('COMMIT'); }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
}

const packageId = 'com.blubberandbyte.waddlewars';
const product = PRODUCTS[0];
const transactionId = '2000000000000000';
const audience = 'https://worker.example/api/commerce/google/notifications';
const serviceEmail = 'rtdn@example.iam.gserviceaccount.com';
const subscription = 'projects/test-project/subscriptions/waddle-rtdn';
const authenticate = async () => ({ sub: 'player-one' });
const json = (data) => new Response(JSON.stringify(data));

function environment(extra = {}) {
  return { DB: new D1(), COMMERCE_ENABLED: 'true', COMMERCE_MODE: 'test', APPLE_BUNDLE_ID: packageId,
    GOOGLE_PLAY_PACKAGE_ID: packageId, GOOGLE_RTDN_AUDIENCE: audience,
    GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL: serviceEmail, GOOGLE_RTDN_SUBSCRIPTION: subscription, ...extra };
}

async function appleFixture(env) {
  const binding = await accountBinding('player-one');
  const transaction = { transactionId, originalTransactionId: transactionId, bundleId: packageId,
    productId: product.apple_product_id, appAccountToken: binding.apple, quantity: 1, type: 'Non-Consumable', environment: 'Sandbox', signedDate: Date.now() - 1000 };
  const fixture = { transaction, eventId: 'notification-fixture', notificationType: 'REFUND',
    notificationTransaction: null, beforeVerify: null,
    verifierAvailable: true, verified: true, calls: [], fetch: async (req) => {
      fixture.calls.push(new URL(req.url).pathname);
      if (!fixture.verifierAvailable) return new Response('', { status: 503 });
      if (new URL(req.url).pathname === '/notification') return json({ verified: fixture.verified,
        notification: { notificationUUID: fixture.eventId, notificationType: fixture.notificationType },
        transaction: fixture.notificationTransaction || fixture.transaction });
      const snapshot = structuredClone(fixture.transaction);
      if (fixture.beforeVerify) await fixture.beforeVerify(snapshot);
      return json({ verified: fixture.verified, transaction: snapshot });
    } };
  env.APPLE_RECEIPT_VERIFIER = fixture;
  await env.DB.prepare('INSERT INTO commerce_store_accounts(user_id, apple_account_token, google_account_id) VALUES (?1, ?2, ?3)')
    .bind('player-one', binding.apple, binding.google).run();
  return fixture;
}

const appleRequest = () => new Request('https://worker.example/api/commerce/apple/notifications', {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ signedPayload: 'provider-jws-fixture' }),
});

test('Apple verified notification revokes earned-independent purchase and deduplicates event', async () => {
  const env = environment(); const fixture = await appleFixture(env);
  await persistNativePurchase(env, { provider: 'apple', transaction_id: transactionId, user_id: 'player-one',
    product_id: product.id, payment_reference: transactionId, state: 'active' });
  fixture.transaction.revocationDate = Date.now();
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_revocations').get().n, 1);
  const result = await (await handleCommerce(appleRequest(), env, authenticate)).json();
  assert.equal(result.duplicate, true);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_events').get().n, 1);
});

test('Apple refund-before-client grant persists terminal tombstone', async () => {
  const env = environment(); const fixture = await appleFixture(env);
  fixture.transaction.revocationDate = Date.now();
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  assert.equal(await persistNativePurchase(env, { provider: 'apple', transaction_id: transactionId,
    user_id: 'player-one', product_id: product.id, payment_reference: transactionId, state: 'active' }), 'refunded');
});

test('Apple REFUND_REVERSED restores only fresh verified same-account purchase; normal client replay cannot', async () => {
  const env = environment(); const fixture = await appleFixture(env);
  fixture.transaction.revocationDate = fixture.transaction.signedDate;
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  delete fixture.transaction.revocationDate;
  fixture.transaction.signedDate += 100;
  const active = { provider: 'apple', transaction_id: transactionId, user_id: 'player-one',
    product_id: product.id, payment_reference: transactionId, state: 'active', provider_signed_at: fixture.transaction.signedDate };
  assert.equal(await persistNativePurchase(env, active), 'refunded');
  fixture.eventId = 'verified-reversal'; fixture.notificationType = 'REFUND_REVERSED';
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active');
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_revocations').get().n, 0);
  assert.equal((await (await handleCommerce(appleRequest(), env, authenticate)).json()).duplicate, true);
});

test('old reversal cannot resurrect a newer refund, even with delayed concurrent authoritative response', async () => {
  const env = environment(); const fixture = await appleFixture(env);
  const firstTime = Date.now() - 10000;
  fixture.transaction.signedDate = firstTime;
  fixture.transaction.revocationDate = firstTime;
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);

  delete fixture.transaction.revocationDate; fixture.transaction.signedDate = firstTime + 100;
  fixture.eventId = 'old-reversal'; fixture.notificationType = 'REFUND_REVERSED';
  let release; let captured;
  const capture = new Promise((resolve) => { captured = resolve; });
  const hold = new Promise((resolve) => { release = resolve; });
  fixture.beforeVerify = async (snapshot) => { if (snapshot.signedDate === firstTime + 100) { captured(); await hold; } };
  const delayed = handleCommerce(appleRequest(), env, authenticate);
  await capture;
  fixture.transaction.signedDate = firstTime + 200; fixture.transaction.revocationDate = firstTime + 200;
  fixture.eventId = 'later-refund'; fixture.notificationType = 'REFUND';
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  release(); assert.equal((await delayed).status, 200);
  assert.equal(env.DB.db.prepare('SELECT state, provider_signed_at FROM commerce_purchases').get().state, 'refunded');
  assert.equal(env.DB.db.prepare('SELECT provider_signed_at FROM commerce_revocations').get().provider_signed_at, firstTime + 200);
  fixture.eventId = 'old-reversal'; fixture.notificationType = 'REFUND_REVERSED';
  assert.equal((await (await handleCommerce(appleRequest(), env, authenticate)).json()).duplicate, true);
  fixture.eventId = 'another-old-reversal';
  fixture.notificationTransaction = { ...fixture.transaction, signedDate: firstTime + 100 };
  delete fixture.notificationTransaction.revocationDate;
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
});

test('stale refund delivery after valid reversal does not revoke current purchase; equal-time refund wins', async () => {
  const env = environment(); const fixture = await appleFixture(env);
  const firstTime = fixture.transaction.signedDate;
  fixture.transaction.revocationDate = firstTime;
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  const oldRefund = structuredClone(fixture.transaction);
  delete fixture.transaction.revocationDate; fixture.transaction.signedDate += 100;
  fixture.eventId = 'restore'; fixture.notificationType = 'REFUND_REVERSED';
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  fixture.notificationTransaction = oldRefund; fixture.eventId = 'delayed-old-refund'; fixture.notificationType = 'REFUND';
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active');
  fixture.notificationTransaction = null; fixture.transaction.revocationDate = firstTime + 100;
  fixture.eventId = 'equal-time-refund';
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  delete fixture.transaction.revocationDate; fixture.eventId = 'equal-time-reversal'; fixture.notificationType = 'REFUND_REVERSED';
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
});

test('newer refund learned from client verification advances watermark despite older notification tombstone', async () => {
  const env = environment(); const fixture = await appleFixture(env);
  const firstTime = Date.now() - 10000;
  fixture.transaction.signedDate = firstTime; fixture.transaction.revocationDate = firstTime;
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  await persistNativePurchase(env, { provider: 'apple', transaction_id: transactionId, user_id: 'player-one',
    product_id: product.id, payment_reference: transactionId, state: 'refunded', provider_signed_at: firstTime + 200 });
  assert.equal(env.DB.db.prepare('SELECT provider_signed_at FROM commerce_purchases').get().provider_signed_at, firstTime + 200);
  delete fixture.transaction.revocationDate; fixture.transaction.signedDate = firstTime + 100;
  fixture.eventId = 'intermediate-stale-reversal'; fixture.notificationType = 'REFUND_REVERSED';
  assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_revocations').get().n, 1);
});

test('Apple reversal rejects account/original-transaction mismatch and retries provider snapshot older than notification', async () => {
  for (const change of [(transaction) => { transaction.appAccountToken = 'wrong-account'; },
    (transaction) => { transaction.originalTransactionId = '2000000000000099'; },
    (transaction) => { transaction.signedDate -= 100; }]) {
    const env = environment(); const fixture = await appleFixture(env);
    await persistNativePurchase(env, { provider: 'apple', transaction_id: transactionId, user_id: 'player-one',
      product_id: product.id, payment_reference: transactionId, state: 'active', provider_signed_at: fixture.transaction.signedDate });
    fixture.transaction.revocationDate = fixture.transaction.signedDate;
    assert.equal((await handleCommerce(appleRequest(), env, authenticate)).status, 200);
    delete fixture.transaction.revocationDate; fixture.transaction.signedDate += 100;
    fixture.eventId = 'invalid-reversal'; fixture.notificationType = 'REFUND_REVERSED';
    fixture.notificationTransaction = structuredClone(fixture.transaction);
    change(fixture.transaction);
    assert.ok((await handleCommerce(appleRequest(), env, authenticate)).status >= 400);
    assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_events WHERE event_id = ?').get('invalid-reversal').n, 0);
  }
});

test('invalid Apple chain, provider failure, wrong app and product never revoke or fulfill', async () => {
  for (const mutation of [(f) => { f.verified = false; }, (f) => { f.verifierAvailable = false; },
    (f) => { f.transaction.bundleId = 'another.app'; }, (f) => { f.transaction.productId = 'another.product'; }]) {
    const env = environment(); const fixture = await appleFixture(env); mutation(fixture);
    assert.ok((await handleCommerce(appleRequest(), env, authenticate)).status >= 400);
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_revocations').get().n, 0);
  }
});

async function googleSigner() {
  const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const jwk = { ...(await crypto.subtle.exportKey('jwk', key.publicKey)), kid: 'test-key' };
  const claims = { iss: 'https://accounts.google.com', aud: audience, email: serviceEmail, email_verified: true,
    sub: 'test-service-account', iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 600 };
  const sign = async (overrides = {}) => {
    const header = Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'test-key' })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ ...claims, ...overrides })).toString('base64url');
    const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key.privateKey, new TextEncoder().encode(`${header}.${payload}`));
    return `${header}.${payload}.${Buffer.from(signature).toString('base64url')}`;
  };
  return { sign, key, fetcher: async (url) => {
    assert.equal(url, 'https://www.googleapis.com/oauth2/v3/certs'); return json({ keys: [jwk] });
  } };
}

function googleRequest(token, notification, extra = {}, messageId = '10001') {
  return new Request(audience, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ subscription, message: { messageId, data: Buffer.from(JSON.stringify({
      packageName: packageId, ...notification })).toString('base64') }, ...extra }) });
}

test('Pub/Sub verifies RSA signature, issuer, audience, exact service account, email verification and expiry', async () => {
  const env = environment(); const signer = await googleSigner();
  await verifyGooglePush(env, googleRequest(await signer.sign(), {}), signer.fetcher);
  for (const claim of [{ aud: 'another-audience' }, { email: 'attacker@example.invalid' }, { email_verified: false },
    { iss: 'https://attacker.example' }, { exp: 1 }, { iat: Math.floor(Date.now() / 1000) + 60 }]) {
    await assert.rejects(verifyGooglePush(env, googleRequest(await signer.sign(claim), {}), signer.fetcher), /unauthorized_notification/);
  }
  const valid = await signer.sign();
  for (const malformed of [`${valid}.`, `${valid}..ignored`, valid.replace(/\.([^.]+)$/, '..$1')]) {
    await assert.rejects(verifyGooglePush(env, googleRequest(malformed, {}), signer.fetcher), /unauthorized_notification/);
  }
  await assert.rejects(verifyGooglePush(env, googleRequest(`${valid.slice(0, -20)}${'a'.repeat(20)}`, {}), signer.fetcher), /unauthorized_notification/);
});

test('authenticated full one-time void event revokes and blocks later client grant; wrong subscription/package blocked', async () => {
  const env = environment(); const signer = await googleSigner(); const jwt = await signer.sign();
  const notice = { voidedPurchaseNotification: { purchaseToken: 'purchase-token-fixture', productType: 2, refundType: 1 } };
  assert.equal((await handleCommerce(googleRequest(jwt, notice, { subscription: 'projects/other/subscriptions/attack' }), env, authenticate, signer)).status, 400);
  assert.equal((await handleCommerce(googleRequest(jwt, { ...notice, packageName: 'another.app' }), env, authenticate, signer)).status, 400);
  assert.equal((await handleCommerce(googleRequest(jwt, notice), env, authenticate, signer)).status, 200);
  const hash = await sha256('purchase-token-fixture');
  assert.equal(await persistNativePurchase(env, { provider: 'google', transaction_id: hash,
    user_id: 'player-one', product_id: product.id, payment_reference: 'GPA.fixture', state: 'active' }), 'refunded');
  assert.equal((await (await handleCommerce(googleRequest(jwt, notice), env, authenticate, signer)).json()).duplicate, true);
});

test('authenticated pending Google notification retries; paid notice grants once and acknowledges only after durable ledger write', async () => {
  const env = environment(); const signer = await googleSigner(); const jwt = await signer.sign();
  const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey('pkcs8', signer.key.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----`;
  env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON = JSON.stringify({ client_email: serviceEmail, private_key: pem });
  const binding = await accountBinding('player-one');
  await env.DB.prepare('INSERT INTO commerce_store_accounts(user_id, apple_account_token, google_account_id) VALUES (?1, ?2, ?3)')
    .bind('player-one', binding.apple, binding.google).run();
  const purchase = { obfuscatedExternalAccountId: binding.google, purchaseStateContext: { purchaseState: 'PENDING' },
    productLineItem: [{ productId: product.google_product_id, productOfferDetails: { quantity: 1, refundableQuantity: 1 } }],
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING', orderId: 'GPA.fixture',
    testPurchaseContext: { fopType: 'TEST' } };
  let queries = 0; let acknowledgments = 0;
  const fetcher = async (url, init) => {
    if (url === 'https://www.googleapis.com/oauth2/v3/certs') return signer.fetcher(url);
    if (url === 'https://oauth2.googleapis.com/token') {
      const [header, payload, signature] = init.body.get('assertion').split('.');
      assert.equal(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', signer.key.publicKey,
        Buffer.from(signature, 'base64url'), new TextEncoder().encode(`${header}.${payload}`)), true);
      return json({ access_token: 'provider-test-token' });
    }
    assert.equal(init.headers.Authorization, 'Bearer provider-test-token');
    if (url.endsWith(':acknowledge')) {
      assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active');
      acknowledgments += 1; return new Response(null, { status: 204 });
    }
    assert.ok(url.includes(`/applications/${packageId}/purchases/productsv2/tokens/`));
    queries += 1; return json(purchase);
  };
  const notice = { oneTimeProductNotification: { notificationType: 1, sku: product.google_product_id, purchaseToken: 'pending-then-paid-token' } };
  assert.equal((await handleCommerce(googleRequest(jwt, notice), env, authenticate, { fetcher })).status, 409);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_events').get().n, 0);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
  purchase.purchaseStateContext.purchaseState = 'PURCHASED';
  assert.equal((await handleCommerce(googleRequest(jwt, notice), env, authenticate, { fetcher })).status, 200);
  assert.equal(acknowledgments, 1);
  const beforeReplay = queries;
  assert.equal((await (await handleCommerce(googleRequest(jwt, notice), env, authenticate, { fetcher })).json()).duplicate, true);
  assert.equal(queries, beforeReplay);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 1);
});

test('mixed Google RTDN delivery rejects opposite-mode grants without consuming retry; probes and full voids stay routed', async () => {
  const signer = await googleSigner(); const jwt = await signer.sign();
  const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey('pkcs8', signer.key.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----`;
  const binding = await accountBinding('player-one');
  for (const mode of ['test', 'live']) {
    const env = environment({ COMMERCE_MODE: mode,
      GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: serviceEmail, private_key: pem }) });
    await env.DB.prepare('INSERT INTO commerce_store_accounts(user_id, apple_account_token, google_account_id) VALUES (?1, ?2, ?3)')
      .bind('player-one', binding.apple, binding.google).run();
    const purchase = { obfuscatedExternalAccountId: binding.google, purchaseStateContext: { purchaseState: 'PURCHASED' },
      productLineItem: [{ productId: product.google_product_id, productOfferDetails: { quantity: 1, refundableQuantity: 1 } }],
      acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING', orderId: 'GPA.fixture' };
    if (mode === 'live') purchase.testPurchaseContext = { fopType: 'TEST' };
    let acknowledgments = 0;
    const fetcher = async (url, init) => {
      if (url === 'https://www.googleapis.com/oauth2/v3/certs') return signer.fetcher(url);
      if (url === 'https://oauth2.googleapis.com/token') return json({ access_token: 'fixture-access-token' });
      assert.equal(init.headers.Authorization, 'Bearer fixture-access-token');
      if (url.endsWith(':acknowledge')) {
        assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active');
        acknowledgments++; return new Response(null, { status: 204 });
      }
      assert.ok(url.includes(`/applications/${packageId}/purchases/productsv2/tokens/`));
      return json(purchase);
    };
    const token = 'mixed-mode-purchase-token';
    const notice = { oneTimeProductNotification: { notificationType: 1, sku: product.google_product_id, purchaseToken: token } };
    let response = await handleCommerce(googleRequest(jwt, notice), env, authenticate, { fetcher });
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error, 'invalid_purchase');
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_events').get().n, 0);
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
    assert.equal(acknowledgments, 0);

    // A mode mismatch must not mark the notification as processed. Retrying
    // the same message after authoritative classification matches can succeed.
    if (mode === 'test') purchase.testPurchaseContext = { fopType: 'TEST' };
    else delete purchase.testPurchaseContext;
    response = await handleCommerce(googleRequest(jwt, notice), env, authenticate, { fetcher });
    assert.equal(response.status, 200);
    assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active');
    assert.equal(acknowledgments, 1);

    response = await handleCommerce(googleRequest(jwt, { testNotification: {} }, {}, '10002'), env, authenticate, { fetcher });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).test, true);
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_events').get().n, 1);
    const voidNotice = { voidedPurchaseNotification: { purchaseToken: token, productType: 2, refundType: 1 } };
    assert.equal((await handleCommerce(googleRequest(jwt, voidNotice, {}, '10003'), env, authenticate, { fetcher })).status, 200);
    assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_revocations').get().n, 1);
    assert.equal((await handleCommerce(googleRequest(jwt, notice, {}, '10004'), env, authenticate, { fetcher })).status, 200);
    assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
    assert.equal(acknowledgments, 1);
  }
});

test('unsigned RTDN and disabled notification provider cannot alter ledger', async () => {
  const env = environment();
  assert.equal((await handleCommerce(googleRequest('not-a-jwt', { testNotification: {} }), env, authenticate)).status, 401);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_events').get().n, 0);
  assert.equal((await handleCommerce(googleRequest('not-a-jwt', {}), environment({ GOOGLE_RTDN_AUDIENCE: '' }), authenticate)).status, 503);
});
