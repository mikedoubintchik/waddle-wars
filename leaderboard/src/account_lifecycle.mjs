// Account retirement is independent of payment refunds and their reversals.
// This module does not choose financial/log/backup retention periods. Those
// disclosures and final erasure workflow remain prerequisites for launch.
import { CommerceError, boundedText, sha256 } from './commerce_providers.mjs';
import { providerSubject } from './native_accounts_policy.mjs';

const SUBJECT = /^(?:clerk_live:)?[A-Za-z0-9_-]{1,256}$/;
const RECEIPT = /^[0-9a-f]{64}$/;
const RECEIPT_HEADER = 'X-Waddle-Deletion-Receipt';
const ROOT = '/api/account';

function subject(value) {
  if (typeof value !== 'string' || !SUBJECT.test(value)) throw new CommerceError('unauthorized', 401);
  return value;
}

export async function isSubjectRetired(env, userId) {
  subject(userId);
  return Boolean(await env.DB.prepare('SELECT user_id FROM account_retirements WHERE user_id = ?1')
    .bind(userId).first());
}

export async function requireActiveSubject(env, userId) {
  if (await isSubjectRetired(env, userId)) throw new CommerceError('account_retired', 403);
}

export async function retireSubjectData(env, userId, recoveryReceipt = undefined) {
  subject(userId);
  const receiptStatements = [];
  if (recoveryReceipt !== undefined) {
    if (typeof recoveryReceipt !== 'string' || !RECEIPT.test(recoveryReceipt)) {
      throw new CommerceError('invalid_deletion_receipt', 400);
    }
    const digest = await sha256(recoveryReceipt);
    // The migration's registration trigger checks ownership even on a conflict.
    // Its deferred FK permits registration before the marker in this one batch.
    receiptStatements.push(env.DB.prepare(`INSERT INTO account_deletion_receipts(receipt_hash, user_id)
      VALUES (?1, ?2) ON CONFLICT(receipt_hash) DO NOTHING`).bind(digest, userId));
  }
  // D1 batch is atomic. The marker and database triggers fence even writes
  // whose JWT/provider verification started before this transaction.
  try {
    await env.DB.batch([
      ...receiptStatements,
      env.DB.prepare('INSERT INTO account_retirements(user_id) VALUES (?1) ON CONFLICT DO NOTHING').bind(userId),
      ...['scores', 'profiles', 'saves', 'commerce_native_auth_sessions', 'commerce_native_auth_requests']
        .map((table) => env.DB.prepare(`DELETE FROM ${table} WHERE user_id = ?1`).bind(userId)),
    ]);
  } catch (error) {
    if (String(error?.message || '').includes('deletion_receipt_conflict')) {
      throw new CommerceError('deletion_receipt_conflict', 409);
    }
    throw error;
  }
  // Preserve financial proof and store mappings until lawful retention and
  // post-deletion restoration are specified. Active auth/entitlement reads are
  // forbidden; these retained rows cannot reactivate the retired subject.
  return env.DB.prepare('SELECT retired_at, clerk_deleted_at FROM account_retirements WHERE user_id = ?1')
    .bind(userId).first();
}

function headers(env, request) {
  const origin = request.headers.get('Origin');
  const allowed = String(env.COMMERCE_ALLOWED_ORIGINS || '').split(',').map((item) => item.trim()).filter(Boolean);
  return { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', Vary: 'Origin',
    ...(origin && allowed.includes(origin) ? { 'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': `Authorization, Content-Type, ${RECEIPT_HEADER}` } : {}) };
}

function reply(env, request, body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: headers(env, request) });
}

function requireProviderConfiguration(env) {
  let issuer;
  try { issuer = new URL(env.CLERK_ISSUER); } catch { /* Fail closed below. */ }
  if (env.ACCOUNT_DELETION_ENABLED !== 'true' || typeof env.CLERK_SECRET_KEY !== 'string' || !env.CLERK_SECRET_KEY ||
      !issuer || issuer.protocol !== 'https:' || issuer.origin !== env.CLERK_ISSUER) {
    throw new CommerceError('account_deletion_unavailable', 503);
  }
}

function requireStatusConfiguration(env, request) {
  if (env.ACCOUNT_DELETION_ENABLED !== 'true' || typeof env.ACCOUNT_DELETION_LIMITER?.limit !== 'function') {
    throw new CommerceError('account_deletion_unavailable', 503);
  }
  const origin = request.headers.get('Origin');
  const allowed = String(env.COMMERCE_ALLOWED_ORIGINS || '').split(',').map((item) => item.trim()).filter(Boolean);
  if (origin && !allowed.includes(origin)) throw new CommerceError('origin_not_allowed', 403);
}

function requireConfiguration(env, request) {
  requireProviderConfiguration(env);
  requireStatusConfiguration(env, request);
}

function status(row) {
  if (!row) return { requested: false, deletion_complete: false };
  return { requested: true, account_data_erased: true,
    identity_deleted: Boolean(row.clerk_deleted_at),
    state: row.clerk_deleted_at ? 'identity_deleted_retention_pending' : 'identity_pending',
    deletion_complete: false, retention_review_required: true };
}

async function deleteClerkIdentity(env, userId, fetcher) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const providerUserId = providerSubject(env, userId);
    const url = `https://api.clerk.com/v1/users/${encodeURIComponent(providerUserId)}`;
    const authorization = { Authorization: `Bearer ${env.CLERK_SECRET_KEY}` };
    // A first 404 could mean a key for the wrong Clerk instance, not erasure.
    // Bind an observed exact identity to the configured issuer/credential before
    // trusting later 404s after a lost delete reply. The digest never leaves DB
    // or appears in logs/responses, and rotating keys requires a fresh check.
    const binding = await sha256(JSON.stringify([env.CLERK_ISSUER, env.CLERK_SECRET_KEY]));
    const prior = await env.DB.prepare('SELECT clerk_identity_seen_at, clerk_binding_hash FROM account_retirements WHERE user_id = ?1')
      .bind(userId).first();
    if (!prior) return false;
    if (!prior.clerk_identity_seen_at || prior.clerk_binding_hash !== binding) {
      const identity = await fetcher(url, { headers: authorization, signal: controller.signal });
      if (!identity.ok || (await identity.json()).id !== providerUserId) return false;
      await env.DB.prepare("UPDATE account_retirements SET clerk_identity_seen_at = datetime('now'), clerk_binding_hash = ?2 WHERE user_id = ?1")
        .bind(userId, binding).run();
    }
    const result = await fetcher(url, {
      method: 'DELETE', headers: authorization,
      signal: controller.signal,
    });
    // A previously completed provider deletion is an idempotent success.
    if (!result.ok && result.status !== 404) return false;
    await env.DB.prepare("UPDATE account_retirements SET clerk_deleted_at = COALESCE(clerk_deleted_at, datetime('now')) WHERE user_id = ?1")
      .bind(userId).run();
    return true;
  } catch {
    // Do not log provider bodies, credentials, or claim the identity is gone.
    return false;
  } finally { clearTimeout(timer); }
}

// Pending identities are durable database work, not dependent on an expired
// device token. A configured scheduler can retry this bounded queue. Scheduling
// cadence and provider deployment are deliberately not enabled here.
export async function retryPendingIdentityDeletions(env, { fetcher = fetch, limit = 5 } = {}) {
  requireProviderConfiguration(env);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 5) throw new CommerceError('invalid_retry_limit');
  const native = env.ACCOUNT_SUBJECT_PREFIX === 'clerk_live:';
  const rows = await env.DB.prepare(native
    ? `SELECT user_id FROM account_retirements WHERE clerk_deleted_at IS NULL AND user_id LIKE 'clerk_live:%'
        ORDER BY COALESCE(last_identity_attempt_at, retired_at), user_id LIMIT ?1`
    : 'SELECT user_id FROM account_retirements WHERE clerk_deleted_at IS NULL ORDER BY retired_at, user_id LIMIT ?1')
    .bind(limit).all();
  let completed = 0;
  for (const row of rows.results) {
    // Rotate failures to the back so an unavailable identity cannot starve all
    // later requests. This field exists only in the native scoped deployment.
    if (native) await env.DB.prepare("UPDATE account_retirements SET last_identity_attempt_at = datetime('now') WHERE user_id = ?1").bind(row.user_id).run();
    if (await deleteClerkIdentity(env, row.user_id, fetcher)) completed++;
  }
  return { attempted: rows.results.length, identity_deleted: completed,
    pending: rows.results.length - completed, deletion_complete: false };
}

/** Raw verified JWT auth permits an idempotent retry after retirement. All
 * ordinary game routes instead require active-subject auth. Production remains
 * disabled until provider, UI, public page and retention acceptance are done. */
export async function handleAccountLifecycle(request, env, authenticate, { fetcher = fetch } = {}) {
  const url = new URL(request.url);
  const path = url.pathname;
  const receiptRoute = path === `${ROOT}/deletion/receipt`;
  if (![`${ROOT}/delete`, `${ROOT}/deletion`, `${ROOT}/deletion/receipt`].includes(path)) return null;
  try {
    if (receiptRoute) {
      // This capability authorizes only a minimal status read, never account
      // access, deletion, provider retries, refunds, restores, or fence release.
      requireStatusConfiguration(env, request);
      if (url.search || request.headers.has('Authorization') || request.headers.has('Proxy-Authorization')) {
        throw new CommerceError('invalid_deletion_receipt_request', 400);
      }
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(env, request) });
      if (request.method !== 'GET') throw new CommerceError('not_found', 404);
      // Cloudflare supplies this address; absent/malformed values share a bucket.
      // Do not key on attacker-rotatable receipt tokens or put them in limiter keys.
      const address = request.headers.get('CF-Connecting-IP');
      const bucket = address && /^[0-9a-fA-F:.]{1,64}$/.test(address) ? address : 'unknown';
      const limited = await env.ACCOUNT_DELETION_LIMITER.limit({ key: `account-deletion-receipt:${bucket}` });
      if (limited?.success !== true) throw new CommerceError('account_deletion_rate_limited', 429);
      const receipt = request.headers.get(RECEIPT_HEADER);
      if (typeof receipt !== 'string' || !RECEIPT.test(receipt)) throw new CommerceError('invalid_deletion_receipt', 400);
      const digest = await sha256(receipt);
      const row = await env.DB.prepare(`SELECT retirement.clerk_deleted_at FROM account_deletion_receipts AS receipt
        JOIN account_retirements AS retirement ON retirement.user_id = receipt.user_id
        WHERE receipt.receipt_hash = ?1`).bind(digest).first();
      if (!row) throw new CommerceError('status_unavailable', 404);
      return reply(env, request, status(row));
    }
    requireConfiguration(env, request);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers(env, request) });
    const claims = await authenticate(env, request);
    const userId = subject(claims?.sub);
    const limited = await env.ACCOUNT_DELETION_LIMITER.limit({ key: `account-deletion:${userId}` });
    if (!limited.success) throw new CommerceError('account_deletion_rate_limited', 429);
    if (path.endsWith('/deletion') && request.method === 'GET') {
      const row = await env.DB.prepare('SELECT retired_at, clerk_deleted_at FROM account_retirements WHERE user_id = ?1')
        .bind(userId).first();
      return reply(env, request, status(row));
    }
    if (!path.endsWith('/delete') || request.method !== 'POST') throw new CommerceError('not_found', 404);
    const now = Math.floor(Date.now() / 1000);
    // JWT issuance freshness is not proof of recent password/MFA entry.
    // Explicit destructive confirmation remains separately required below.
    if (!Number.isSafeInteger(claims.iat) || claims.iat > now + 30 || now - claims.iat > 300) {
      throw new CommerceError('fresh_session_token_required', 401);
    }
    let body;
    try { body = JSON.parse(await boundedText(request, 4096)); }
    catch (error) { if (error instanceof CommerceError) throw error; throw new CommerceError('invalid_json'); }
    if (!body || Array.isArray(body) || typeof body !== 'object' ||
        Object.keys(body).length !== 2 || body.confirm !== 'DELETE_ACCOUNT' ||
        !Object.hasOwn(body, 'recovery_receipt')) {
      throw new CommerceError('deletion_confirmation_required', 400);
    }
    const row = await retireSubjectData(env, userId, body.recovery_receipt);
    if (!row.clerk_deleted_at) await deleteClerkIdentity(env, userId, fetcher);
    const current = await env.DB.prepare('SELECT retired_at, clerk_deleted_at FROM account_retirements WHERE user_id = ?1')
      .bind(userId).first();
    // 202 is intentional: even identity success is not a completed retention/
    // backup/payment-proof erasure workflow or launch-policy certification.
    return reply(env, request, status(current), 202);
  } catch (error) {
    return reply(env, request, { error: error instanceof CommerceError ? error.code : 'account_deletion_unavailable' },
      error instanceof CommerceError ? error.status : 503);
  }
}
