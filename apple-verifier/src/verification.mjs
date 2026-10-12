import { Buffer } from 'node:buffer';

// Apple's dependency initializes a cryptographic RNG when first imported.
// Workers allow that only inside a request, not at isolate/module startup.
// Keep the official implementation intact and initialize it on demand.
let libraryPromise;
const appleLibrary = () => libraryPromise ??= import('@apple/app-store-server-library');

export class VerificationError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

export function configuration(env) {
  if (env.APPLE_VERIFIER_ENABLED !== 'true' ||
      !['test', 'live'].includes(env.COMMERCE_MODE) ||
      env.APPLE_BUNDLE_ID !== 'com.blubberandbyte.waddlewars' ||
      !/^[A-Z0-9]{10}$/.test(env.APPLE_KEY_ID || '') ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(env.APPLE_ISSUER_ID || '') ||
      !env.APPLE_PRIVATE_KEY?.includes('-----BEGIN PRIVATE KEY-----')) {
    throw new VerificationError('verifier_unavailable', 503);
  }
  const appAppleId = Number(env.APPLE_APP_ID);
  if (env.COMMERCE_MODE === 'live' &&
      (!Number.isSafeInteger(appAppleId) || appAppleId <= 0)) {
    throw new VerificationError('verifier_unavailable', 503);
  }
  return {
    bundleId: env.APPLE_BUNDLE_ID,
    environment: env.COMMERCE_MODE === 'live' ? 'Production' : 'Sandbox',
    appAppleId: env.COMMERCE_MODE === 'live' ? appAppleId : undefined,
  };
}

export async function appleServices(env, roots) {
  const config = configuration(env);
  if (roots.length !== 3) throw new VerificationError('verifier_unavailable', 503);
  const { AppStoreServerAPIClient, SignedDataVerifier } = await appleLibrary();
  return {
    config,
    api: new AppStoreServerAPIClient(env.APPLE_PRIVATE_KEY, env.APPLE_KEY_ID,
      env.APPLE_ISSUER_ID, config.bundleId, config.environment),
    // Online revocation checks remain enabled. A failed chain or unavailable
    // validation service must not turn a purchase into an entitlement.
    verifier: new SignedDataVerifier(roots.map((root) => Buffer.from(root)),
      true, config.environment, config.bundleId, config.appAppleId),
  };
}

async function boundedJSON(request, kind) {
  const limit = kind === 'notification' ? 65536 : 2048;
  if (!request.headers.get('content-type')?.startsWith('application/json')) {
    throw new VerificationError('invalid_content_type', 415);
  }
  if (Number(request.headers.get('content-length') || 0) > limit) {
    throw new VerificationError('body_too_large', 413);
  }
  const reader = request.body?.getReader();
  if (!reader) throw new VerificationError('invalid_request');
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      throw new VerificationError('body_too_large', 413);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    const valid = kind === 'notification'
      ? typeof body?.signed_payload === 'string' && body.signed_payload.length > 0
      : typeof body?.transaction_id === 'string' && /^\d{8,40}$/.test(body.transaction_id);
    if (!body || Array.isArray(body) || Object.keys(body).length !== 1 || !valid) {
      throw new Error('shape');
    }
    return body;
  } catch {
    throw new VerificationError('invalid_request');
  }
}

const reply = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});

async function verifiedPayload(action) {
  try {
    return await action();
  } catch (error) {
    const { VerificationStatus } = await appleLibrary();
    if (error?.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
      throw new VerificationError('verifier_unavailable', 503);
    }
    throw new VerificationError('unverified_transaction');
  }
}

export function createHandler(serviceFactory) {
  return async function handle(request, env) {
    try {
      const url = new URL(request.url);
      if (url.hostname !== 'apple-verifier.internal' ||
          !['/verify', '/notification'].includes(url.pathname)) {
        return reply({ error: 'not_found' }, 404);
      }
      if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
      // Browsers cannot use this private service as an arbitrary receipt oracle.
      if (request.headers.has('Origin')) return reply({ error: 'forbidden' }, 403);
      configuration(env);
      const kind = url.pathname === '/notification' ? 'notification' : 'transaction';
      const body = await boundedJSON(request, kind);
      const { api, verifier, config } = await serviceFactory(env);
      if (kind === 'notification') {
        const notification = await verifiedPayload(() =>
          verifier.verifyAndDecodeNotification(body.signed_payload));
        let transaction = null;
        if (notification.data?.signedTransactionInfo) {
          transaction = await verifiedPayload(() =>
            verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo));
          if (transaction.bundleId !== config.bundleId || transaction.environment !== config.environment) {
            throw new VerificationError('transaction_mismatch');
          }
        }
        return reply({ verified: true, notification, transaction });
      }
      const transactionId = body.transaction_id;
      // Client-supplied transaction contents and success flags are never trusted.
      const response = await api.getTransactionInfo(transactionId);
      if (typeof response.signedTransactionInfo !== 'string') {
        throw new VerificationError('invalid_provider_response', 502);
      }
      const transaction = await verifiedPayload(() =>
        verifier.verifyAndDecodeTransaction(response.signedTransactionInfo));
      if (transaction.transactionId !== transactionId || transaction.bundleId !== config.bundleId ||
          transaction.environment !== config.environment) {
        throw new VerificationError('transaction_mismatch');
      }
      return reply({ verified: true, transaction });
    } catch (error) {
      if (error instanceof VerificationError) return reply({ error: error.code }, error.status);
      // Provider exceptions can contain signed receipts or credential details.
      // Keep those out of responses and logs.
      return reply({ error: 'verifier_unavailable' }, 503);
    }
  };
}
