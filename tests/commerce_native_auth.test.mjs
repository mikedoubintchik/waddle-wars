import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { runInNewContext } from 'node:vm';
import { handleNativeAuth } from '../leaderboard/src/commerce_native_auth.mjs';

const ORIGIN = 'https://worker.example';
const VERIFIER = 'a'.repeat(43);
const encoder = new TextEncoder();

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
        run: async () => statement.run(args) };
    }; return make();
  }
  async batch(statements) {
    this.db.exec('BEGIN'); try { for (const statement of statements) await statement.run(); this.db.exec('COMMIT'); }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
}

function env(extra = {}) {
  return { DB: new D1(), COMMERCE_NATIVE_AUTH_ENABLED: 'true', COMMERCE_NATIVE_AUTH_ORIGIN: ORIGIN,
    COMMERCE_ALLOWED_ORIGINS: ORIGIN, CLERK_ISSUER: 'https://test.clerk.accounts.dev',
    COMMERCE_CLERK_PUBLISHABLE_KEY: 'pk_test_notarealpublickey', CLERK_SECRET_KEY: 'sk_test_notarealkey',
    COMMERCE_AUTH_LIMITER: { limit: async () => ({ success: true }) }, ...extra };
}

function request(path, body, extra = {}) {
  return new Request(`${ORIGIN}/api/commerce/native-auth/${path}`, { method: body ? 'POST' : 'GET',
    headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...extra.headers },
    ...(body ? { body: JSON.stringify(body) } : {}) });
}

const claims = (user = 'player-one') => ({ sub: user, sid: 'sess_fixture', exp: Math.floor(Date.now() / 1000) + 60 });
async function authenticate(_env, req) {
  const bearer = req.headers.get('Authorization');
  if (bearer === 'Bearer browser-auth' || bearer === 'Bearer native-jwt') return claims();
  if (bearer === 'Bearer other-account') return claims('player-two');
  return null;
}

function provider() {
  const fixture = { session: { id: 'sess_fixture', user_id: 'player-one', status: 'active' }, issued: 'native-jwt', calls: [],
    fetcher: async (url, init) => {
      fixture.calls.push({ url, init });
      return new Response(JSON.stringify(url.endsWith('/tokens') ? { jwt: fixture.issued } : fixture.session));
    } }; return fixture;
}

async function start(environment, extra = {}) {
  const hash = await crypto.subtle.digest('SHA-256', encoder.encode(VERIFIER));
  const challenge = Buffer.from(hash).toString('base64url');
  const response = await handleNativeAuth(request('start', { challenge, ...extra }), environment, authenticate);
  assert.equal(response.status, 200); return response.json();
}

const approve = (environment, id, who = 'browser-auth', origin = ORIGIN) => handleNativeAuth(request('complete', { request_id: id },
  { headers: { Authorization: `Bearer ${who}`, Origin: origin } }), environment, authenticate);

async function delayedRefresh() {
  const environment = env(); const started = await start(environment); const fixture = provider();
  assert.equal((await approve(environment, started.request_id)).status, 200);
  const body = { request_id: started.request_id, verifier: VERIFIER };
  assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, fixture)).status, 200);
  const before = environment.DB.db.prepare('SELECT * FROM commerce_native_auth_sessions WHERE request_id = ?').get(body.request_id);
  let signalReached; let release;
  const reached = new Promise((resolve) => { signalReached = resolve; });
  const hold = new Promise((resolve) => { release = resolve; });
  const baseFetch = fixture.fetcher;
  fixture.fetcher = async (url, init) => {
    const response = await baseFetch(url, init);
    if (url.endsWith('/tokens')) { signalReached(); await hold; }
    return response;
  };
  const pending = handleNativeAuth(request('refresh', body), environment, authenticate, fixture);
  await reached;
  return { environment, fixture, body, before, pending, release };
}

async function assertRefreshDenied(pending) {
  const response = await pending;
  assert.equal(response.status, 401);
  const payload = await response.json();
  assert.equal(payload.error, 'auth_session_invalid');
  assert.equal(Object.hasOwn(payload, 'token'), false);
}

test('native auth configuration, exact host/origin and rate limiter fail closed', async () => {
  for (const override of [{ COMMERCE_NATIVE_AUTH_ENABLED: 'false' }, { CLERK_SECRET_KEY: '' },
    { COMMERCE_NATIVE_AUTH_ORIGIN: 'https://wrong-host.example' }, { COMMERCE_AUTH_LIMITER: null }]) {
    assert.equal((await handleNativeAuth(request('start', { challenge: 'a'.repeat(43) }), env(override), authenticate)).status, 503);
  }
  assert.equal((await handleNativeAuth(request('start', { challenge: 'a'.repeat(43) }, { headers: { Origin: 'https://attacker.example' } }), env(), authenticate)).status, 403);
  assert.equal((await handleNativeAuth(request('start', { challenge: 'a'.repeat(43) }), env({ COMMERCE_AUTH_LIMITER: { limit: async () => ({ success: false }) } }), authenticate)).status, 429);
});

test('authorize page uses explicit account connection; no device verifier or secret in URL/page', async () => {
  const environment = env(); const started = await start(environment);
  assert.equal(started.expires_in, 300); assert.equal(started.interval, 3);
  assert.equal(new URL(started.authorize_url).origin, ORIGIN);
  assert.ok(!started.authorize_url.includes(VERIFIER));
  const page = await handleNativeAuth(new Request(started.authorize_url), environment, authenticate);
  assert.equal(page.status, 200); assert.equal(page.headers.get('X-Frame-Options'), 'DENY');
  assert.equal(page.headers.get('Referrer-Policy'), 'no-referrer');
  const html = await page.text();
  assert.ok(html.includes('Connect this account to my game'));
  assert.ok(html.includes(started.request_id.slice(0, 8).toUpperCase()));
  assert.ok(!html.includes(VERIFIER)); assert.ok(!html.includes(environment.CLERK_SECRET_KEY));
  assert.equal(started.presentation, 'browser');
  assert.ok(!html.includes('com.blubberandbyte.waddlewars.auth://'));
});

test('iOS presentation is stored and cannot switch routes, duplicate IDs or inject callback URLs', async () => {
  const environment = env(); const ios = await start(environment, { presentation: 'ios' });
  const browser = await start(environment);
  assert.equal(ios.presentation, 'ios');
  assert.equal(ios.authorize_url, `${ORIGIN}/api/commerce/native-auth/authorize-ios?request_id=${ios.request_id}`);
  assert.equal(environment.DB.db.prepare('SELECT presentation FROM commerce_native_auth_requests WHERE request_id = ?').get(ios.request_id).presentation, 'ios');
  for (const url of [ios.authorize_url.replace('authorize-ios', 'authorize'), browser.authorize_url.replace('authorize?', 'authorize-ios?'),
    `${ios.authorize_url}&callback_url=https://attacker.example`, `${ios.authorize_url}&request_id=${ios.request_id}`]) {
    assert.equal((await handleNativeAuth(new Request(url), environment, authenticate)).status, 400);
  }
  for (const body of [{ presentation: 'unknown' }, { presentation: 'browser' }, { presentation: null },
    { presentation: 'ios', callback_url: 'custom://attacker' }, { redirect_url: 'https://attacker.example' }]) {
    assert.equal((await handleNativeAuth(request('start', { challenge: 'a'.repeat(43), ...body }), environment, authenticate)).status, 400);
  }
});

async function approvalHarness(environment, started, complete, { signedIn = true, storage = new Map(), storageBlocked = false } = {}) {
  const page = await handleNativeAuth(new Request(started.authorize_url), environment, authenticate);
  assert.equal(page.status, 200);
  const html = await page.text();
  const sources = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map((match) => match[1]).filter((source) => source.trim());
  assert.equal(sources.length, 1);
  const events = {};
  const elements = { connect: { disabled: true, hidden: false }, notice: {}, signin: { addEventListener: (type, handler) => { events[type] = handler; } } };
  const callbacks = []; const fetches = []; const listeners = [];
  const user = { id: 'player-one', primaryEmailAddress: { emailAddress: 'player@example.invalid' } };
  const session = { id: 'sess_fixture', getToken: async () => 'browser-auth' };
  const clerk = { load: async () => {}, user: signedIn ? user : null, session: signedIn ? session : null,
    addListener: (handler) => listeners.push(handler), unmountSignIn: () => {}, mountSignIn: () => {} };
  runInNewContext(sources[0], { document: { getElementById: (id) => elements[id] }, setTimeout,
    sessionStorage: { getItem: (key) => { if (storageBlocked) throw Error(); return storage.get(key) || null; },
      setItem: (key, value) => { if (storageBlocked) throw Error(); storage.set(key, value); }, removeItem: (key) => storage.delete(key) },
    window: { location: { href: started.authorize_url, replace: (url) => callbacks.push(url) }, Clerk: clerk },
    fetch: async (url, init) => {
      fetches.push({ url, init });
      return complete(new Request(`${ORIGIN}${url}`, { ...init, headers: { ...init.headers, Origin: ORIGIN } }));
    } });
  const settle = () => new Promise((resolve) => setImmediate(resolve));
  await settle();
  return { callbacks, fetches, html, elements, events, storage, clerk, settle,
    async waitForCallback() { const deadline = Date.now() + 2000; while (!callbacks.length && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 2)); assert.equal(callbacks.length, 1, elements.notice.textContent); },
    signIn() { clerk.user = user; clerk.session = session; for (const listener of listeners) listener(); },
    sync() { for (const listener of listeners) listener(); } };
}

async function runApprovalPage(environment, started, complete) {
  const harness = await approvalHarness(environment, started, complete);
  assert.equal(typeof harness.elements.connect.onclick, 'function');
  await harness.elements.connect.onclick();
  return harness;
}

test('iOS sheet keeps connection code in Security details and never approves fresh sign-in automatically', async () => {
  const environment = env(); const ios = await start(environment, { presentation: 'ios' });
  const h = await approvalHarness(environment, ios, (req) => handleNativeAuth(req, environment, authenticate), { signedIn: false });
  assert.ok(h.html.includes('Sign in to Waddle Wars'));
  assert.match(h.html, /<details[^>]*><summary>Security details<\/summary><p>Connection code:/);
  assert.ok(h.html.includes('Continue only if you opened sign-in from Waddle Wars on this device.'));
  assert.ok(!h.html.includes('Connect this account to my game'));
  assert.equal(h.fetches.length, 0);
  h.signIn(); h.sync(); h.sync(); await h.settle();
  assert.equal(h.fetches.length, 0); assert.equal(h.callbacks.length, 0);
  assert.equal(h.elements.connect.hidden, false); assert.equal(h.elements.connect.disabled, false);
  assert.match(h.elements.notice.textContent, /Continue with player@example.invalid/);
  await h.elements.connect.onclick(); assert.equal(h.fetches.length, 1); assert.equal(h.callbacks.length, 1);
});

test('iOS existing session and OAuth return always require explicit Continue regardless of storage markers', async () => {
  const environment = env(); const ios = await start(environment, { presentation: 'ios' });
  const storage = new Map([[`waddle-ios-sign-in:${ios.request_id}`, JSON.stringify({ requestID: ios.request_id, at: Date.now() })]]);
  const h = await approvalHarness(environment, ios, (req) => handleNativeAuth(req, environment, authenticate), { storage });
  h.sync(); await h.settle(); assert.equal(h.fetches.length, 0); assert.equal(h.callbacks.length, 0);
  assert.equal(h.elements.connect.hidden, false);
  await h.elements.connect.onclick(); assert.equal(h.fetches.length, 1); assert.equal(h.callbacks.length, 1);
});

test('iOS confirmation double clicks complete once; failed reply never callbacks or retries automatically', async () => {
  for (const success of [true, false]) {
    const environment = env(); const ios = await start(environment, { presentation: 'ios' });
    const h = await approvalHarness(environment, ios, success ? (req) => handleNativeAuth(req, environment, authenticate) : async () => new Response('{}', { status: 401 }));
    await Promise.all([h.elements.connect.onclick(), h.elements.connect.onclick()]);
    h.sync(); await h.settle(); assert.equal(h.fetches.length, 1); assert.equal(h.callbacks.length, success ? 1 : 0);
    if (!success) assert.match(h.elements.notice.textContent, /Close this sheet and try again/);
  }
});

test('iOS session switch while getting token aborts before completion; external browser remains explicit', async () => {
  const environment = env(); const ios = await start(environment, { presentation: 'ios' });
  const h = await approvalHarness(environment, ios, (req) => handleNativeAuth(req, environment, authenticate));
  h.clerk.session.getToken = async () => { h.clerk.session = { id: 'sess_other' }; return 'browser-auth'; };
  await h.elements.connect.onclick(); assert.equal(h.fetches.length, 0); assert.equal(h.callbacks.length, 0);
  const browser = await start(environment); const b = await approvalHarness(environment, browser, (req) => handleNativeAuth(req, environment, authenticate));
  assert.equal(b.fetches.length, 0); assert.ok(b.html.includes('Connection code:'));
  await b.elements.connect.onclick(); assert.equal(b.fetches.length, 1); assert.equal(b.callbacks.length, 0);
});

test('executed iOS approval page returns only fixed credential-free callback after verified complete; return alone cannot exchange', async () => {
  const environment = env(); const ios = await start(environment, { presentation: 'ios' });
  const fixture = provider();
  const tokenBody = { request_id: ios.request_id, verifier: VERIFIER };
  assert.equal((await handleNativeAuth(request('token', tokenBody), environment, authenticate, fixture)).status, 409);
  const result = await runApprovalPage(environment, ios, (req) => handleNativeAuth(req, environment, authenticate));
  assert.deepEqual(result.callbacks, [`com.blubberandbyte.waddlewars.auth://native-auth/return?request_id=${ios.request_id}`]);
  assert.equal(result.fetches[0].url, '/api/commerce/native-auth/complete');
  assert.equal(result.fetches[0].init.headers.Authorization, 'Bearer browser-auth');
  assert.deepEqual(JSON.parse(result.fetches[0].init.body), { request_id: ios.request_id });
  assert.ok(!result.callbacks[0].includes('token')); assert.ok(!result.callbacks[0].includes(VERIFIER));
  assert.equal((await handleNativeAuth(request('token', { ...tokenBody, verifier: 'wrong'.repeat(12) }), environment, authenticate, fixture)).status, 401);
  assert.equal((await handleNativeAuth(request('token', tokenBody), environment, authenticate, fixture)).status, 200);
});

test('executed iOS approval page never returns after failed or non-approval reply; cancellation rejects PKCE exchange', async () => {
  for (const failure of [new Response('{}', { status: 401 }), new Response('{"connected":false}')]) {
    const environment = env(); const ios = await start(environment, { presentation: 'ios' });
    const result = await runApprovalPage(environment, ios, async () => failure);
    assert.deepEqual(result.callbacks, []);
    assert.equal(environment.DB.db.prepare('SELECT state FROM commerce_native_auth_requests').get().state, 'pending');
    const body = { request_id: ios.request_id, verifier: VERIFIER };
    assert.equal((await handleNativeAuth(request('cancel', body), environment, authenticate)).status, 200);
    assert.equal((await approve(environment, ios.request_id)).status, 410);
    assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, provider())).status, 401);
  }
});

test('PKCE requires browser approval and correct device verifier; user IDs in body do not authorize', async () => {
  const environment = env(); const started = await start(environment); const fixture = provider();
  const body = { request_id: started.request_id, verifier: VERIFIER, user_id: 'attacker' };
  assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, fixture)).status, 409);
  assert.equal(fixture.calls.length, 0);
  assert.equal((await approve(environment, started.request_id, 'invalid')).status, 401);
  assert.equal((await approve(environment, started.request_id, 'browser-auth', 'https://attacker.example')).status, 403);
  assert.equal((await approve(environment, started.request_id)).status, 200);
  assert.equal((await handleNativeAuth(request('token', { ...body, verifier: 'b'.repeat(43) }), environment, authenticate, fixture)).status, 401);
  const tokenResponse = await handleNativeAuth(request('token', body), environment, authenticate, fixture);
  assert.equal(tokenResponse.status, 200); assert.equal(tokenResponse.headers.get('Cache-Control'), 'no-store');
  const payload = await tokenResponse.json(); assert.equal(payload.user_id, 'player-one'); assert.equal(payload.token, 'native-jwt');
  const stored = environment.DB.db.prepare('SELECT * FROM commerce_native_auth_sessions').get();
  assert.equal(stored.verifier_hash.length, 64); assert.notEqual(stored.verifier_hash, VERIFIER);
  assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, fixture)).status, 200);
  assert.equal(environment.DB.db.prepare('SELECT COUNT(*) n FROM commerce_native_auth_sessions').get().n, 1);
});

test('approved request cannot switch accounts', async () => {
  const environment = env(); const started = await start(environment);
  await approve(environment, started.request_id);
  assert.equal((await approve(environment, started.request_id, 'other-account')).status, 409);
  assert.equal(environment.DB.db.prepare('SELECT user_id FROM commerce_native_auth_requests').get().user_id, 'player-one');
});

test('expired request and cancellation reject exchange; no provider token produced', async () => {
  for (const cancel of [true, false]) {
    const environment = env(); const started = await start(environment); const fixture = provider();
    await approve(environment, started.request_id);
    const body = { request_id: started.request_id, verifier: VERIFIER };
    if (cancel) assert.equal((await handleNativeAuth(request('cancel', body), environment, authenticate)).status, 200);
    else environment.DB.db.prepare('UPDATE commerce_native_auth_requests SET expires_at = 1').run();
    const response = await handleNativeAuth(request('token', body), environment, authenticate, fixture);
    assert.equal(response.status, cancel ? 401 : 410); assert.equal(fixture.calls.length, 0);
  }
});

test('revoked/expired/provider-mismatched sessions reject refresh', async () => {
  const environment = env(); const started = await start(environment); const fixture = provider();
  await approve(environment, started.request_id);
  const body = { request_id: started.request_id, verifier: VERIFIER };
  await handleNativeAuth(request('token', body), environment, authenticate, fixture);
  assert.equal((await handleNativeAuth(request('refresh', body), environment, authenticate, fixture)).status, 200);
  fixture.session.status = 'revoked';
  assert.equal((await handleNativeAuth(request('refresh', body), environment, authenticate, fixture)).status, 401);
  fixture.session.status = 'active'; fixture.session.user_id = 'attacker';
  assert.equal((await handleNativeAuth(request('refresh', body), environment, authenticate, fixture)).status, 401);
  fixture.session.user_id = 'player-one';
  environment.DB.db.prepare('UPDATE commerce_native_auth_sessions SET expires_at = 1').run();
  assert.equal((await handleNativeAuth(request('refresh', body), environment, authenticate, fixture)).status, 401);
});

test('explicit logout revokes refresh secret and cannot be resurrected by exchange', async () => {
  const environment = env(); const started = await start(environment); const fixture = provider();
  await approve(environment, started.request_id);
  const body = { request_id: started.request_id, verifier: VERIFIER };
  await handleNativeAuth(request('token', body), environment, authenticate, fixture);
  assert.equal((await handleNativeAuth(request('cancel', body), environment, authenticate)).status, 200);
  assert.equal((await handleNativeAuth(request('refresh', body), environment, authenticate, fixture)).status, 401);
  assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, fixture)).status, 401);
});

test('delayed native refresh cannot return a token after real cancel revokes the grant', async () => {
  const delayed = await delayedRefresh();
  const { environment, fixture, body, before, pending, release } = delayed;
  assert.equal((await handleNativeAuth(request('cancel', body), environment, authenticate)).status, 200);
  release(); await assertRefreshDenied(pending);
  const after = environment.DB.db.prepare('SELECT * FROM commerce_native_auth_sessions WHERE request_id = ?').get(body.request_id);
  assert.equal(after.revoked, 1);
  assert.equal(after.expires_at, before.expires_at);
  assert.equal(environment.DB.db.prepare('SELECT state FROM commerce_native_auth_requests WHERE request_id = ?').get(body.request_id).state, 'cancelled');
  const calls = fixture.calls.length;
  assert.equal((await handleNativeAuth(request('refresh', body), environment, authenticate, fixture)).status, 401);
  assert.equal(fixture.calls.length, calls);
});

test('delayed native refresh rechecks grant existence and expiry without recreating or extending it', async () => {
  for (const missing of [false, true]) {
    const { environment, body, pending, release } = await delayedRefresh();
    if (missing) environment.DB.db.prepare('DELETE FROM commerce_native_auth_sessions WHERE request_id = ?').run(body.request_id);
    else environment.DB.db.prepare('UPDATE commerce_native_auth_sessions SET expires_at = 1 WHERE request_id = ?').run(body.request_id);
    release(); await assertRefreshDenied(pending);
    const after = environment.DB.db.prepare('SELECT * FROM commerce_native_auth_sessions WHERE request_id = ?').get(body.request_id);
    if (missing) assert.equal(after, undefined);
    else assert.equal(after.expires_at, 1);
  }
});

test('delayed native refresh rejects changed owner, Clerk session, verifier and request bindings', async () => {
  for (const [column, value] of [['user_id', 'player-two'], ['clerk_session_id', 'sess_other'],
    ['verifier_hash', '0'.repeat(64)], ['request_id', '66b7c5e8-34d6-44ca-8d41-2b67531cdd25']]) {
    const { environment, body, pending, release } = await delayedRefresh();
    environment.DB.db.prepare(`UPDATE commerce_native_auth_sessions SET ${column} = ? WHERE request_id = ?`).run(value, body.request_id);
    release(); await assertRefreshDenied(pending);
    const after = environment.DB.db.prepare('SELECT * FROM commerce_native_auth_sessions').get();
    assert.equal(after[column], value);
    assert.equal(environment.DB.db.prepare('SELECT COUNT(*) n FROM commerce_native_auth_sessions').get().n, 1);
  }
});

test('delayed native refresh succeeds for unchanged grant without extending its lifetime', async () => {
  const { environment, body, before, pending, release } = await delayedRefresh();
  release();
  const response = await pending;
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.token, 'native-jwt');
  assert.equal(payload.user_id, 'player-one');
  assert.ok(payload.expires_in > 0 && payload.expires_in <= 60);
  assert.deepEqual(environment.DB.db.prepare('SELECT * FROM commerce_native_auth_sessions WHERE request_id = ?').get(body.request_id), before);
});

test('cancellation racing provider response cannot create a live refresh session', async () => {
  const environment = env(); const started = await start(environment); const fixture = provider();
  await approve(environment, started.request_id);
  const baseFetch = fixture.fetcher;
  fixture.fetcher = async (url, init) => {
    if (url.endsWith('/tokens')) environment.DB.db.prepare("UPDATE commerce_native_auth_requests SET state = 'cancelled'").run();
    return baseFetch(url, init);
  };
  const response = await handleNativeAuth(request('token', { request_id: started.request_id, verifier: VERIFIER }), environment, authenticate, fixture);
  assert.equal(response.status, 401);
  assert.equal(environment.DB.db.prepare('SELECT COUNT(*) n FROM commerce_native_auth_sessions').get().n, 0);
});

test('provider JWT must itself pass host cryptographic verifier with matching user/session', async () => {
  const environment = env(); const started = await start(environment); const fixture = provider();
  await approve(environment, started.request_id); fixture.issued = 'bad-unsigned-token';
  assert.equal((await handleNativeAuth(request('token', { request_id: started.request_id, verifier: VERIFIER }), environment, authenticate, fixture)).status, 401);
  assert.equal(environment.DB.db.prepare('SELECT COUNT(*) n FROM commerce_native_auth_sessions').get().n, 0);
});

async function approveV2(environment, id) {
  return handleNativeAuth(request('complete', { request_id: id, flow_version: 2 },
    { headers: { Authorization: 'Bearer browser-auth', Origin: ORIGIN } }), environment, authenticate);
}

async function callbackFlow() {
  const environment = env(); const started = await start(environment, { presentation: 'ios', flow_version: 2 });
  const approval = await approveV2(environment, started.request_id); assert.equal(approval.status, 200);
  const approved = await approval.json();
  return { environment, started, approved, body: { request_id: started.request_id, verifier: VERIFIER, callback_code: approved.callback_code } };
}

test('v2 protocol is bound at start and all authorize/complete downgrades fail closed', async () => {
  const environment = env(); const started = await start(environment, { presentation: 'ios', flow_version: 2 });
  assert.equal(started.flow_version, 2); assert.match(started.authorize_url, /\/authorize-ios-v2\?request_id=/);
  for (const route of ['authorize', 'authorize-ios']) assert.equal((await handleNativeAuth(new Request(started.authorize_url.replace('authorize-ios-v2', route)), environment, authenticate)).status, 400);
  assert.equal((await approve(environment, started.request_id)).status, 400);
  const old = await start(environment, { presentation: 'ios' });
  assert.equal((await handleNativeAuth(new Request(old.authorize_url.replace('authorize-ios?', 'authorize-ios-v2?')), environment, authenticate)).status, 400);
  assert.equal((await approveV2(environment, old.request_id)).status, 400);
  for (const extra of [{ flow_version: 2 }, { presentation: 'ios', flow_version: '2' }, { presentation: 'ios', flow_version: 3 }]) {
    assert.equal((await handleNativeAuth(request('start', { challenge: 'a'.repeat(43), ...extra }), environment, authenticate)).status, 400);
  }
});

test('v2 shared-link requester cannot poll for victim token before or after browser login without callback proof', async () => {
  const environment = env(); const started = await start(environment, { presentation: 'ios', flow_version: 2 });
  const fixture = provider(), requestOnly = { request_id: started.request_id, verifier: VERIFIER };
  assert.equal((await handleNativeAuth(request('token', requestOnly), environment, authenticate, fixture)).status, 401);
  const result = await approveV2(environment, started.request_id); assert.equal(result.status, 200);
  const approved = await result.json(); assert.match(approved.callback_code, /^[A-Za-z0-9_-]{43}$/);
  const stored = environment.DB.db.prepare('SELECT * FROM commerce_native_auth_requests').get();
  assert.match(stored.callback_code_hash, /^[a-f0-9]{64}$/); assert.notEqual(stored.callback_code_hash, approved.callback_code);
  assert.equal(JSON.stringify(stored).includes(approved.callback_code), false); assert.equal(stored.callback_code_consumed_at, null);
  assert.ok(stored.callback_code_expires_at <= Math.floor(Date.now() / 1000) + 120);
  for (const body of [requestOnly, { ...requestOnly, callback_code: 'b'.repeat(43) }]) {
    const denied = await handleNativeAuth(request('token', body), environment, authenticate, fixture); assert.equal(denied.status, 401); assert.equal(Object.hasOwn(await denied.json(), 'token'), false);
  }
  assert.equal(fixture.calls.length, 0);
  assert.equal((await approveV2(environment, started.request_id)).status, 409);
});

test('v2 browser automatically returns only its callback code after Clerk login without extra buttons', async () => {
  for (const signedIn of [true, false]) {
    const environment = env(); const started = await start(environment, { presentation: 'ios', flow_version: 2 });
    const h = await approvalHarness(environment, started, req => handleNativeAuth(req, environment, authenticate), { signedIn });
    if (!signedIn) { assert.equal(h.fetches.length, 0); h.signIn(); }
    h.sync(); await h.waitForCallback();
    assert.equal(h.fetches.length, 1); assert.equal(h.callbacks.length, 1);
    assert.ok(!h.html.includes('Connection code:')); assert.ok(!h.html.includes('Security details')); assert.ok(!h.html.includes('<button'));
    const callback = new URL(h.callbacks[0]); assert.equal(callback.protocol, 'com.blubberandbyte.waddlewars.auth:');
    assert.equal(callback.searchParams.get('request_id'), started.request_id); const code = callback.searchParams.get('code'); assert.match(code, /^[A-Za-z0-9_-]{43}$/);
    const body = { request_id: started.request_id, verifier: VERIFIER, callback_code: code };
    assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, provider())).status, 200);
    assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, provider())).status, 401);
  }
});

test('v2 callback malformed or failed complete never redirects and never retries approval automatically', async () => {
  for (const response of [new Response('{}', { status: 401 }), Response.json({ connected: true }), Response.json({ connected: true, callback_code: 'javascript:bad' })]) {
    const environment = env(); const started = await start(environment, { presentation: 'ios', flow_version: 2 });
    const h = await approvalHarness(environment, started, async () => response); h.sync(); await h.settle();
    assert.equal(h.fetches.length, 1); assert.equal(h.callbacks.length, 0); assert.match(h.elements.notice.textContent, /Close this sheet/);
  }
});

test('v2 exact callback plus wrong verifier fails; code expires and duplicate exchange never returns token', async () => {
  const { environment, body } = await callbackFlow(); const fixture = provider();
  assert.equal((await handleNativeAuth(request('token', { ...body, verifier: 'x'.repeat(43) }), environment, authenticate, fixture)).status, 401);
  assert.equal(fixture.calls.length, 0);
  environment.DB.db.prepare('UPDATE commerce_native_auth_requests SET callback_code_expires_at = 1').run();
  assert.equal((await handleNativeAuth(request('token', body), environment, authenticate, fixture)).status, 401);
  assert.equal(fixture.calls.length, 0);
});

async function delayedCallbackFlow() {
  const f = await callbackFlow(), fixture = provider(); let release; let reach;
  const hold = new Promise(resolve => { release = resolve; }), reached = new Promise(resolve => { reach = resolve; });
  const original = fixture.fetcher;
  fixture.fetcher = async (url, init) => { const result = await original(url, init); if (url.endsWith('/tokens')) { reach(); await hold; } return result; };
  const exchange = () => handleNativeAuth(request('token', f.body), f.environment, authenticate, fixture);
  return { ...f, fixture, release, reached, exchange };
}

test('v2 concurrent exchanges consume once and create exactly one refresh grant', async () => {
  const f = await delayedCallbackFlow(); const one = f.exchange(), two = f.exchange(); await f.reached; f.release();
  const results = await Promise.all([one, two]); assert.deepEqual(results.map(r => r.status).sort(), [200, 401]);
  assert.equal(f.environment.DB.db.prepare('SELECT COUNT(*) n FROM commerce_native_auth_sessions').get().n, 1);
  const row = f.environment.DB.db.prepare('SELECT * FROM commerce_native_auth_requests').get(); assert.equal(row.state, 'exchanged'); assert.ok(row.callback_code_consumed_at > 0);
  const replay = await f.exchange(); assert.equal(replay.status, 401);
  const refresh = await handleNativeAuth(request('refresh', { request_id: f.body.request_id, verifier: VERIFIER }), f.environment, authenticate, provider()); assert.equal(refresh.status, 200);
});

test('v2 delayed exchange loses to cancellation, code expiry, subject retirement or changed session', async () => {
  for (const mode of ['cancel', 'expire', 'retire', 'session']) {
    const f = await delayedCallbackFlow(); const pending = f.exchange(); await f.reached;
    if (mode === 'cancel') assert.equal((await handleNativeAuth(request('cancel', { request_id: f.body.request_id, verifier: VERIFIER }), f.environment, authenticate)).status, 200);
    if (mode === 'expire') f.environment.DB.db.prepare('UPDATE commerce_native_auth_requests SET callback_code_expires_at = 1').run();
    if (mode === 'retire') f.environment.DB.db.prepare('INSERT INTO account_retirements(user_id) VALUES (?)').run('player-one');
    if (mode === 'session') f.environment.DB.db.prepare("UPDATE commerce_native_auth_requests SET clerk_session_id = 'sess_other'").run();
    f.release(); const result = await pending; assert.notEqual(result.status, 200, mode); assert.equal(Object.hasOwn(await result.json(), 'token'), false, mode);
    assert.equal(f.environment.DB.db.prepare('SELECT COUNT(*) n FROM commerce_native_auth_sessions').get().n, 0, mode);
  }
});
