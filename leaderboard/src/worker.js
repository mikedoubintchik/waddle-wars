// Waddle Wars leaderboard — Cloudflare Worker + D1.
// Auth: Clerk session JWTs verified against the instance JWKS (RS256).
// Endpoints:
//   GET  /api/leaderboard?mode=time&course=glacier&limit=20   (public; adds `me` when a valid Bearer token is sent)
//   POST /api/scores  {mode, course, value}  Bearer required  (upserts, keeps personal best)
//   GET  /api/health

const MODES = new Set(['time', 'endless']);
const COURSES = new Set(['glacier', 'aurora', 'iceberg', 'endless']);
// Sanity bounds: times 10s..30min in ms, endless distance 1..1,000,000 m.
const BOUNDS = { time: [10_000, 1_800_000], endless: [1, 1_000_000] };

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  'Access-Control-Max-Age': '86400',
};

let jwksCache = { keys: null, fetchedAt: 0 };

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
  if (!jwksCache.keys || now - jwksCache.fetchedAt > 3_600_000) {
    const r = await fetch(`${issuer}/.well-known/jwks.json`);
    if (!r.ok) return null;
    jwksCache = { keys: (await r.json()).keys || [], fetchedAt: now };
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
    const jwk = await getJwk(env.CLERK_ISSUER, header.kid);
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
    if (payload.iss !== env.CLERK_ISSUER) return null;
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
  return clerkName(env, userId);
}

async function clerkName(env, userId) {
  try {
    const r = await fetch(`https://api.clerk.com/v1/users/${userId}`, {
      headers: { Authorization: `Bearer ${env.CLERK_SECRET_KEY}` },
    });
    if (!r.ok) return 'Penguin';
    const u = await r.json();
    const email = u.email_addresses?.[0]?.email_address || '';
    return (
      u.username ||
      [u.first_name, u.last_name].filter(Boolean).join(' ') ||
      email.split('@')[0] ||
      'Penguin'
    ).slice(0, 24);
  } catch {
    return 'Penguin';
  }
}

async function authFromRequest(env, request) {
  const auth = request.headers.get('Authorization') || '';
  if (!auth.startsWith('Bearer ')) return null;
  return verifyClerkJwt(env, auth.slice(7));
}

async function handleLeaderboard(env, request, url) {
  const mode = url.searchParams.get('mode') || 'time';
  const course = url.searchParams.get('course') || 'glacier';
  if (!MODES.has(mode) || !COURSES.has(course)) return json({ error: 'bad params' }, 400);
  const limit = Math.min(Math.max(parseInt(url.searchParams.get('limit') || '20', 10) || 20, 1), 100);
  const order = mode === 'time' ? 'ASC' : 'DESC';
  const rows = await env.DB.prepare(
    `SELECT name, value, created_at FROM scores WHERE mode = ?1 AND course = ?2 ORDER BY value ${order} LIMIT ?3`,
  ).bind(mode, course, limit).all();
  const entries = (rows.results || []).map((r, i) => ({ rank: i + 1, name: r.name, value: r.value }));

  let me = null;
  const claims = await authFromRequest(env, request);
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
  const value = Math.round(Number(body?.value));
  if (!MODES.has(mode) || !COURSES.has(course)) return json({ error: 'bad params' }, 400);
  const [lo, hi] = BOUNDS[mode];
  if (!Number.isFinite(value) || value < lo || value > hi) return json({ error: 'bad value' }, 400);

  const customName = sanitizeName(body?.name);
  if (customName) {
    await env.DB.prepare(
      'INSERT INTO profiles (user_id, name) VALUES (?1, ?2) ON CONFLICT(user_id) DO UPDATE SET name = ?2',
    ).bind(claims.sub, customName).run();
  }
  const name = customName || await displayName(env, claims.sub);
  const existing = await env.DB.prepare(
    'SELECT value FROM scores WHERE user_id = ?1 AND mode = ?2 AND course = ?3',
  ).bind(claims.sub, mode, course).first();
  const improved =
    !existing || (mode === 'time' ? value < existing.value : value > existing.value);
  const best = improved ? value : existing.value;
  await env.DB.prepare(
    `INSERT INTO scores (user_id, name, mode, course, value) VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(user_id, mode, course) DO UPDATE SET value = ?5, name = ?2, created_at = datetime('now')`,
  ).bind(claims.sub, name, mode, course, best).run();

  const cmp = mode === 'time' ? '<' : '>';
  const betterCount = await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM scores WHERE mode = ?1 AND course = ?2 AND value ${cmp} ?3`,
  ).bind(mode, course, best).first();
  return json({ ok: true, improved, best, rank: (betterCount?.n || 0) + 1, name });
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

async function handleSaveGet(env, request) {
  const claims = await authFromRequest(env, request);
  if (!claims) return json({ error: 'unauthorized' }, 401);
  const row = await env.DB.prepare('SELECT data, updated_at FROM saves WHERE user_id = ?1')
    .bind(claims.sub).first();
  if (!row) return json({ exists: false });
  return json({ exists: true, data: row.data, updated_at: row.updated_at });
}

async function handleSavePut(env, request) {
  const claims = await authFromRequest(env, request);
  if (!claims) return json({ error: 'unauthorized' }, 401);
  const text = await request.text();
  if (text.length > MAX_SAVE_BYTES) return json({ error: 'save too large' }, 413);
  try {
    JSON.parse(text);
  } catch {
    return json({ error: 'save must be JSON' }, 400);
  }
  await env.DB.prepare(
    `INSERT INTO saves (user_id, data, updated_at) VALUES (?1, ?2, datetime('now'))
     ON CONFLICT(user_id) DO UPDATE SET data = ?2, updated_at = datetime('now')`,
  ).bind(claims.sub, text).run();
  return json({ ok: true });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const url = new URL(request.url);
    try {
      if (url.pathname === '/api/health') return json({ ok: true });
      if (url.pathname === '/api/leaderboard' && request.method === 'GET') {
        return await handleLeaderboard(env, request, url);
      }
      if (url.pathname === '/api/scores' && request.method === 'POST') {
        return await handleSubmit(env, request);
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
      return json({ error: 'internal', detail: String(e) }, 500);
    }
  },
};
