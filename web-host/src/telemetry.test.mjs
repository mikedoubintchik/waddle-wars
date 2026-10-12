import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';

function fixture() {
  const points = [];
  const env = {
    SITE: { head: async () => ({ size: 1 }) },
    GAME_EVENTS: { writeDataPoint: point => points.push(point) },
    TELEMETRY_LIMITER: { limit: async () => ({ success: true }) },
  };
  const send = (body, options = {}) => worker.fetch(new Request('https://waddlewars.io/api/telemetry', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://play.waddlewars.io', ...options.headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  }), env);
  return { env, points, send };
}

test('anonymous gameplay events write only bounded allowlisted fields', async () => {
  const f = fixture();
  const response = await f.send({ event: 'run_end', platform: 'web', build: 'a1b2c3',
    distance: 245, score: 1460, fish: 32 });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), 'https://play.waddlewars.io');
  assert.deepEqual(f.points, [{ blobs: ['run_end', 'web', 'a1b2c3', ''], doubles: [245, 1460, 32] }]);
});

test('event endpoint rejects identity, free text, invalid totals, and foreign browser origins', async () => {
  const f = fixture();
  const base = { event: 'app_open', platform: 'web', build: 'release-1' };
  for (const payload of [
    { ...base, user_id: '123' }, { ...base, score: -1 },
    { ...base, code: 'arbitrary' }, { ...base, build: 'x'.repeat(49) },
    { ...base, event: 'made_up' }, { ...base, distance: 5 },
    { ...base, event: 'client_error', code: 'private stack trace' },
  ]) assert.equal((await f.send(payload)).status, 400);
  assert.equal((await f.send(base, { headers: { Origin: 'https://evil.example' } })).status, 403);
  assert.equal((await f.send('x'.repeat(513))).status, 413);
  assert.deepEqual(f.points, []);
});

test('endpoint accepts native requests without Origin, honors rate limit, and checks bindings', async () => {
  const f = fixture();
  const native = { event: 'run_start', platform: 'ios', build: 'release-1' };
  assert.equal((await worker.fetch(new Request('https://waddlewars.io/api/telemetry', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(native),
  }), f.env)).status, 204);
  f.env.TELEMETRY_LIMITER.limit = async () => ({ success: false });
  assert.equal((await f.send(native)).status, 429);
  delete f.env.GAME_EVENTS;
  assert.equal((await f.send(native)).status, 503);
  assert.equal(f.points.length, 1);
});

test('health requires both public entry documents in R2', async () => {
  const f = fixture();
  const request = new Request('https://play.waddlewars.io/api/health');
  assert.deepEqual(await (await worker.fetch(request, f.env)).json(), { ok: true });
  f.env.SITE.head = async key => key === 'index.html' ? null : { size: 1 };
  const old = console.error;
  console.error = () => {};
  try { assert.equal((await worker.fetch(request, f.env)).status, 503); }
  finally { console.error = old; }
});

test('scheduled monitor checks web entries and live leaderboard query', async () => {
  const f = fixture();
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const calls = [], errors = [];
  globalThis.fetch = async url => {
    calls.push(url);
    return new Response(JSON.stringify({ entries: [] }), { status: 200 });
  };
  console.error = message => errors.push(message);
  try {
    await worker.scheduled({}, f.env);
    assert.equal(calls.length, 1);
    assert.match(calls[0], /\/api\/leaderboard\?mode=runner/);
    assert.deepEqual(errors, []);
    f.env.SITE.head = async () => null;
    globalThis.fetch = async () => new Response('{}', { status: 503 });
    await worker.scheduled({}, f.env);
    assert.deepEqual(errors, ['monitor: web_entries_unavailable', 'monitor: leaderboard_unavailable']);
  } finally { globalThis.fetch = originalFetch; console.error = originalError; }
});
