import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { handleCommerce, persistNativePurchase } from '../leaderboard/src/commerce.mjs';
import worker from '../leaderboard/src/worker.js';
import { PRODUCTS } from '../leaderboard/src/commerce_catalog.mjs';
import { accountBinding, boundedText, verifyStripeSignature, verifyGooglePurchase,
  verifyApplePurchase } from '../leaderboard/src/commerce_providers.mjs';

const ORIGIN = 'https://game.example';
const ORDER = '287ead21-9496-4220-8dc9-5e939c04a60c';
const SECRET = 'whsec_test_only_not_a_real_credential';
const product = PRODUCTS[0];
const authenticate = async (_env, request) => request.headers.get('Authorization') === 'Bearer test-player' ? { sub: 'player-one' } : null;

// Use a real SQLite database and the actual migration. This exercises SQL
// constraints, atomic batches and concurrency-safe identity predicates.
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
      const statement = db.prepare(sql);
      const parameters = Object.fromEntries(values.map((value, index) => [String(index + 1), value]));
      statement.setAllowUnknownNamedParameters(true);
      return { bind: (...args) => make(args), first: async () => statement.get(parameters) || null,
        all: async () => ({ results: statement.all(parameters) }), run: async () => statement.run(parameters) };
    };
    return make();
  }
  async batch(statements) {
    this.db.exec('BEGIN');
    try { const result = []; for (const statement of statements) result.push(await statement.run());
      this.db.exec('COMMIT'); return result;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
}

function environment(extra = {}) {
  return { DB: new D1(), COMMERCE_ENABLED: 'true', COMMERCE_MODE: 'test',
    COMMERCE_ALLOWED_ORIGINS: ORIGIN, COMMERCE_SUCCESS_URL: `${ORIGIN}/?purchase=return`,
    COMMERCE_CANCEL_URL: `${ORIGIN}/?purchase=cancel`, STRIPE_SECRET_KEY: 'sk_test_not_a_real_credential',
    STRIPE_WEBHOOK_SECRET: SECRET, COMMERCE_STRIPE_PRICES: JSON.stringify({ cozy_expedition: 'price_cozy' }), ...extra };
}

function request(path, body, { auth = true, origin = ORIGIN, method = body ? 'POST' : 'GET', headers = {} } = {}) {
  return new Request(`https://worker.example/api/commerce/${path}`, { method,
    headers: { ...(auth ? { Authorization: 'Bearer test-player' } : {}), ...(origin ? { Origin: origin } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}), ...headers },
    ...(body ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}) });
}

const responseJSON = (value) => new Response(JSON.stringify(value), { status: 200, headers: { 'Content-Type': 'application/json' } });

function stripeFixture() {
  const calls = [];
  const session = { id: 'cs_test_fixture', url: 'https://checkout.stripe.com/c/pay/cs_test_fixture', livemode: false,
    mode: 'payment', payment_status: 'paid', payment_intent: 'pi_fixture', client_reference_id: 'player-one',
    amount_total: product.price_minor, currency: product.currency,
    metadata: { user_id: 'player-one', product_id: product.id, order_id: ORDER },
    line_items: { data: [{ quantity: 1, price: { id: 'price_cozy' } }] } };
  const fixture = { session, charge: { id: 'ch_fixture', payment_intent: 'pi_fixture', amount: 299, amount_refunded: 299, refunded: true },
    dispute: { id: 'dp_fixture', payment_intent: 'pi_fixture', status: 'needs_response' }, calls,
    async fetcher(url, init) {
      calls.push({ url, init });
      if (url.includes('/prices/')) return responseJSON({ id: 'price_cozy', active: true, type: 'one_time',
        livemode: false, currency: 'usd', unit_amount: 299 });
      if (url.includes('/charges/')) return responseJSON(fixture.charge);
      if (url.includes('/disputes/')) return responseJSON(fixture.dispute);
      if (url.includes('/payment_intents/')) return responseJSON({ id: 'pi_fixture', livemode: false, metadata: session.metadata });
      if (url.includes('/checkout/sessions')) return responseJSON(session);
      throw new Error(`Unexpected provider path: ${url}`);
    },
  };
  return fixture;
}

async function googleFixture() {
  const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey('pkcs8', key.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----`;
  const env = environment({ GOOGLE_PLAY_PACKAGE_ID: 'com.blubberandbyte.waddlewars',
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'fixture@example.invalid', private_key: pem }) });
  const binding = await accountBinding('player-one');
  const purchase = { obfuscatedExternalAccountId: binding.google, purchaseStateContext: { purchaseState: 'PURCHASED' },
    productLineItem: [{ productId: product.google_product_id,
      productOfferDetails: { quantity: 1, refundableQuantity: 1, purchaseOptionId: 'buy' } }],
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING', orderId: 'GPA.fixture',
    testPurchaseContext: { fopType: 'TEST' } };
  const fixture = { env, purchase, acknowledgments: 0,
    async fetcher(url, init) {
      if (url === 'https://oauth2.googleapis.com/token') return responseJSON({ access_token: 'fixture_access_token' });
      assert.equal(init.headers.Authorization, 'Bearer fixture_access_token');
      if (url.endsWith(':acknowledge')) {
        // The server must durably record the grant before acknowledging it.
        assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active');
        fixture.acknowledgments++;
        return new Response(null, { status: 204 });
      }
      assert.ok(url.includes('/purchases/productsv2/tokens/'));
      return responseJSON(purchase);
    },
  };
  return fixture;
}

async function verifyGoogleFixture(fixture) {
  return handleCommerce(request('verify', { provider: 'google', product_id: product.id,
    purchase_token: 'fixture-permanent-purchase-token' }, { origin: null }), fixture.env, authenticate, fixture);
}

async function signature(raw, timestamp = Math.floor(Date.now() / 1000)) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const hash = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${raw}`)));
  return `t=${timestamp},v1=${Array.from(hash, (byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

async function webhook(env, fixture, type = 'checkout.session.completed', id = 'evt_fixture', object = { id: fixture.session.id }) {
  const raw = JSON.stringify({ id, type, livemode: false, data: { object } });
  return handleCommerce(request('stripe/webhook', raw, { auth: false, origin: null,
    headers: { 'Stripe-Signature': await signature(raw) } }), env, authenticate, fixture);
}

async function startCheckout(env, fixture, extra = {}) {
  return handleCommerce(request('checkout', { platform: 'web', request_id: ORDER, product_id: product.id, ...extra }), env, authenticate, fixture);
}

test('catalog matches runtime assets and all products are cosmetic non-consumables', () => {
  const data = JSON.parse(readFileSync(new URL('../data/commerce/catalog.json', import.meta.url)));
  assert.deepEqual(data.products, PRODUCTS);
  const cosmetics = readFileSync(new URL('../scripts/progression/cosmetics_db.gd', import.meta.url), 'utf8');
  for (const item of PRODUCTS) {
    assert.equal(item.cosmetics.length, 3);
    assert.ok(item.price_minor > 0);
    for (const id of item.cosmetics) assert.ok(cosmetics.includes(`"${id}": {`), `${id} must exist`);
    assert.ok(!item.cosmetics.some((id) => id.startsWith('body_')));
  }
  assert.ok(data.disclosure.includes('Fish unlocks cost the sum of each unowned item'));
  assert.ok(data.disclosure.includes('owned items are excluded'));
  assert.ok(data.disclosure.includes('no subscriptions, random rewards or gameplay bonuses'));
});

test('deployed Worker entrypoint routes unavailable commerce instead of generic404', async () => {
  const response = await worker.fetch(request('catalog', null, { auth: false }), {
    COMMERCE_ENABLED: 'false', COMMERCE_ALLOWED_ORIGINS: ORIGIN,
  });
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'store_unavailable' });
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), ORIGIN);
});

test('Worker commerce preflight uses explicit origin and method policy', async () => {
  for (const [origin, status] of [[ORIGIN, 204], ['https://unapproved.example', 403]]) {
    const response = await worker.fetch(request('catalog', null, { auth: false, origin, method: 'OPTIONS' }), {
      COMMERCE_ALLOWED_ORIGINS: ORIGIN,
    });
    assert.equal(response.status, status);
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), status === 204 ? ORIGIN : null);
    if (status === 204) {
      assert.equal(response.headers.get('Access-Control-Allow-Methods'), 'GET, POST, OPTIONS');
      assert.equal(response.headers.get('Access-Control-Allow-Headers'), 'Authorization, Content-Type');
    }
  }
});

test('Worker enabled catalog requires authenticated identity before database or provider access', async () => {
  const response = await worker.fetch(request('catalog', null, { auth: false }), {
    COMMERCE_ENABLED: 'true', COMMERCE_MODE: 'test', COMMERCE_ALLOWED_ORIGINS: ORIGIN,
    get DB() { throw new Error('unauthenticated request must not access database'); },
  });
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: 'unauthorized' });
});

test('commerce disabled/auth/origin gates fail closed without contacting payment provider', async () => {
  const fixture = stripeFixture();
  for (const [env, req, code] of [
    [environment({ COMMERCE_ENABLED: 'false' }), request('checkout', {}), 503],
    [environment(), request('catalog', null, { auth: false }), 401],
    [environment(), request('checkout', {}, { origin: 'https://attacker.example' }), 403],
    [environment(), request('checkout', {}, { origin: null }), 403],
    [environment(), request('checkout', { platform: 'android' }), 400],
  ]) {
    const response = await handleCommerce(req, env, authenticate, fixture);
    assert.equal(response.status, code);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
  }
  assert.equal(fixture.calls.length, 0);
});

test('native charge-sheet preparation needs explicit sales enablement and notification readiness; reconciliation remains available', async () => {
  for (const provider of ['apple', 'google']) {
    const extra = provider === 'apple' ? { APPLE_BUNDLE_ID: 'com.blubberandbyte.waddlewars', APPLE_RECEIPT_VERIFIER: {} } :
      { GOOGLE_PLAY_PACKAGE_ID: 'com.blubberandbyte.waddlewars', GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: '{}' };
    const env = environment(extra);
    const prepare = () => request('prepare-native-purchase', { provider, product_id: product.id }, { origin: null });
    let catalog = await (await handleCommerce(request('catalog', null), env, authenticate)).json();
    assert.equal(catalog.native_purchase_configured[provider], false);
    assert.equal(catalog.native_verification_configured[provider], true);
    assert.equal((await handleCommerce(prepare(), env, authenticate)).status, 503);
    env[provider === 'apple' ? 'COMMERCE_APPLE_SALES_ENABLED' : 'COMMERCE_GOOGLE_SALES_ENABLED'] = 'true';
    assert.equal((await handleCommerce(prepare(), env, authenticate)).status, 503);
    if (provider === 'apple') env.APPLE_SERVER_NOTIFICATIONS_ENABLED = 'true';
    else Object.assign(env, { GOOGLE_RTDN_AUDIENCE: 'expected-audience', GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL: 'expected@service.example',
      GOOGLE_RTDN_SUBSCRIPTION: 'projects/test/subscriptions/rtdn' });
    catalog = await (await handleCommerce(request('catalog', null), env, authenticate)).json();
    assert.equal(catalog.native_purchase_configured[provider], true);
    const authorized = await (await handleCommerce(prepare(), env, authenticate)).json();
    assert.equal(authorized.approved, true); assert.equal(authorized.product_id, product.id); assert.equal(authorized.provider, provider);
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
    assert.equal((await handleCommerce(request('prepare-native-purchase', { provider, product_id: product.id }), env, authenticate)).status, 400);
    assert.equal((await handleCommerce(request('prepare-native-purchase', { provider, product_id: product.id }, { origin: null, auth: false }), env, authenticate)).status, 401);
    assert.equal((await handleCommerce(request('prepare-native-purchase', { provider, product_id: 'unknown' }, { origin: null }), env, authenticate)).status, 400);
    env[provider === 'apple' ? 'COMMERCE_APPLE_SALES_ENABLED' : 'COMMERCE_GOOGLE_SALES_ENABLED'] = 'false';
    const reconcile = await handleCommerce(request('account', null, { origin: null }), env, authenticate);
    assert.equal(reconcile.status, 200); assert.ok((await reconcile.json()).bindings[provider]);
  }
});

test('signed raw Stripe payload verified; changed, stale, future and duplicate timestamps rejected', async () => {
  const raw = '{"id":"evt_fixture"}';
  const good = await signature(raw);
  await verifyStripeSignature(raw, good, SECRET);
  await verifyStripeSignature(raw, `${good},v1=${'a'.repeat(64)}`, SECRET);
  await assert.rejects(verifyStripeSignature(`${raw} `, good, SECRET));
  await assert.rejects(verifyStripeSignature(raw, await signature(raw, Math.floor(Date.now() / 1000) - 301), SECRET));
  await assert.rejects(verifyStripeSignature(raw, await signature(raw, Math.floor(Date.now() / 1000) + 301), SECRET));
  await assert.rejects(verifyStripeSignature(raw, `${good},t=1`, SECRET));
  await assert.rejects(verifyStripeSignature(raw, good, 'wrong_secret'));
});

test('body bound enforces actual streamed size, not only Content-Length', async () => {
  await assert.rejects(boundedText(new Request('https://test.example', { method: 'POST', body: 'x'.repeat(20) }), 10),
    (error) => error.status === 413);
  assert.equal(await boundedText(new Request('https://test.example', { method: 'POST', body: '雪' }), 3), '雪');
});

test('checkout sends server price, identity metadata and stable idempotency key; never grants on redirect', async () => {
  const env = environment(); const fixture = stripeFixture();
  const response = await startCheckout(env, fixture, { user_id: 'attacker', price_minor: 1, price_id: 'price_free' });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).checkout_url, fixture.session.url);
  const create = fixture.calls.find((call) => call.init.method === 'POST');
  assert.equal(create.init.headers['Idempotency-Key'], `waddle-wars:checkout:${ORDER}`);
  assert.equal(create.init.body.get('line_items[0][price]'), 'price_cozy');
  assert.equal(create.init.body.get('metadata[user_id]'), 'player-one');
  assert.equal(create.init.body.get('payment_intent_data[metadata][order_id]'), ORDER);
  assert.equal((await handleCommerce(request('entitlements'), env, authenticate)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_purchases').get().n, 0);
  assert.equal((await startCheckout(env, fixture)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_checkouts').get().n, 1);
});

test('wrong price or arbitrary return URL rejected', async () => {
  const env = environment({ COMMERCE_SUCCESS_URL: 'https://attacker.example/redirect' });
  const fixture = stripeFixture();
  assert.equal((await startCheckout(env, fixture)).status, 503);
  const badPriceFixture = { fetcher: async () => responseJSON({ id: 'price_cozy', active: true,
    type: 'one_time', livemode: false, currency: 'usd', unit_amount: 1 }) };
  assert.equal((await startCheckout(environment(), badPriceFixture)).status, 503);
});

test('webhook requires signature and correct mode; client metadata cannot grant', async () => {
  const env = environment(); const fixture = stripeFixture();
  const response = await handleCommerce(request('stripe/webhook', { id: 'evt_attack',
    data: { object: { metadata: { user_id: 'player-one', product_id: product.id } } } }, { auth: false }), env, authenticate, fixture);
  assert.equal(response.status, 400);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_purchases').get().n, 0);
  const raw = JSON.stringify({ id: 'evt_wrongmode', livemode: true, type: 'checkout.session.completed' });
  assert.equal((await handleCommerce(request('stripe/webhook', raw, { auth: false, headers: { 'Stripe-Signature': await signature(raw) } }), env, authenticate)).status, 400);
});

test('paid completion and async completion fulfill once; replay returns same ownership', async () => {
  const env = environment(); const fixture = stripeFixture();
  await startCheckout(env, fixture);
  assert.equal((await webhook(env, fixture)).status, 200);
  assert.equal((await webhook(env, fixture)).status, 200);
  assert.equal((await webhook(env, fixture, 'checkout.session.async_payment_succeeded', 'evt_async')).status, 200);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_purchases').get().n, 1);
  const owned = await (await handleCommerce(request('entitlements'), env, authenticate)).json();
  assert.deepEqual(owned.product_ids, ['cozy_expedition']);
  assert.deepEqual(owned.cosmetic_ids, [...product.cosmetics].sort());
  assert.equal((await startCheckout(env, fixture)).status, 409);
});

test('pending payment grants nothing; async paid event then fulfills', async () => {
  const env = environment(); const fixture = stripeFixture();
  await startCheckout(env, fixture);
  fixture.session.payment_status = 'unpaid';
  assert.equal((await webhook(env, fixture)).status, 200);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_purchases').get().n, 0);
  fixture.session.payment_status = 'paid';
  assert.equal((await webhook(env, fixture, 'checkout.session.async_payment_succeeded', 'evt_async')).status, 200);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_purchases').get().n, 1);
});

test('server re-fetch rejects wrong quantity, amount, identity, price and session ID', async () => {
  for (const mutate of [
    (session) => { session.line_items.data[0].quantity = 2; },
    (session) => { session.amount_total = 1; },
    (session) => { session.metadata.user_id = 'another-player'; },
    (session) => { session.line_items.data[0].price.id = 'price_attack'; },
    (session) => { session.id = 'cs_unreserved'; },
  ]) {
    const env = environment(); const fixture = stripeFixture(); await startCheckout(env, fixture);
    mutate(fixture.session);
    assert.equal((await webhook(env, fixture)).status, 400);
    assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_purchases').get().n, 0);
  }
});

test('refund before completion blocks late fulfillment; full refund revokes active entitlement', async () => {
  for (const refundFirst of [true, false]) {
    const env = environment(); const fixture = stripeFixture(); await startCheckout(env, fixture);
    if (!refundFirst) await webhook(env, fixture);
    assert.equal((await webhook(env, fixture, 'charge.refunded', 'evt_refund', { id: 'ch_fixture' })).status, 200);
    assert.equal((await webhook(env, fixture, 'checkout.session.completed', 'evt_late')).status, 200);
    assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
    const owned = await (await handleCommerce(request('entitlements'), env, authenticate)).json();
    assert.deepEqual(owned.cosmetic_ids, []);
  }
});

test('dispute temporarily revokes; won dispute restores; cannot restore a refunded purchase', async () => {
  const env = environment(); const fixture = stripeFixture(); await startCheckout(env, fixture); await webhook(env, fixture);
  await webhook(env, fixture, 'charge.dispute.created', 'evt_dispute', { id: 'dp_fixture' });
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'disputed');
  fixture.dispute.status = 'won';
  await webhook(env, fixture, 'charge.dispute.closed', 'evt_disputewon', { id: 'dp_fixture' });
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active');
  await webhook(env, fixture, 'charge.refunded', 'evt_refund', { id: 'ch_fixture' });
  await webhook(env, fixture, 'charge.dispute.closed', 'evt_disputewon2', { id: 'dp_fixture' });
  assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
});

test('native verification unavailable is an explicit failure, never a cosmetic grant', async () => {
  const env = environment();
  assert.equal((await handleCommerce(request('verify', { provider: 'apple', product_id: product.id, transaction_id: '2000000000000000' }), env, authenticate)).status, 503);
  assert.equal((await handleCommerce(request('verify', { provider: 'google', product_id: product.id, purchase_token: 'test-token-123' }), env, authenticate)).status, 400);
  assert.equal(env.DB.db.prepare('SELECT COUNT(*) AS n FROM commerce_purchases').get().n, 0);
});

test('native transaction cannot transfer to another app account; refund is terminal; acknowledgment after persistence', async () => {
  const env = environment(); let acknowledged = false;
  const purchase = { provider: 'google', transaction_id: 'token_hash', user_id: 'player-one', product_id: product.id,
    payment_reference: 'GPA.test', state: 'active', acknowledge: async () => {
      assert.equal(env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'active'); acknowledged = true;
    } };
  assert.equal(await persistNativePurchase(env, purchase), 'active'); assert.ok(acknowledged);
  await assert.rejects(persistNativePurchase(env, { ...purchase, user_id: 'another-player' }), /purchase_already_linked/);
  assert.equal(await persistNativePurchase(env, { ...purchase, state: 'refunded' }), 'refunded');
  acknowledged = false;
  assert.equal(await persistNativePurchase(env, purchase), 'refunded'); assert.equal(acknowledged, false);
});

test('Apple verifier response must bind app, store account, environment and non-consumable product', async () => {
  const binding = await accountBinding('player-one');
  const transaction = { transactionId: '2000000000000000', originalTransactionId: '2000000000000000',
    bundleId: 'com.blubberandbyte.waddlewars', productId: product.apple_product_id, type: 'Non-Consumable',
    quantity: 1, appAccountToken: binding.apple, environment: 'Sandbox', signedDate: Date.now() };
  const env = environment({ APPLE_BUNDLE_ID: transaction.bundleId,
    APPLE_RECEIPT_VERIFIER: { fetch: async () => responseJSON({ verified: true, transaction }) } });
  assert.equal((await verifyApplePurchase(env, product, 'player-one', transaction.transactionId)).state, 'active');
  transaction.revocationDate = Date.now();
  assert.equal((await verifyApplePurchase(env, product, 'player-one', transaction.transactionId)).state, 'refunded');
  await assert.rejects(verifyApplePurchase(env, product, 'another-player', transaction.transactionId), /invalid_purchase/);
  transaction.environment = 'Production';
  await assert.rejects(verifyApplePurchase(env, product, 'player-one', transaction.transactionId), /invalid_purchase/);
});

test('Google provider uses signed OAuth, validates authoritative account/product/state, and acknowledges non-consumable', async () => {
  const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const keyBytes = new Uint8Array(await crypto.subtle.exportKey('pkcs8', key.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(keyBytes).toString('base64')}\n-----END PRIVATE KEY-----`;
  const env = environment({ GOOGLE_PLAY_PACKAGE_ID: 'com.blubberandbyte.waddlewars',
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: 'test@example.invalid', private_key: pem }) });
  const binding = await accountBinding('player-one');
  const googlePurchase = { obfuscatedExternalAccountId: binding.google, purchaseStateContext: { purchaseState: 'PURCHASED' },
    productLineItem: [{ productId: product.google_product_id, productOfferDetails: { quantity: 1, refundableQuantity: 1 } }],
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING', orderId: 'GPA.test',
    testPurchaseContext: { fopType: 'TEST' } };
  let acknowledgementCount = 0;
  const fetcher = async (url, init) => {
    if (url === 'https://oauth2.googleapis.com/token') {
      const jwt = init.body.get('assertion'); const [header, payload, signature] = jwt.split('.');
      assert.equal(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key.publicKey,
        Buffer.from(signature, 'base64url'), new TextEncoder().encode(`${header}.${payload}`)), true);
      assert.equal(JSON.parse(Buffer.from(payload, 'base64url')).scope, 'https://www.googleapis.com/auth/androidpublisher');
      return responseJSON({ access_token: 'fake_access_token' });
    }
    assert.equal(init.headers.Authorization, 'Bearer fake_access_token');
    if (url.endsWith(':acknowledge')) { acknowledgementCount++; return responseJSON({}); }
    assert.ok(url.includes('/purchases/productsv2/tokens/'));
    return responseJSON(googlePurchase);
  };
  const verified = await verifyGooglePurchase(env, product, 'player-one', 'purchase-token-test', fetcher);
  assert.equal(verified.state, 'active'); assert.equal(verified.transaction_id.length, 64);
  await verified.acknowledge(); assert.equal(acknowledgementCount, 1);
  googlePurchase.purchaseStateContext.purchaseState = 'PENDING';
  await assert.rejects(verifyGooglePurchase(env, product, 'player-one', 'purchase-token-test', fetcher), /purchase_pending/);
  googlePurchase.purchaseStateContext.purchaseState = 'CANCELLED';
  assert.equal((await verifyGooglePurchase(env, product, 'player-one', 'purchase-token-test', fetcher)).state, 'refunded');
  await assert.rejects(verifyGooglePurchase(env, product, 'another-player', 'purchase-token-test', fetcher), /invalid_purchase/);
});

test('Google permanent buy option fulfills and acknowledges after durable ownership', async () => {
  const fixture = await googleFixture();
  const response = await verifyGoogleFixture(fixture);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.state, 'active');
  assert.deepEqual(payload.product_ids, [product.id]);
  assert.equal(fixture.acknowledgments, 1);
  assert.equal(fixture.env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 1);
});

test('Google test/live verification rejects opposite-mode receipts before grant or acknowledgment', async () => {
  const fixture = await googleFixture();
  for (const [mode, context, legacyType] of [
    ['test', undefined, undefined],
    ['test', undefined, 0],
    ['live', { fopType: 'TEST' }, undefined],
  ]) {
    fixture.env.COMMERCE_MODE = mode;
    delete fixture.purchase.testPurchaseContext;
    delete fixture.purchase.purchaseType;
    if (context !== undefined) fixture.purchase.testPurchaseContext = context;
    if (legacyType !== undefined) fixture.purchase.purchaseType = legacyType;
    const response = await verifyGoogleFixture(fixture);
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error, 'invalid_purchase');
    assert.equal(fixture.env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
    assert.equal(fixture.acknowledgments, 0);
  }
});

test('Google malformed or unsupported v2 test context fails closed in both modes', async () => {
  const fixture = await googleFixture();
  for (const mode of ['test', 'live']) {
    fixture.env.COMMERCE_MODE = mode;
    for (const context of [null, {}, { fopType: 'FOP_TYPE_UNSPECIFIED' }, { fopType: 'future-type' },
      { fopType: 1 }, [], 'TEST', false]) {
      fixture.purchase.testPurchaseContext = context;
      const response = await verifyGoogleFixture(fixture);
      assert.equal(response.status, 400);
      assert.equal((await response.json()).error, 'invalid_purchase');
      assert.equal(fixture.env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
      assert.equal(fixture.acknowledgments, 0);
    }
  }
  fixture.env.COMMERCE_MODE = 'unconfigured';
  fixture.purchase.testPurchaseContext = { fopType: 'TEST' };
  await assert.rejects(verifyGooglePurchase(fixture.env, product, 'player-one',
    'fixture-permanent-purchase-token', fixture.fetcher), /invalid_purchase/);
});

test('Google matching-mode permanent purchases and both refund forms preserve durable fulfillment', async () => {
  const fixture = await googleFixture();
  const offer = fixture.purchase.productLineItem[0].productOfferDetails;
  for (const mode of ['test', 'live']) {
    fixture.env.COMMERCE_MODE = mode;
    if (mode === 'test') fixture.purchase.testPurchaseContext = { fopType: 'TEST' };
    else delete fixture.purchase.testPurchaseContext;
    for (const refund of ['cancelled', 'quantity-refunded']) {
      fixture.env.DB = new D1();
      fixture.acknowledgments = 0;
      fixture.purchase.purchaseStateContext.purchaseState = 'PURCHASED';
      offer.refundableQuantity = 1;
      let response = await verifyGoogleFixture(fixture);
      assert.equal(response.status, 200);
      assert.deepEqual((await response.json()).product_ids, [product.id]);
      assert.equal(fixture.acknowledgments, 1);
      if (refund === 'cancelled') fixture.purchase.purchaseStateContext.purchaseState = 'CANCELLED';
      else offer.refundableQuantity = 0;
      response = await verifyGoogleFixture(fixture);
      assert.equal(response.status, 200);
      const payload = await response.json();
      assert.equal(payload.state, 'refunded');
      assert.deepEqual(payload.product_ids, []);
      assert.equal(fixture.env.DB.db.prepare('SELECT state FROM commerce_purchases').get().state, 'refunded');
      assert.equal(fixture.acknowledgments, 1);
    }
  }
});

test('Google rental options cannot become permanent cosmetic grants or be acknowledged', async () => {
  const fixture = await googleFixture();
  const offer = fixture.purchase.productLineItem[0].productOfferDetails;
  offer.purchaseOptionId = 'rent';
  for (const rental of [{}, { rentalPeriod: 'P2D' }, null]) {
    // Even malformed rental metadata cannot be interpreted as a buy option.
    offer.rentOfferDetails = rental;
    const response = await verifyGoogleFixture(fixture);
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error, 'invalid_purchase');
    assert.equal(fixture.env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
    assert.equal(fixture.acknowledgments, 0);
  }
});

test('Google permanent preorder remains pending until authoritative purchase completion', async () => {
  const fixture = await googleFixture();
  const offer = fixture.purchase.productLineItem[0].productOfferDetails;
  offer.preorderOfferDetails = { preorderReleaseTime: new Date(Date.now() + 86400000).toISOString() };
  fixture.purchase.purchaseStateContext.purchaseState = 'PENDING';
  let response = await verifyGoogleFixture(fixture);
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error, 'purchase_pending');
  assert.equal(fixture.env.DB.db.prepare('SELECT COUNT(*) n FROM commerce_purchases').get().n, 0);
  assert.equal(fixture.acknowledgments, 0);
  // A completed permanent preorder is a legitimate buy entitlement. Provider
  // purchase state, not the client or a local release-date timer, authorizes it.
  offer.preorderOfferDetails.preorderReleaseTime = new Date(Date.now() - 1000).toISOString();
  fixture.purchase.purchaseStateContext.purchaseState = 'PURCHASED';
  response = await verifyGoogleFixture(fixture);
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).product_ids, [product.id]);
  assert.equal(fixture.acknowledgments, 1);
  fixture.purchase.purchaseStateContext.purchaseState = 'CANCELLED';
  response = await verifyGoogleFixture(fixture);
  assert.equal(response.status, 200);
  const cancelled = await response.json();
  assert.equal(cancelled.state, 'refunded');
  assert.deepEqual(cancelled.product_ids, []);
  assert.equal(fixture.acknowledgments, 1);
});
