const encoder = new TextEncoder();
const bytesToB64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const b64url = (bytes) => bytesToB64(bytes).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

export class CommerceError extends Error {
  constructor(code, status = 400) { super(code); this.code = code; this.status = status; }
}

export async function sha256(value) {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export async function accountBinding(userId) {
  const hex = await sha256(`waddle-wars:store-account:v1:${userId}`);
  // A stable UUID supplied to StoreKit's appAccountToken. The same opaque
  // account binding is supplied to Play Billing's obfuscated account ID.
  const uuid = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-${
    ((parseInt(hex[16], 16) & 3) | 8).toString(16)}${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
  return { apple: uuid, google: hex };
}

export async function boundedText(request, limit = 65536) {
  const declared = request.headers.get('content-length');
  if (declared && Number(declared) > limit) throw new CommerceError('body_too_large', 413);
  if (!request.body) return '';
  const reader = request.body.getReader();
  let size = 0;
  const chunks = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) { await reader.cancel(); throw new CommerceError('body_too_large', 413); }
    chunks.push(value);
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder('utf-8', { fatal: true }).decode(result);
}

export async function verifyStripeSignature(raw, signature, secret, now = Date.now()) {
  if (!secret || !signature) throw new CommerceError('invalid_signature', 400);
  const fields = signature.split(',').map((field) => field.trim().split('='));
  const timestamps = fields.filter(([name]) => name === 't').map(([, value]) => value);
  const signatures = fields.filter(([name]) => name === 'v1').map(([, value]) => value);
  if (timestamps.length !== 1 || !/^\d+$/.test(timestamps[0]) ||
      Math.abs(now / 1000 - Number(timestamps[0])) > 300) {
    throw new CommerceError('invalid_signature', 400);
  }
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  const message = encoder.encode(`${timestamps[0]}.${raw}`);
  for (const signatureHex of signatures) {
    if (!/^[0-9a-f]{64}$/.test(signatureHex)) continue;
    const bytes = Uint8Array.from(signatureHex.match(/../g), (value) => parseInt(value, 16));
    if (await crypto.subtle.verify('HMAC', key, bytes, message)) return;
  }
  throw new CommerceError('invalid_signature', 400);
}

export function stripeConfig(env) {
  const mode = env.COMMERCE_MODE;
  if (!['test', 'live'].includes(mode) || !env.STRIPE_SECRET_KEY?.startsWith(
    mode === 'live' ? 'sk_live_' : 'sk_test_')) throw new CommerceError('stripe_unavailable', 503);
  let prices;
  try { prices = JSON.parse(env.COMMERCE_STRIPE_PRICES || '{}'); } catch { prices = {}; }
  return { mode, prices };
}

export async function stripeRequest(env, path, init = {}, fetcher = fetch) {
  stripeConfig(env);
  const response = await fetcher(`https://api.stripe.com/v1/${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      ...(init.body ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}), ...init.headers },
  });
  if (!response.ok) throw new CommerceError('payment_provider_unavailable', 503);
  const value = await response.json();
  if (!value || typeof value !== 'object') throw new CommerceError('invalid_provider_response', 502);
  return value;
}

export function validateStripePrice(price, product, priceId, mode) {
  if (price.id !== priceId || price.active !== true || price.type !== 'one_time' ||
      price.livemode !== (mode === 'live') || price.currency !== product.currency ||
      price.unit_amount !== product.price_minor) throw new CommerceError('price_configuration_mismatch', 503);
}

function pkcs8Bytes(pem) {
  if (typeof pem !== 'string') throw new CommerceError('store_verifier_unavailable', 503);
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

async function googleAccessToken(env, fetcher) {
  let account;
  try { account = JSON.parse(env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON); } catch {
    throw new CommerceError('store_verifier_unavailable', 503);
  }
  if (!account.client_email || !account.private_key) throw new CommerceError('store_verifier_unavailable', 503);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const payload = b64url(encoder.encode(JSON.stringify({ iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher', aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600 })));
  const key = await crypto.subtle.importKey('pkcs8', pkcs8Bytes(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(`${header}.${payload}`));
  const response = await fetcher('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${payload}.${b64url(signature)}` }),
  });
  if (!response.ok) throw new CommerceError('store_verifier_unavailable', 503);
  const result = await response.json();
  if (typeof result.access_token !== 'string') throw new CommerceError('store_verifier_unavailable', 503);
  return result.access_token;
}

export async function queryGooglePurchase(env, token, fetcher = fetch) {
  if (!env.GOOGLE_PLAY_PACKAGE_ID || typeof token !== 'string' || token.length < 10 || token.length > 4096) {
    throw new CommerceError('invalid_purchase');
  }
  const accessToken = await googleAccessToken(env, fetcher);
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${
    encodeURIComponent(env.GOOGLE_PLAY_PACKAGE_ID)}/purchases`;
  const response = await fetcher(`${base}/productsv2/tokens/${encodeURIComponent(token)}`,
    { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new CommerceError('purchase_verification_failed', response.status === 404 ? 400 : 503);
  const purchase = await response.json();
  return { purchase, accessToken, base };
}

export async function verifyGooglePurchase(env, product, userId, token, fetcher = fetch) {
  const { purchase, accessToken, base } = await queryGooglePurchase(env, token, fetcher);
  const binding = await accountBinding(userId);
  const offer = purchase.productLineItem?.[0]?.productOfferDetails;
  const isTestPurchase = Object.hasOwn(purchase, 'testPurchaseContext');
  // The v2 API sets this context only for test purchases. Do not infer test
  // status from the legacy v1 purchaseType field or client-supplied metadata.
  if (!['test', 'live'].includes(env.COMMERCE_MODE) ||
      (isTestPurchase && (!purchase.testPurchaseContext ||
        typeof purchase.testPurchaseContext !== 'object' || Array.isArray(purchase.testPurchaseContext) ||
        purchase.testPurchaseContext.fopType !== 'TEST')) ||
      isTestPurchase !== (env.COMMERCE_MODE === 'test')) throw new CommerceError('invalid_purchase');
  // Google can expose rental and permanent buy options for one product ID.
  // Cosmetic bundles require permanent ownership, never a rental entitlement.
  if (purchase.obfuscatedExternalAccountId !== binding.google ||
      purchase.productLineItem?.length !== 1 ||
      purchase.productLineItem[0].productId !== product.google_product_id ||
      offer?.quantity !== 1 || Object.hasOwn(offer, 'rentOfferDetails')) throw new CommerceError('invalid_purchase');
  const state = purchase.purchaseStateContext?.purchaseState;
  if (state === 'PENDING') throw new CommerceError('purchase_pending', 409);
  if (!['PURCHASED', 'CANCELLED'].includes(state)) throw new CommerceError('invalid_purchase');
  const refunded = state === 'CANCELLED' || offer.refundableQuantity === 0;
  return {
    provider: 'google', transaction_id: await sha256(token), user_id: userId, product_id: product.id,
    payment_reference: purchase.orderId || null, state: refunded ? 'refunded' : 'active',
    acknowledge: async () => {
      if (refunded || purchase.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED') return;
      const result = await fetcher(`${base}/products/${encodeURIComponent(product.google_product_id)}/tokens/${
        encodeURIComponent(token)}:acknowledge`, { method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: '{}' });
      if (!result.ok) throw new CommerceError('purchase_acknowledgement_pending', 503);
    },
  };
}

// Cloudflare's Web Crypto API does not validate Apple's x5c certificate chain.
// A private service binding must use Apple's official SignedDataVerifier and
// trusted Apple roots. Missing binding is a launch gate, never a success stub.
export async function verifyApplePurchase(env, product, userId, transactionId) {
  if (!env.APPLE_RECEIPT_VERIFIER || !env.APPLE_BUNDLE_ID) throw new CommerceError('store_verifier_unavailable', 503);
  if (typeof transactionId !== 'string' || !/^\d{8,40}$/.test(transactionId)) throw new CommerceError('invalid_purchase');
  const response = await env.APPLE_RECEIPT_VERIFIER.fetch(new Request('https://apple-verifier.internal/verify', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ transaction_id: transactionId }),
  }));
  if (!response.ok) throw new CommerceError('purchase_verification_failed', response.status === 400 ? 400 : 503);
  const verified = await response.json();
  const binding = await accountBinding(userId);
  const transaction = verified.transaction;
  if (verified.verified !== true || !transaction || transaction.bundleId !== env.APPLE_BUNDLE_ID ||
      transaction.productId !== product.apple_product_id || transaction.type !== 'Non-Consumable' ||
      transaction.quantity !== 1 || transaction.transactionId !== transactionId ||
      !/^\d{8,40}$/.test(transaction.originalTransactionId || transaction.transactionId) ||
      !Number.isSafeInteger(transaction.signedDate) || transaction.signedDate <= 0 ||
      transaction.signedDate > Date.now() + 30000 ||
      transaction.appAccountToken?.toLowerCase() !== binding.apple ||
      transaction.environment !== (env.COMMERCE_MODE === 'live' ? 'Production' : 'Sandbox')) {
    throw new CommerceError('invalid_purchase');
  }
  return { provider: 'apple', transaction_id: transaction.originalTransactionId || transaction.transactionId,
    user_id: userId, product_id: product.id, payment_reference: transaction.transactionId,
    provider_signed_at: transaction.signedDate,
    state: transaction.revocationDate ? 'refunded' : 'active' };
}
