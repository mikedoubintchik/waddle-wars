import { PRODUCTS, DISCLOSURE, productById } from './commerce_catalog.mjs';
import { handleNativeAuth } from './commerce_native_auth.mjs';
import { handleNativeNotification } from './commerce_notifications.mjs';
import { isSubjectRetired, requireActiveSubject } from './account_lifecycle.mjs';
import { CommerceError, accountBinding, boundedText, stripeConfig, stripeRequest,
  validateStripePrice, verifyStripeSignature, verifyApplePurchase, verifyGooglePurchase } from './commerce_providers.mjs';

const ROOT = '/api/commerce';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function allowedOrigins(env) {
  return String(env.COMMERCE_ALLOWED_ORIGINS || '').split(',').map((value) => value.trim()).filter(Boolean);
}

function corsHeaders(env, request) {
  const origin = request.headers.get('Origin');
  return { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Vary: 'Origin',
    ...(origin && allowedOrigins(env).includes(origin) ? { 'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type', 'Access-Control-Max-Age': '600' } : {}) };
}

function json(env, request, data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders(env, request) });
}

function requireEnabled(env) {
  if (env.COMMERCE_ENABLED !== 'true' || !['live', 'test'].includes(env.COMMERCE_MODE)) {
    throw new CommerceError('store_unavailable', 503);
  }
}

function requireOrigin(env, request, webOnly = false) {
  const origin = request.headers.get('Origin');
  if ((webOnly && !origin) || (origin && !allowedOrigins(env).includes(origin))) {
    throw new CommerceError('origin_not_allowed', 403);
  }
}

async function bodyJson(request) {
  let result;
  try { result = JSON.parse(await boundedText(request, 8192)); } catch (error) {
    if (error instanceof CommerceError) throw error;
    throw new CommerceError('invalid_json');
  }
  if (!result || typeof result !== 'object' || Array.isArray(result)) throw new CommerceError('invalid_json');
  return result;
}

async function entitlements(env, userId) {
  await requireActiveSubject(env, userId);
  const rows = await env.DB.prepare(
    'SELECT DISTINCT product_id FROM commerce_purchases WHERE user_id = ?1 AND state = \'active\'',
  ).bind(userId).all();
  const productIds = rows.results.map((row) => row.product_id).filter((id) => productById(id)).sort();
  const cosmeticIds = [...new Set(productIds.flatMap((id) => productById(id).cosmetics))].sort();
  await requireActiveSubject(env, userId);
  return { product_ids: productIds, cosmetic_ids: cosmeticIds, verified_at: new Date().toISOString() };
}

function nativeVerificationConfigured(env, provider) {
  if (provider === 'apple') return Boolean(env.APPLE_BUNDLE_ID && env.APPLE_RECEIPT_VERIFIER);
  if (provider === 'google') return Boolean(env.GOOGLE_PLAY_PACKAGE_ID && env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON);
  return false;
}

function nativeSalesConfigured(env, provider) {
  if (!nativeVerificationConfigured(env, provider)) return false;
  if (provider === 'apple') return env.COMMERCE_APPLE_SALES_ENABLED === 'true' && env.APPLE_SERVER_NOTIFICATIONS_ENABLED === 'true';
  if (provider === 'google') return env.COMMERCE_GOOGLE_SALES_ENABLED === 'true' &&
    Boolean(env.GOOGLE_RTDN_AUDIENCE && env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL && env.GOOGLE_RTDN_SUBSCRIPTION);
  return false;
}

async function storeAccount(env, userId) {
  const bindings = await accountBinding(userId);
  await requireActiveSubject(env, userId);
  await env.DB.prepare('INSERT INTO commerce_store_accounts(user_id, apple_account_token, google_account_id) VALUES (?1, ?2, ?3) ON CONFLICT(user_id) DO NOTHING')
    .bind(userId, bindings.apple, bindings.google).run();
  await requireActiveSubject(env, userId);
  return bindings;
}

async function prepareNativePurchase(env, request, userId) {
  if (request.headers.has('Origin')) throw new CommerceError('invalid_native_purchase');
  const body = await bodyJson(request);
  if (!['apple', 'google'].includes(body.provider)) throw new CommerceError('invalid_provider');
  const product = productById(body.product_id);
  if (!product) throw new CommerceError('unknown_product');
  if (!nativeSalesConfigured(env, body.provider)) throw new CommerceError('native_sales_unavailable', 503);
  if ((await entitlements(env, userId)).product_ids.includes(product.id)) throw new CommerceError('already_owned', 409);
  await storeAccount(env, userId);
  // This authorizes opening the native store sheet, not fulfillment. A charge
  // still requires StoreKit/Play Billing; grants require verified paid receipts.
  return { approved: true, product_id: product.id, provider: body.provider,
    store_product_id: body.provider === 'apple' ? product.apple_product_id : product.google_product_id };
}

function validatedReturnURL(env, name) {
  let value;
  try { value = new URL(env[name]); } catch { throw new CommerceError('checkout_unavailable', 503); }
  if (value.protocol !== 'https:' || !allowedOrigins(env).includes(value.origin) ||
      value.username || value.password) throw new CommerceError('checkout_unavailable', 503);
  return value.href;
}

async function checkout(env, request, userId, fetcher) {
  // Native applications expose StoreKit / Play Billing only. Browser Checkout
  // additionally requires an approved web origin and an authenticated account.
  requireOrigin(env, request, true);
  const body = await bodyJson(request);
  if (body.platform !== 'web' || !UUID.test(body.request_id || '')) throw new CommerceError('invalid_checkout');
  const product = productById(body.product_id);
  if (!product) throw new CommerceError('unknown_product');
  const owned = await entitlements(env, userId);
  if (owned.product_ids.includes(product.id) || product.cosmetics.every((id) => owned.cosmetic_ids.includes(id))) {
    throw new CommerceError('already_owned', 409);
  }
  const config = stripeConfig(env);
  const priceId = config.prices[product.id];
  if (typeof priceId !== 'string' || !/^price_[A-Za-z0-9]+$/.test(priceId)) throw new CommerceError('checkout_unavailable', 503);
  const price = await stripeRequest(env, `prices/${priceId}`, {}, fetcher);
  validateStripePrice(price, product, priceId, config.mode);
  const successURL = validatedReturnURL(env, 'COMMERCE_SUCCESS_URL');
  const cancelURL = validatedReturnURL(env, 'COMMERCE_CANCEL_URL');
  await requireActiveSubject(env, userId);
  await env.DB.prepare(
    'INSERT INTO commerce_checkouts(request_id, user_id, product_id) VALUES (?1, ?2, ?3) ON CONFLICT DO NOTHING',
  ).bind(body.request_id, userId, product.id).run();
  const order = await env.DB.prepare('SELECT * FROM commerce_checkouts WHERE request_id = ?1')
    .bind(body.request_id).first();
  if (!order || order.user_id !== userId || order.product_id !== product.id) throw new CommerceError('checkout_conflict', 409);
  if (order.state !== 'pending') throw new CommerceError('checkout_closed', 409);
  const metadata = { user_id: userId, product_id: product.id, order_id: body.request_id };
  const form = new URLSearchParams({ mode: 'payment', 'line_items[0][price]': priceId,
    'line_items[0][quantity]': '1', success_url: successURL, cancel_url: cancelURL,
    client_reference_id: userId });
  for (const [key, value] of Object.entries(metadata)) {
    form.set(`metadata[${key}]`, value);
    form.set(`payment_intent_data[metadata][${key}]`, value);
  }
  // Repeated requests use the same Stripe key, including after a lost response.
  await requireActiveSubject(env, userId);
  const session = await stripeRequest(env, 'checkout/sessions', { method: 'POST', body: form,
    headers: { 'Idempotency-Key': `waddle-wars:checkout:${body.request_id}` } }, fetcher);
  // A provider operation already in flight cannot be undone here. Never
  // deliver its URL or grant a purchase to an account retired during that wait.
  await requireActiveSubject(env, userId);
  let paymentURL;
  try { paymentURL = new URL(session.url); } catch { throw new CommerceError('invalid_provider_response', 502); }
  if (paymentURL.protocol !== 'https:' || paymentURL.hostname !== 'checkout.stripe.com' ||
      typeof session.id !== 'string' || !session.id.startsWith('cs_') ||
      session.livemode !== (config.mode === 'live')) throw new CommerceError('invalid_provider_response', 502);
  await env.DB.prepare('UPDATE commerce_checkouts SET stripe_session_id = ?2, payment_intent_id = ?3, updated_at = datetime(\'now\') WHERE request_id = ?1')
    .bind(body.request_id, session.id, typeof session.payment_intent === 'string' ? session.payment_intent : null).run();
  await requireActiveSubject(env, userId);
  return { checkout_url: paymentURL.href, checkout_id: session.id, product_id: product.id };
}

export async function persistNativePurchase(env, purchase, { appleRefundReversal = false } = {}) {
  if (await isSubjectRetired(env, purchase.user_id)) return 'retired';
  const existing = await env.DB.prepare('SELECT user_id, product_id, state FROM commerce_purchases WHERE provider = ?1 AND transaction_id = ?2')
    .bind(purchase.provider, purchase.transaction_id).first();
  if (existing && (existing.user_id !== purchase.user_id || existing.product_id !== purchase.product_id)) {
    throw new CommerceError('purchase_already_linked', 409);
  }
  const signedAt = purchase.provider === 'apple' ? purchase.provider_signed_at || 0 : 0;
  // Only the certificate-verified REFUND_REVERSED notification path can request
  // restoration; client receipt verification never removes a refund tombstone.
  const restore = appleRefundReversal && purchase.provider === 'apple' && purchase.state === 'active' && signedAt > 0;
  const statements = [];
  if (restore) statements.push(env.DB.prepare(`DELETE FROM commerce_revocations
    WHERE provider = ?1 AND transaction_id = ?2 AND provider_signed_at < ?3
    AND NOT EXISTS(SELECT 1 FROM commerce_purchases WHERE provider = ?1 AND transaction_id = ?2
      AND state = 'refunded' AND provider_signed_at >= ?3)`)
    .bind(purchase.provider, purchase.transaction_id, signedAt));
  // Identity and monotonic provider timestamp restrictions also appear in SQL
  // to cover concurrent deliveries. Equal-time conflicts always favor refund.
  statements.push(env.DB.prepare(`INSERT INTO commerce_purchases(provider, transaction_id, user_id, product_id, payment_reference, state, provider_signed_at)
    VALUES (?1, ?2, ?3, ?4, ?5,
      CASE WHEN EXISTS(SELECT 1 FROM commerce_revocations WHERE provider = ?1 AND transaction_id = ?2)
        THEN 'refunded' ELSE ?6 END,
      CASE WHEN EXISTS(SELECT 1 FROM commerce_revocations WHERE provider = ?1 AND transaction_id = ?2)
        THEN CASE WHEN ?6 = 'active' AND NOT ?8
          THEN (SELECT provider_signed_at FROM commerce_revocations WHERE provider = ?1 AND transaction_id = ?2)
          ELSE MAX(?7, (SELECT provider_signed_at FROM commerce_revocations WHERE provider = ?1 AND transaction_id = ?2)) END
        ELSE ?7 END) ON CONFLICT(provider, transaction_id) DO UPDATE SET
    state = CASE WHEN commerce_purchases.state = 'refunded'
      AND (NOT ?8 OR excluded.provider_signed_at <= commerce_purchases.provider_signed_at) THEN 'refunded'
      ELSE excluded.state END,
    provider_signed_at = CASE WHEN commerce_purchases.state = 'refunded' AND excluded.state = 'active' AND NOT ?8
      THEN commerce_purchases.provider_signed_at ELSE MAX(commerce_purchases.provider_signed_at, excluded.provider_signed_at) END,
    updated_at = datetime('now') WHERE commerce_purchases.user_id = excluded.user_id
    AND commerce_purchases.product_id = excluded.product_id
    AND excluded.provider_signed_at >= commerce_purchases.provider_signed_at`)
    .bind(purchase.provider, purchase.transaction_id, purchase.user_id, purchase.product_id, purchase.payment_reference, purchase.state, signedAt, restore ? 1 : 0));
  try { await env.DB.batch(statements); }
  catch (error) {
    // The database fence is authoritative when retirement races a callback.
    // Atomic rollback also preserves any reversible refund tombstone.
    if (await isSubjectRetired(env, purchase.user_id)) return 'retired';
    throw error;
  }
  if (await isSubjectRetired(env, purchase.user_id)) return 'retired';
  const linked = await env.DB.prepare('SELECT user_id, product_id, state FROM commerce_purchases WHERE provider = ?1 AND transaction_id = ?2')
    .bind(purchase.provider, purchase.transaction_id).first();
  if (!linked || linked.user_id !== purchase.user_id || linked.product_id !== purchase.product_id) {
    throw new CommerceError('purchase_already_linked', 409);
  }
  if (linked.state === 'active' && purchase.acknowledge) await purchase.acknowledge();
  if (await isSubjectRetired(env, purchase.user_id)) return 'retired';
  return linked.state;
}

async function verifyNative(env, request, userId, fetcher) {
  const body = await bodyJson(request);
  const product = productById(body.product_id);
  if (!product) throw new CommerceError('unknown_product');
  let purchase;
  if (body.provider === 'apple') purchase = await verifyApplePurchase(env, product, userId, body.transaction_id);
  else if (body.provider === 'google') purchase = await verifyGooglePurchase(env, product, userId, body.purchase_token, fetcher);
  else throw new CommerceError('invalid_provider');
  const state = await persistNativePurchase(env, purchase);
  return { state, ...(await entitlements(env, userId)) };
}

async function grantStripeSession(env, event, fetcher) {
  const id = event.data?.object?.id;
  if (typeof id !== 'string' || !/^cs_[A-Za-z0-9_]+$/.test(id)) throw new CommerceError('invalid_event');
  // Re-fetch the session. Redirect URLs and browser callbacks never fulfill.
  const session = await stripeRequest(env, `checkout/sessions/${id}?expand[]=line_items`, {}, fetcher);
  const config = stripeConfig(env);
  const product = productById(session.metadata?.product_id);
  if (!product || session.livemode !== (config.mode === 'live') || session.mode !== 'payment') throw new CommerceError('invalid_event');
  if (session.payment_status !== 'paid') return; // Includes asynchronous pending payments.
  const order = await env.DB.prepare('SELECT * FROM commerce_checkouts WHERE request_id = ?1')
    .bind(session.metadata.order_id).first();
  const items = session.line_items?.data;
  if (!order || order.stripe_session_id !== session.id || order.user_id !== session.metadata.user_id ||
      order.user_id !== session.client_reference_id || order.product_id !== product.id ||
      typeof session.payment_intent !== 'string' || session.amount_total !== product.price_minor ||
      session.currency !== product.currency || items?.length !== 1 ||
      items[0].quantity !== 1 || items[0].price?.id !== config.prices[product.id]) throw new CommerceError('invalid_event');
  if (await isSubjectRetired(env, order.user_id)) return;
  await env.DB.batch([
    env.DB.prepare(`UPDATE commerce_checkouts SET state = CASE WHEN state = 'pending' THEN 'paid' ELSE state END,
      payment_intent_id = ?2, updated_at = datetime('now') WHERE request_id = ?1`)
      .bind(order.request_id, session.payment_intent),
    env.DB.prepare(`INSERT INTO commerce_purchases(provider, transaction_id, user_id, product_id, payment_reference, state)
      SELECT 'stripe', stripe_session_id, user_id, product_id, payment_intent_id,
        CASE state WHEN 'refunded' THEN 'refunded' WHEN 'disputed' THEN 'disputed' ELSE 'active' END
      FROM commerce_checkouts WHERE request_id = ?1
      ON CONFLICT(provider, transaction_id) DO NOTHING`).bind(order.request_id),
  ]);
}

async function updateStripeRefundOrDispute(env, event, fetcher) {
  let paymentIntent;
  let state;
  if (event.type === 'charge.refunded') {
    const chargeId = event.data?.object?.id;
    if (!/^ch_[A-Za-z0-9]+$/.test(chargeId || '')) throw new CommerceError('invalid_event');
    const charge = await stripeRequest(env, `charges/${chargeId}`, {}, fetcher);
    if (!charge.refunded || charge.amount_refunded < charge.amount) return; // Partial support refunds keep the bundle.
    paymentIntent = charge.payment_intent;
    state = 'refunded';
  } else {
    const disputeId = event.data?.object?.id;
    if (!/^dp_[A-Za-z0-9]+$/.test(disputeId || '')) throw new CommerceError('invalid_event');
    const dispute = await stripeRequest(env, `disputes/${disputeId}`, {}, fetcher);
    paymentIntent = dispute.payment_intent;
    state = dispute.status === 'won' ? 'active' : 'disputed';
  }
  if (!/^pi_[A-Za-z0-9]+$/.test(paymentIntent || '')) throw new CommerceError('invalid_event');
  const intent = await stripeRequest(env, `payment_intents/${paymentIntent}`, {}, fetcher);
  const orderId = intent.metadata?.order_id;
  const order = await env.DB.prepare('SELECT * FROM commerce_checkouts WHERE request_id = ?1').bind(orderId || '').first();
  if (!order || order.user_id !== intent.metadata?.user_id || order.product_id !== intent.metadata?.product_id ||
      intent.livemode !== (env.COMMERCE_MODE === 'live')) throw new CommerceError('invalid_event');
  // Preserve legitimate refund/dispute bookkeeping, never restore access on
  // a dispute win after account retirement.
  if (state === 'active' && await isSubjectRetired(env, order.user_id)) return;
  await env.DB.batch([
    env.DB.prepare(`UPDATE commerce_checkouts SET state = CASE WHEN state = 'refunded' THEN 'refunded'
      WHEN ?2 = 'active' AND state = 'disputed' THEN 'paid' WHEN ?2 = 'active' THEN state ELSE ?2 END,
      payment_intent_id = ?3, updated_at = datetime('now') WHERE request_id = ?1`)
      .bind(orderId, state, paymentIntent),
    env.DB.prepare(`UPDATE commerce_purchases SET state = CASE WHEN state = 'refunded' THEN 'refunded'
      WHEN ?2 = 'active' AND state = 'disputed' THEN 'active' WHEN ?2 = 'active' THEN state ELSE ?2 END,
      updated_at = datetime('now') WHERE provider = 'stripe' AND payment_reference = ?1`)
      .bind(paymentIntent, state),
  ]);
}

async function stripeWebhook(env, request, fetcher) {
  stripeConfig(env);
  const raw = await boundedText(request);
  await verifyStripeSignature(raw, request.headers.get('Stripe-Signature'), env.STRIPE_WEBHOOK_SECRET);
  let event;
  try { event = JSON.parse(raw); } catch { throw new CommerceError('invalid_event'); }
  if (!/^evt_[A-Za-z0-9]+$/.test(event.id || '') || event.livemode !== (env.COMMERCE_MODE === 'live')) {
    throw new CommerceError('invalid_event');
  }
  const seen = await env.DB.prepare('SELECT event_id FROM commerce_events WHERE provider = \'stripe\' AND event_id = ?1')
    .bind(event.id).first();
  if (seen) return { received: true, duplicate: true };
  if (['checkout.session.completed', 'checkout.session.async_payment_succeeded'].includes(event.type)) {
    await grantStripeSession(env, event, fetcher);
  } else if (['charge.refunded', 'charge.dispute.created', 'charge.dispute.closed'].includes(event.type)) {
    await updateStripeRefundOrDispute(env, event, fetcher);
  }
  // Record only after durable fulfillment. Lost replies / concurrent events can
  // repeat safely; transaction and event primary keys make fulfillment singular.
  await env.DB.prepare('INSERT INTO commerce_events(provider, event_id) VALUES (\'stripe\', ?1) ON CONFLICT DO NOTHING')
    .bind(event.id).run();
  return { received: true };
}

/** Return null for unrelated routes. Authenticate with the host's verified JWT
 * helper; never accept user IDs from request bodies or unsigned cloud saves. */
export async function handleCommerce(request, env, authenticate, { fetcher = fetch } = {}) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith(`${ROOT}/`)) return null;
  try {
    const nativeAuth = await handleNativeAuth(request, env, authenticate, { fetcher });
    if (nativeAuth) return nativeAuth;
    if (request.method === 'OPTIONS') {
      requireOrigin(env, request);
      return new Response(null, { status: 204, headers: corsHeaders(env, request) });
    }
    requireEnabled(env);
    const notification = await handleNativeNotification(request, env, persistNativePurchase, { fetcher });
    if (notification) return json(env, request, notification);
    if (path === `${ROOT}/stripe/webhook` && request.method === 'POST') {
      return json(env, request, await stripeWebhook(env, request, fetcher));
    }
    requireOrigin(env, request);
    const claims = await authenticate(env, request);
    if (!claims || typeof claims.sub !== 'string' || !claims.sub) throw new CommerceError('unauthorized', 401);
    await requireActiveSubject(env, claims.sub);
    if (path === `${ROOT}/catalog` && request.method === 'GET') {
      return json(env, request, { version: 1, products: PRODUCTS, disclosure: DISCLOSURE,
        mode: env.COMMERCE_MODE,
        native_purchase_configured: {
          apple: nativeSalesConfigured(env, 'apple'),
          google: nativeSalesConfigured(env, 'google'),
        },
        native_verification_configured: {
          apple: nativeVerificationConfigured(env, 'apple'),
          google: nativeVerificationConfigured(env, 'google'),
        },
        web_checkout_configured: Boolean(env.STRIPE_SECRET_KEY && env.COMMERCE_STRIPE_PRICES &&
          env.STRIPE_WEBHOOK_SECRET && env.COMMERCE_SUCCESS_URL && env.COMMERCE_CANCEL_URL) });
    }
    if (path === `${ROOT}/entitlements` && request.method === 'GET') {
      return json(env, request, await entitlements(env, claims.sub));
    }
    if (path === `${ROOT}/account` && request.method === 'GET') {
      return json(env, request, { bindings: await storeAccount(env, claims.sub) });
    }
    if (path === `${ROOT}/prepare-native-purchase` && request.method === 'POST') {
      return json(env, request, await prepareNativePurchase(env, request, claims.sub));
    }
    if (path === `${ROOT}/checkout` && request.method === 'POST') {
      if (!env.STRIPE_WEBHOOK_SECRET) throw new CommerceError('checkout_unavailable', 503);
      return json(env, request, await checkout(env, request, claims.sub, fetcher));
    }
    if (path === `${ROOT}/verify` && request.method === 'POST') {
      return json(env, request, await verifyNative(env, request, claims.sub, fetcher));
    }
    return json(env, request, { error: 'not_found' }, 404);
  } catch (error) {
    if (error instanceof CommerceError) return json(env, request, { error: error.code }, error.status);
    // Provider credentials, raw receipts and database errors never reach clients.
    return json(env, request, { error: 'commerce_unavailable' }, 503);
  }
}
