// Waddle Wars leaderboard — Cloudflare Worker + D1.
// Auth: Clerk session JWTs verified against the instance JWKS (RS256).
// Endpoints:
//   GET  /api/leaderboard?mode=time&course=glacier&limit=20   (public; adds `me` when a valid Bearer token is sent)
//   POST /api/scores  {mode, course, value}  Bearer required  (upserts, keeps personal best)
//   GET  /api/health

import { handleCommerce } from './commerce.mjs';
import { acceptedClerkIssuer } from './native_accounts_policy.mjs';
import { handleAccountLifecycle, requireActiveSubject } from './account_lifecycle.mjs';
import { CommerceError } from './commerce_providers.mjs';
import { handleAccountDeletionPage } from './account_deletion_page.mjs';

const RACE_COURSES = new Set(['glacier', 'aurora', 'iceberg', 'cinder', 'hollow']);
// Distinct scoring systems must never share a board. Times are milliseconds;
// Endless Expedition and Waddle Run are points, not distance.
const BOUNDS = { time: [10_000, 1_800_000], endless: [1, 1_000_000], runner: [1, 1_000_000_000] };

function validBoard(mode, course) {
  return (mode === 'time' && RACE_COURSES.has(course)) ||
    (mode === 'endless' && course === 'endless') || (mode === 'runner' && course === 'runner');
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  'Access-Control-Max-Age': '86400',
};

let jwksCache = { issuer: null, keys: null, fetchedAt: 0 };

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

function b64urlToBytes(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  s += '='.repeat((4 - (s.length % 4)) % 4);
  const bin = atob(s);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

async function getJwk(issuer, kid) {
  const now = Date.now();
  if (jwksCache.issuer !== issuer || !jwksCache.keys || now - jwksCache.fetchedAt > 3_600_000) {
    const r = await fetch(`${issuer}/.well-known/jwks.json`);
    if (!r.ok) return null;
    jwksCache = { issuer, keys: (await r.json()).keys || [], fetchedAt: now };
  }
  return jwksCache.keys.find((k) => k.kid === kid) || null;
}

async function verifyClerkJwt(env, token) {
  try {
    const [h, p, sig] = token.split('.');
    if (!h || !p || !sig) return null;
    const dec = new TextDecoder();
    const header = JSON.parse(dec.decode(b64urlToBytes(h)));
    const payload = JSON.parse(dec.decode(b64urlToBytes(p)));
    if (header.alg !== 'RS256') return null;
    const issuer = acceptedClerkIssuer(env, payload.iss);
    if (!issuer) return null;
    const jwk = await getJwk(issuer, header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey(
      'jwk', jwk,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false, ['verify'],
    );
    const ok = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5', key,
      b64urlToBytes(sig), new TextEncoder().encode(`${h}.${p}`),
    );
    if (!ok) return null;
    const now = Date.now() / 1000;
    if (payload.iss !== issuer) return null;
    if (typeof payload.exp !== 'number' || payload.exp < now - 5) return null;
    if (typeof payload.nbf === 'number' && payload.nbf > now + 5) return null;
    if (!payload.sub) return null;
    return payload;
  } catch {
    return null;
  }
}

function sanitizeName(raw) {
  if (typeof raw !== 'string') return null;
  const cleaned = raw.replace(/[^A-Za-z0-9 _\-\.]/g, '').trim().slice(0, 20);
  return cleaned.length >= 2 ? cleaned : null;
}

async function displayName(env, userId) {
  const profile = await env.DB.prepare('SELECT name FROM profiles WHERE user_id = ?1')
    .bind(userId).first();
  if (profile?.name) return profile.name;
  // A private sign-in identity is not consent to publish a leaderboard name.
  // Only the explicitly chosen game profile may supply a public handle.
  return 'Penguin';
}

async function verifiedClaimsFromRequest(env, request) {
  const auth = request.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return null;
  return verifyClerkJwt(env, auth.slice(7));
}

async function authFromRequest(env, request) {
  const claims = await verifiedClaimsFromRequest(env, request);
  if (claims) await requireActiveSubject(env, claims.sub);
  return claims;
}

async function handleLeaderboard(env, request, url) {
  const mode = url.searchParams.get('mode') || 'time';
  const course = url.searchParams.get('course') || 'glacier';
  if (!validBoard(mode, course)) return json({ error: 'bad params' }, 400);
  const limit = Math.min(Math.max(parseInt(url.searchParams.get('limit') || '20', 10) || 20, 1), 100);
  const order = mode === 'time' ? 'ASC' : 'DESC';
  const claims = await authFromRequest(env, request);
  const rows = await env.DB.prepare(
    `SELECT user_id, name, value, RANK() OVER (ORDER BY value ${order}) AS rank
     FROM scores WHERE mode = ?1 AND course = ?2
     ORDER BY value ${order}, created_at ASC, user_id ASC LIMIT ?3`,
  ).bind(mode, course, limit).all();
  // Account identifiers remain private; only authenticated ownership is exposed.
  const entries = (rows.results || []).map((r) => ({ rank: r.rank, name: r.name,
    value: r.value, is_me: Boolean(claims && r.user_id === claims.sub) }));

  let me = null;
  if (claims) {
    const mine = await env.DB.prepare(
      'SELECT value FROM scores WHERE user_id = ?1 AND mode = ?2 AND course = ?3',
    ).bind(claims.sub, mode, course).first();
    if (mine) {
      const cmp = mode === 'time' ? '<' : '>';
      const better = await env.DB.prepare(
        `SELECT COUNT(*) AS n FROM scores WHERE mode = ?1 AND course = ?2 AND value ${cmp} ?3`,
      ).bind(mode, course, mine.value).first();
      me = { rank: (better?.n || 0) + 1, value: mine.value };
    }
  }
  return json({ mode, course, entries, me });
}

async function handleSubmit(env, request) {
  const claims = await authFromRequest(env, request);
  if (!claims) return json({ error: 'unauthorized' }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const { mode, course } = body || {};
  const value = body?.value;
  if (!validBoard(mode, course)) return json({ error: 'bad params' }, 400);
  const [lo, hi] = BOUNDS[mode];
  if (!Number.isSafeInteger(value) || value < lo || value > hi) return json({ error: 'bad value' }, 400);

  const customName = sanitizeName(body?.name);
  if (customName) {
    await env.DB.prepare(
      'INSERT INTO profiles (user_id, name) VALUES (?1, ?2) ON CONFLICT(user_id) DO UPDATE SET name = ?2',
    ).bind(claims.sub, customName).run();
  }
  const name = customName || await displayName(env, claims.sub);
  // Compare inside the write: simultaneous retries or completed runs must
  // never replace a personal best with a worse value read from an old snapshot.
  const cmp = mode === 'time' ? '<' : '>';
  const written = await env.DB.prepare(
    `INSERT INTO scores (user_id, name, mode, course, value) VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(user_id, mode, course) DO UPDATE SET value = excluded.value,
       name = excluded.name, created_at = datetime('now')
     WHERE excluded.value ${cmp} scores.value
     RETURNING value`,
  ).bind(claims.sub, name, mode, course, value).first();
  const improved = Boolean(written);
  if (!improved) {
    // Keep the explicitly chosen public handle current without changing the
    // record's value or tie-order timestamp on a replayed/non-improving score.
    await env.DB.prepare('UPDATE scores SET name = ?2 WHERE user_id = ?1 AND mode = ?3 AND course = ?4')
      .bind(claims.sub, name, mode, course).run();
  }
  const best = written?.value ?? (await env.DB.prepare(
    'SELECT value FROM scores WHERE user_id = ?1 AND mode = ?2 AND course = ?3',
  ).bind(claims.sub, mode, course).first())?.value;

  const betterCount = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM scores WHERE mode = ?1 AND course = ?2 AND value ${cmp} ?3`,
  ).bind(mode, course, best).first();
  return json({ ok: true, improved, best, rank: (betterCount?.n || 0) + 1, name });
}

async function handleProfileGet(env, request) {
  const claims = await authFromRequest(env, request);
  if (!claims) return json({ error: 'unauthorized' }, 401);
  const profile = await env.DB.prepare('SELECT name FROM profiles WHERE user_id = ?1').bind(claims.sub).first();
  return json({ name: profile?.name || '' });
}

async function handleProfile(env, request) {
  const claims = await authFromRequest(env, request);
  if (!claims) return json({ error: 'unauthorized' }, 401);
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const name = sanitizeName(body?.name);
  if (!name) return json({ error: 'bad name (2-20 chars, letters/numbers/space/-_.)' }, 400);
  await env.DB.prepare(
    'INSERT INTO profiles (user_id, name) VALUES (?1, ?2) ON CONFLICT(user_id) DO UPDATE SET name = ?2',
  ).bind(claims.sub, name).run();
  await env.DB.prepare('UPDATE scores SET name = ?2 WHERE user_id = ?1')
    .bind(claims.sub, name).run();
  return json({ ok: true, name });
}

const MAX_SAVE_BYTES = 128 * 1024;

function cloudProgressJSON(text) {
  const progress = JSON.parse(text);
  if (!progress || typeof progress !== 'object' || Array.isArray(progress)) return null;
  // Old clients and stored saves may include local per-account purchase caches
  // or deletion journals/capabilities. None are cloud progress or entitlements.
  for (const field of ['commerce', 'account_deletion', 'account_deletion_receipt',
    'account_deletion_receipts', 'account_deletion_recovery_owner', '_cloud_owner']) delete progress[field];
  return JSON.stringify(progress);
}

async function handleSaveGet(env, request) {
  const claims = await authFromRequest(env, request);
  if (!claims) return json({ error: 'unauthorized' }, 401);
  const row = await env.DB.prepare('SELECT data, updated_at FROM saves WHERE user_id = ?1')
    .bind(claims.sub).first();
  const revisioned = new URL(request.url).searchParams.get('sync') === '2';
  if (!row) return json(revisioned ? { exists: false, sync_protocol: 2, revision: 'absent' } : { exists: false });
  let progress;
  try { progress = cloudProgressJSON(row.data); } catch { /* Never echo malformed legacy data. */ }
  if (!progress) return json({ error: 'invalid cloud save' }, 500);
  return json({ exists: true, data: progress, updated_at: row.updated_at,
    ...(revisioned ? { sync_protocol: 2, revision: await saveRevision(row.data) } : {}) });
}

async function saveRevision(data) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(data));
  return Array.from(new Uint8Array(bytes), (value) => value.toString(16).padStart(2, '0')).join('');
}

function changedRows(result) {
  return Number(result?.meta?.changes ?? result?.changes ?? 0);
}

async function handleSavePut(env, request) {
  const claims = await authFromRequest(env, request);
  if (!claims) return json({ error: 'unauthorized' }, 401);
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_SAVE_BYTES) return json({ error: 'save too large' }, 413);
  let progress, body;
  try {
    body = JSON.parse(text);
    progress = cloudProgressJSON(body?.sync_protocol === 2 ? JSON.stringify(body.progress) : text);
  } catch {
    return json({ error: 'save must be JSON' }, 400);
  }
  if (!progress) return json({ error: 'save must be an object' }, 400);
  const previous = await env.DB.prepare('SELECT data FROM saves WHERE user_id = ?1')
    .bind(claims.sub).first();
  if (body?.sync_protocol === 2) {
    if (typeof body.base_revision !== 'string' || !/^(absent|[a-f0-9]{64})$/.test(body.base_revision)) {
      return json({ error: 'invalid save revision' }, 400);
    }
    const canonical = JSON.parse(progress);
    canonical.cloud_sync_version = 2;
    progress = JSON.stringify(canonical);
    const actualRevision = previous ? await saveRevision(previous.data) : 'absent';
    if (body.base_revision !== actualRevision) return json({ error: 'save_revision_conflict' }, 409);
    // Exact-row compare-and-swap closes the GET/PUT and concurrent PUT races.
    // No timestamp ordering assumptions or schema migration required.
    const result = previous
      ? await env.DB.prepare(`UPDATE saves SET data = ?2, updated_at = datetime('now')
          WHERE user_id = ?1 AND data = ?3
          AND NOT EXISTS (SELECT 1 FROM account_retirements WHERE user_id = ?1)`).bind(claims.sub, progress, previous.data).run()
      : await env.DB.prepare(`INSERT INTO saves (user_id, data, updated_at)
          SELECT ?1, ?2, datetime('now')
          WHERE NOT EXISTS (SELECT 1 FROM account_retirements WHERE user_id = ?1)
          ON CONFLICT(user_id) DO NOTHING`)
        .bind(claims.sub, progress).run();
    if (changedRows(result) !== 1) return json({ error: 'save_revision_conflict' }, 409);
    return json({ ok: true, sync_protocol: 2, revision: await saveRevision(progress) });
  }
  // Once a revised client has saved this account, an old last-write-wins
  // client must not erase its merged ledger or newer progress.
  if (previous) {
    try {
      if (JSON.parse(previous.data)?.cloud_sync_version >= 2) {
        return json({ error: 'save_client_upgrade_required' }, 409);
      }
    } catch { return json({ error: 'invalid cloud save' }, 500); }
  }
  const result = previous
    ? await env.DB.prepare(`UPDATE saves SET data = ?2, updated_at = datetime('now')
        WHERE user_id = ?1 AND data = ?3
          AND NOT EXISTS (SELECT 1 FROM account_retirements WHERE user_id = ?1)`).bind(claims.sub, progress, previous.data).run()
    : await env.DB.prepare(`INSERT INTO saves (user_id, data, updated_at)
        SELECT ?1, ?2, datetime('now')
          WHERE NOT EXISTS (SELECT 1 FROM account_retirements WHERE user_id = ?1)
          ON CONFLICT(user_id) DO NOTHING`)
      .bind(claims.sub, progress).run();
  if (changedRows(result) !== 1) return json({ error: 'save_revision_conflict' }, 409);
  return json({ ok: true });
}

export default {
  async fetch(request, env) {
    try {
      const deletionPage = handleAccountDeletionPage(request, env);
      if (deletionPage) return deletionPage;
      const accountResponse = await handleAccountLifecycle(request, env, verifiedClaimsFromRequest);
      if (accountResponse) return accountResponse;
      // Commerce owns its narrower origin policy, including preflight responses.
      const commerceResponse = await handleCommerce(request, env, authFromRequest);
      if (commerceResponse) return commerceResponse;
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
      const url = new URL(request.url);
      if (url.pathname === '/api/health') return json({ ok: true });
      if (url.pathname === '/api/leaderboard' && request.method === 'GET') {
        return await handleLeaderboard(env, request, url);
      }
      if (url.pathname === '/api/scores' && request.method === 'POST') {
        return await handleSubmit(env, request);
      }
      if (url.pathname === '/api/profile' && request.method === 'GET') {
        return await handleProfileGet(env, request);
      }
      if (url.pathname === '/api/profile' && request.method === 'POST') {
        return await handleProfile(env, request);
      }
      if (url.pathname === '/api/save' && request.method === 'GET') {
        return await handleSaveGet(env, request);
      }
      if (url.pathname === '/api/save' && request.method === 'PUT') {
        return await handleSavePut(env, request);
      }
      return json({ error: 'not found' }, 404);
    } catch (e) {
      if (e instanceof CommerceError) return json({ error: e.code }, e.status);
      // A fenced stale write must not expose SQL or identity details.
      return json({ error: 'internal' }, 500);
    }
  },
};
