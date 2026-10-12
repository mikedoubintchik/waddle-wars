import { PRODUCTS } from './commerce_catalog.mjs';
import { CommerceError, boundedText, sha256, queryGooglePurchase,
  verifyGooglePurchase, verifyApplePurchase } from './commerce_providers.mjs';

const bytes = (value) => Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')),
  (character) => character.charCodeAt(0));
const decoder = new TextDecoder();

async function body(request) {
  try {
    const parsed = JSON.parse(await boundedText(request));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error();
    return parsed;
  } catch (error) {
    if (error instanceof CommerceError) throw error;
    throw new CommerceError('invalid_notification');
  }
}

export async function verifyGooglePush(env, request, fetcher = fetch) {
  if (!env.GOOGLE_RTDN_AUDIENCE || !env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL || !env.GOOGLE_RTDN_SUBSCRIPTION) {
    throw new CommerceError('store_notifications_unavailable', 503);
  }
  const authorization = request.headers.get('Authorization') || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token || token.length > 16384) throw new CommerceError('unauthorized_notification', 401);
  try {
    const segments = token.split('.');
    if (segments.length !== 3 || segments.some((segment) => !segment)) throw new Error();
    const [head, payload, signature] = segments;
    const header = JSON.parse(decoder.decode(bytes(head)));
    const claims = JSON.parse(decoder.decode(bytes(payload)));
    const now = Math.floor(Date.now() / 1000);
    if (header.alg !== 'RS256' || typeof header.kid !== 'string' ||
        !['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss) ||
        claims.aud !== env.GOOGLE_RTDN_AUDIENCE || claims.email !== env.GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL ||
        claims.email_verified !== true || !Number.isFinite(claims.exp) || claims.exp <= now ||
        !Number.isFinite(claims.iat) || claims.iat > now + 30 || now - claims.iat > 3900) throw new Error();
    const reply = await fetcher('https://www.googleapis.com/oauth2/v3/certs');
    if (!reply.ok) throw new CommerceError('store_notifications_unavailable', 503);
    const jwk = (await reply.json()).keys?.find((key) => key.kid === header.kid && key.kty === 'RSA');
    if (!jwk) throw new Error();
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    if (!await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, bytes(signature), new TextEncoder().encode(`${head}.${payload}`))) throw new Error();
  } catch (error) {
    if (error instanceof CommerceError) throw error;
    throw new CommerceError('unauthorized_notification', 401);
  }
}

async function recordRevocation(env, provider, transactionId, eventId, signedAt = 0) {
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO commerce_revocations(provider, transaction_id, provider_signed_at)
      SELECT ?1, ?2, ?3 WHERE NOT EXISTS(SELECT 1 FROM commerce_purchases
        WHERE provider = ?1 AND transaction_id = ?2 AND provider_signed_at > ?3)
      ON CONFLICT(provider, transaction_id) DO UPDATE SET provider_signed_at = MAX(provider_signed_at, excluded.provider_signed_at)`)
      .bind(provider, transactionId, signedAt),
    env.DB.prepare(`UPDATE commerce_purchases SET state = 'refunded', provider_signed_at = ?3, updated_at = datetime('now')
      WHERE provider = ?1 AND transaction_id = ?2 AND provider_signed_at <= ?3`)
      .bind(provider, transactionId, signedAt),
    env.DB.prepare('INSERT INTO commerce_events(provider, event_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING')
      .bind(provider, eventId),
  ]);
}

async function googleNotification(env, request, persist, fetcher) {
  await verifyGooglePush(env, request, fetcher);
  const outer = await body(request);
  if (outer.subscription !== env.GOOGLE_RTDN_SUBSCRIPTION || !/^\d{1,64}$/.test(outer.message?.messageId || '') ||
      typeof outer.message.data !== 'string' || outer.message.data.length > 16384) throw new CommerceError('invalid_notification');
  const eventId = outer.message.messageId;
  const seen = await env.DB.prepare('SELECT event_id FROM commerce_events WHERE provider = \'google\' AND event_id = ?1').bind(eventId).first();
  if (seen) return { received: true, duplicate: true };
  let notice;
  try { notice = JSON.parse(decoder.decode(bytes(outer.message.data))); } catch { throw new CommerceError('invalid_notification'); }
  if (notice.packageName !== env.GOOGLE_PLAY_PACKAGE_ID) throw new CommerceError('invalid_notification');
  if (notice.testNotification) return { received: true, test: true };
  const notification = notice.oneTimeProductNotification || notice.voidedPurchaseNotification;
  if (!notification) return { received: true, ignored: true };
  const token = notification.purchaseToken;
  if (typeof token !== 'string' || token.length < 10 || token.length > 4096) throw new CommerceError('invalid_notification');
  const transactionId = await sha256(token);
  if (notice.voidedPurchaseNotification && notification.productType === 2 && notification.refundType === 1) {
    // A signed, allowlisted Pub/Sub full void event is authoritative. It also
    // carries a purchase token before client fulfillment; persist the tombstone.
    await recordRevocation(env, 'google', transactionId, eventId);
    return { received: true };
  }
  const context = await queryGooglePurchase(env, token, fetcher);
  const providerPurchase = context.purchase;
  const product = PRODUCTS.find((item) => item.google_product_id === providerPurchase.productLineItem?.[0]?.productId);
  if (!product || providerPurchase.productLineItem?.length !== 1 ||
      (notification.sku && notification.sku !== product.google_product_id)) throw new CommerceError('invalid_notification');
  const account = await env.DB.prepare('SELECT user_id FROM commerce_store_accounts WHERE google_account_id = ?1')
    .bind(providerPurchase.obfuscatedExternalAccountId || '').first();
  if (!account) throw new CommerceError('unknown_store_account', 409);
  // Revalidation makes notification ordering immaterial and enforces the same
  // app-account/product/test/quantity checks as the client verification path.
  const verified = await verifyGooglePurchase(env, product, account.user_id, token, fetcher);
  await persist(env, verified);
  await env.DB.prepare('INSERT INTO commerce_events(provider, event_id) VALUES (\'google\', ?1) ON CONFLICT DO NOTHING').bind(eventId).run();
  return { received: true };
}

async function appleNotification(env, request, persist) {
  if (!env.APPLE_RECEIPT_VERIFIER || !env.APPLE_BUNDLE_ID) throw new CommerceError('store_notifications_unavailable', 503);
  const raw = await body(request);
  if (typeof raw.signedPayload !== 'string' || raw.signedPayload.length > 60000) throw new CommerceError('invalid_notification');
  const reply = await env.APPLE_RECEIPT_VERIFIER.fetch(new Request('https://apple-verifier.internal/notification', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ signed_payload: raw.signedPayload }),
  }));
  if (!reply.ok) throw new CommerceError('invalid_notification', reply.status === 400 ? 400 : 503);
  const verified = await reply.json();
  const eventId = verified.notification?.notificationUUID;
  if (verified.verified !== true || typeof eventId !== 'string' || eventId.length > 128) throw new CommerceError('invalid_notification');
  const seen = await env.DB.prepare('SELECT event_id FROM commerce_events WHERE provider = \'apple\' AND event_id = ?1').bind(eventId).first();
  if (seen) return { received: true, duplicate: true };
  const transaction = verified.transaction;
  if (!transaction) return { received: true, ignored: true };
  const product = PRODUCTS.find((item) => item.apple_product_id === transaction.productId);
  if (!product || transaction.bundleId !== env.APPLE_BUNDLE_ID || transaction.type !== 'Non-Consumable' || transaction.quantity !== 1 ||
      !Number.isSafeInteger(transaction.signedDate) || transaction.signedDate <= 0 || transaction.signedDate > Date.now() + 30000 ||
      transaction.environment !== (env.COMMERCE_MODE === 'live' ? 'Production' : 'Sandbox')) throw new CommerceError('invalid_notification');
  const transactionId = transaction.originalTransactionId || transaction.transactionId;
  if (typeof transactionId !== 'string' || !/^\d{8,40}$/.test(transactionId)) throw new CommerceError('invalid_notification');
  const account = await env.DB.prepare('SELECT user_id FROM commerce_store_accounts WHERE apple_account_token = ?1')
    .bind(transaction.appAccountToken?.toLowerCase() || '').first();
  if (!account) {
    if (transaction.revocationDate) {
      await recordRevocation(env, 'apple', transactionId, eventId, transaction.signedDate);
      return { received: true };
    }
    throw new CommerceError('unknown_store_account', 409);
  }
  const purchase = await verifyApplePurchase(env, product, account.user_id, transaction.transactionId);
  if (purchase.transaction_id !== transactionId) throw new CommerceError('invalid_notification');
  // Apple can notify before Get Transaction Info has caught up. Do not consume
  // this event until a certificate-verified snapshot is at least as recent.
  if (purchase.provider_signed_at < transaction.signedDate) throw new CommerceError('store_state_not_current', 503);
  if (purchase.state === 'refunded') await recordRevocation(env, 'apple', transactionId, eventId, purchase.provider_signed_at);
  else {
    await persist(env, purchase, { appleRefundReversal: verified.notification.notificationType === 'REFUND_REVERSED' });
    await env.DB.prepare('INSERT INTO commerce_events(provider, event_id) VALUES (\'apple\', ?1) ON CONFLICT DO NOTHING').bind(eventId).run();
  }
  return { received: true };
}

export async function handleNativeNotification(request, env, persist, { fetcher = fetch } = {}) {
  if (request.method !== 'POST') return null;
  const path = new URL(request.url).pathname;
  if (path === '/api/commerce/google/notifications') return googleNotification(env, request, persist, fetcher);
  if (path === '/api/commerce/apple/notifications') return appleNotification(env, request, persist);
  return null;
}
