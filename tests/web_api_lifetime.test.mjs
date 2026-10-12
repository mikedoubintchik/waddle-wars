// Exact production transport; synthetic fetch and deterministic deadlines only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const preset = readFileSync(new URL('../export_presets.cfg', import.meta.url), 'utf8');
const shell = preset.match(/html\/head_include="([\s\S]*?)"\n/)[1]
  .replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
const script = [...shell.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map(match => match[1]).find(source => source.includes('window.__ww_api = api;'));
const flush = async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); };

function fixture({ throws = false } = {}) {
  const requests = [], timers = new Map(); let nextTimer = 0;
  const window = {};
  runInNewContext(script, { window, URL, AbortController,
    setTimeout(callback, delay) { timers.set(++nextTimer, { callback, delay }); return nextTimer; },
    clearTimeout(id) { timers.delete(id); },
    fetch(url, options) {
      if (throws) throw new Error('synthetic fetch failure');
      return new Promise((resolve, reject) => requests.push({ url, options, resolve, reject }));
    } });
  return { api: window.__ww_api, requests, timers,
    start() { return window.__ww_api.start('GET', 'https://synthetic.invalid/board', '', ''); },
    expire() { for (const { callback } of [...timers.values()]) callback(); } };
}

test('never-resolving fetch times out even when abort is ignored, consumed exactly once', async () => {
  const f = fixture(); const id = f.start();
  assert.equal([...f.timers.values()][0].delay, 20000);
  assert.equal(f.api.poll(id), '');
  f.expire();
  assert.equal(f.requests[0].options.signal.aborted, true);
  assert.equal(f.timers.size, 0);
  const reply = JSON.parse(f.api.poll(id));
  assert.equal(reply.ok, false); assert.equal(reply.status, 0);
  assert.deepEqual(JSON.parse(reply.body), { error: 'network_unavailable' });
  assert.equal(f.api.poll(id), '');
  f.requests[0].resolve({ ok: true, status: 200, text: async () => '{"entries":[]}' });
  await flush(); assert.equal(f.api.poll(id), '');
});

test('deadline covers a body that stalls after successful response headers', async () => {
  const f = fixture(); const id = f.start(); let completeBody;
  f.requests[0].resolve({ ok: true, status: 200, text: () => new Promise(resolve => { completeBody = resolve; }) });
  await flush(); assert.equal(f.api.poll(id), '');
  f.expire(); assert.equal(JSON.parse(f.api.poll(id)).ok, false);
  completeBody('{"entries":[]}'); await flush();
  assert.equal(f.api.poll(id), ''); assert.equal(f.timers.size, 0);
});

test('success clears timeout and preserves exact status/body without aborting', async () => {
  const f = fixture(); const id = f.start();
  f.requests[0].resolve({ ok: true, status: 201, text: async () => '{"saved":true}' });
  await flush();
  assert.equal(f.timers.size, 0); assert.equal(f.requests[0].options.signal.aborted, false);
  f.expire();
  assert.deepEqual(JSON.parse(f.api.poll(id)), { done: true, ok: true, status: 201, body: '{"saved":true}' });
  assert.equal(f.api.poll(id), '');
});

test('HTTP and fetch rejection remain failures and release deadlines', async () => {
  const f = fixture(); const http = f.start(); const network = f.start();
  f.requests[0].resolve({ ok: false, status: 503, text: async () => '{"error":"unavailable"}' });
  f.requests[1].reject(new TypeError('synthetic offline'));
  await flush();
  assert.equal(f.timers.size, 0);
  assert.equal(JSON.parse(f.api.poll(http)).status, 503);
  const reply = JSON.parse(f.api.poll(network));
  assert.equal(reply.ok, false); assert.equal(reply.status, 0);
  assert.equal(reply.body, 'TypeError: synthetic offline');
});

test('cancel removes pending/completed results and ignores late resolution/rejection', async () => {
  const f = fixture(); const pending = f.start(); const complete = f.start(); const rejected = f.start();
  f.requests[1].resolve({ ok: true, status: 200, text: async () => '{}' });
  await flush();
  for (const id of [pending, complete, rejected, 999]) f.api.cancel(id);
  assert.equal(f.timers.size, 0); assert.equal(f.requests[0].options.signal.aborted, true);
  assert.equal(f.requests[2].options.signal.aborted, true);
  f.requests[0].resolve({ ok: true, status: 200, text: async () => '{}' });
  f.requests[2].reject(new Error('synthetic cancellation'));
  await flush();
  assert.deepEqual(Object.keys(f.api.results), []);
});

test('repeated stalled requests expire and drain without residual results/timers', () => {
  const f = fixture(); const ids = Array.from({ length: 100 }, () => f.start());
  f.expire();
  for (const id of ids) assert.equal(JSON.parse(f.api.poll(id)).ok, false);
  assert.equal(f.timers.size, 0); assert.equal(Object.keys(f.api.results).length, 0);
  assert.ok(f.requests.every(request => request.options.signal.aborted));
});

test('synchronous fetch failure still gives one consumable error and no timeout', () => {
  const f = fixture({ throws: true }); const id = f.start();
  assert.equal(f.timers.size, 0);
  assert.equal(JSON.parse(f.api.poll(id)).ok, false); assert.equal(f.api.poll(id), '');
});
