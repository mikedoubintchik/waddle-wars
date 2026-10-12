import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';

function splitFixture(overrides = {}) {
  const key = 'releases/web-fixture/index.pck';
  const spec = { version: 1, bytes: 7, sha256: 'a'.repeat(64),
    parts: [{ key: `${key}.part0`, bytes: 3 }, { key: `${key}.part1`, bytes: 4 }], ...overrides };
  const calls = [];
  const env = { SITE: { get: async (name, options) => {
    calls.push(name);
    if (name === key) return null;
    if (name === `${key}.parts.json`) {
      if (options?.onlyIf?.get('If-None-Match') === '"manifest"') return { httpEtag: '"manifest"' };
      return { body: new Response(JSON.stringify(spec)).body, size: 300, httpEtag: '"manifest"' };
    }
    const text = name.endsWith('part0') ? 'abc' : 'defg';
    return { body: new Response(text).body, size: text.length };
  } } };
  return { key, spec, calls, env, request: new Request(`https://play.waddlewars.io/${key}`) };
}

test('large release packs stream ordered bytes without client-side assembly', async () => {
  const f = splitFixture();
  const response = await worker.fetch(f.request, f.env);
  assert.equal(response.headers.get('Content-Length'), '7');
  assert.equal(response.headers.get('Content-Type'), 'application/octet-stream');
  assert.equal(response.headers.get('Cross-Origin-Embedder-Policy'), 'require-corp');
  assert.equal(await response.text(), 'abcdefg');
  assert.deepEqual(f.calls, [f.key, `${f.key}.parts.json`, `${f.key}.part0`, `${f.key}.part1`]);
});

test('large pack HEAD and revalidation do not fetch any parts', async () => {
  for (const conditional of [false, true]) {
    const f = splitFixture();
    const response = await worker.fetch(new Request(f.request, conditional
      ? { headers: { 'If-None-Match': '"manifest"' } } : { method: 'HEAD' }), f.env);
    assert.equal(response.status, conditional ? 304 : 200);
    assert.equal(await response.text(), '');
    assert.equal(f.calls.length, 2);
  }
});

test('pack manifests cannot cross release paths or declare invalid byte counts', async () => {
  for (const spec of [{ parts: [{ key: 'private/file', bytes: 7 }] }, { bytes: 8 },
    { parts: [] }, { sha256: 'invalid' }, { version: 2 },
    { parts: [{ key: 'releases/web-fixture/index.pck.part0', bytes: -1 }] }]) {
    const f = splitFixture(spec);
    assert.equal((await worker.fetch(f.request, f.env)).status, 502);
    assert.equal(f.calls.length, 2);
  }
});

test('missing or truncated pack parts fail the stream instead of returning corrupt success', async () => {
  for (const broken of [null, { body: new Response('ab').body, size: 3 },
    { body: new Response('abcd').body, size: 3 }]) {
    const f = splitFixture();
    const get = f.env.SITE.get;
    f.env.SITE.get = async (key, options) => key === `${f.key}.part0` ? broken : get(key, options);
    const response = await worker.fetch(f.request, f.env);
    await assert.rejects(response.arrayBuffer(), /release pack/);
  }
});

test('closing a download while R2 lookup is pending cancels the arriving part', async () => {
  const f = splitFixture();
  const original = f.env.SITE.get;
  let resolvePart, lookedUp;
  const pending = new Promise(resolve => { resolvePart = resolve; });
  const entered = new Promise(resolve => { lookedUp = resolve; });
  let upstreamCancelled = 0;
  f.env.SITE.get = async (key, options) => {
    if (key === `${f.key}.part0`) { lookedUp(); return pending; }
    return original(key, options);
  };
  const response = await worker.fetch(f.request, f.env);
  await entered;
  await response.body.cancel('tab closed');
  const body = new ReadableStream({ cancel(reason) {
    assert.equal(reason, 'tab closed'); upstreamCancelled++;
  } });
  resolvePart({ body, size: 3 });
  for (let i = 0; i < 10 && upstreamCancelled === 0; i++) await Promise.resolve();
  assert.equal(upstreamCancelled, 1);
  assert.equal(body.locked, false);
  assert.equal(f.calls.includes(`${f.key}.part1`), false);
});

test('public home, game aliases, and canonical redirect keep their routes', async () => {
  const keys = [];
  const env = { SITE: { get: async key => {
    keys.push(key);
    return { body: 'test asset', httpEtag: '"fixture"' };
  } } };
  for (const host of ['waddlewars.io', 'play.waddlewars.io', 'waddlewars.ninjaconsulting.ai']) {
    const response = await worker.fetch(new Request(`https://${host}/`), env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Content-Type'), 'text/html; charset=utf-8');
  }
  assert.deepEqual(keys, ['oauth-home.html', 'index.html', 'index.html']);
  const redirect = await worker.fetch(new Request('https://www.waddlewars.io/native/privacy.html'), env);
  assert.equal(redirect.status, 308);
  assert.equal(redirect.headers.get('Location'), 'https://waddlewars.io/native/privacy.html');
});

test('static host keeps MIME, cache, isolation and conditional responses', async () => {
  const env = { SITE: { get: async () => ({ body: 'fixture', httpEtag: '"fixture"' }) } };
  for (const [name, mime] of Object.entries({ 'app.css': 'text/css; charset=utf-8',
    'favicon.ico': 'image/x-icon', 'sitemap.xml': 'application/xml; charset=utf-8',
    'loader.webp': 'image/webp', 'oauth-feature-6828d07a.avif': 'image/avif',
    'index.wasm': 'application/wasm' })) {
    const response = await worker.fetch(new Request(`https://play.waddlewars.io/${name}`), env);
    assert.equal(response.headers.get('Content-Type'), mime);
    assert.equal(response.headers.get('Cross-Origin-Opener-Policy'), 'same-origin');
    assert.equal(response.headers.get('Cross-Origin-Embedder-Policy'), 'require-corp');
  }
  const index = await worker.fetch(new Request('https://play.waddlewars.io/'), env);
  const hero = await worker.fetch(new Request('https://waddlewars.io/oauth-feature-6828d07a.avif'), env);
  assert.equal(hero.headers.get('Cache-Control'), 'public, max-age=31536000, immutable');
  assert.equal(index.headers.get('Cache-Control'), 'no-store');
  assert.equal(index.headers.get('Link'), '<https://play.waddlewars.io/>; rel="canonical"');
  const staged = await worker.fetch(new Request('https://play.waddlewars.io/releases/web-test/index.html'), env);
  assert.equal(staged.headers.get('X-Robots-Tag'), 'noindex');
  const conditional = await worker.fetch(new Request('https://play.waddlewars.io/index.pck',
    { headers: { 'If-None-Match': '"fixture"' } }), { SITE: { get: async () => ({ httpEtag: '"fixture"' }) } });
  assert.equal(conditional.status, 304);
  const missing = await worker.fetch(new Request('https://play.waddlewars.io/missing'), { SITE: { get: async () => null } });
  assert.equal(missing.status, 404);
});

test('CTA analytics records allowlisted clicks without visitor data', async () => {
  const points = [];
  const env = { CTA_CLICKS: { writeDataPoint: point => points.push(point) },
    CTA_LIMITER: { limit: async () => ({ success: true }) } };
  const post = (body, headers = {}) => worker.fetch(new Request('https://waddlewars.io/api/analytics', {
    method: 'POST', headers: { Origin: 'https://waddlewars.io', 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  }), env);
  assert.equal((await post({ event: 'google_play', placement: 'hero' })).status, 204);
  assert.deepEqual(points, [{ blobs: ['google_play', 'hero'], indexes: ['google_play'] }]);
  assert.equal((await post({ event: 'google_play', placement: 'nav' })).status, 400);
  assert.equal((await post({ event: 'play_browser', placement: 'hero' }, { Origin: 'https://other.example' })).status, 403);
  assert.equal((await post({ event: 'play_browser', placement: 'hero' }, { 'Content-Type': 'text/plain' })).status, 415);
  assert.equal((await worker.fetch(new Request('https://play.waddlewars.io/api/analytics'), env)).status, 404);
  assert.equal(points.length, 1);
  assert.equal((await worker.fetch(new Request('https://waddlewars.io/api/analytics', {
    method: 'POST', headers: { Origin: 'https://waddlewars.io', 'Content-Type': 'application/json' },
    body: '{"event":"google_play","placement":"hero"}',
  }), { ...env, CTA_LIMITER: { limit: async () => ({ success: false }) } })).status, 429);
  assert.equal(points.length, 1);
});

test('feedback is routed only on apex and accepts game preflight without touching R2', async () => {
  const request = new Request('https://waddlewars.io/api/feedback', {
    method: 'OPTIONS', headers: { Origin: 'https://play.waddlewars.io' },
  });
  const response = await worker.fetch(request, {});
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), 'https://play.waddlewars.io');
  assert.equal((await worker.fetch(new Request('https://play.waddlewars.io/api/feedback'), {})).status, 404);
  const invalid = await worker.fetch(new Request('https://waddlewars.io/api/feedback', {
    method: 'POST', headers: { Origin: 'https://play.waddlewars.io', 'Content-Type': 'application/json' },
    body: '{"category":"bug","message":"short"}',
  }), {});
  assert.equal(invalid.status, 400);
  assert.equal(invalid.headers.get('Access-Control-Allow-Origin'), 'https://play.waddlewars.io');
});
