// Actual shipped fetch bridge, synthetic fetch only. Never contacts an account.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const preset = readFileSync(new URL('../export_presets.cfg', import.meta.url), 'utf8');
const shell = preset.match(/html\/head_include="([\s\S]*?)"\n/)[1]
  .replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
const script = [...shell.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map(match => match[1]).find(source => source.includes('window.__ww_api = api;'));
const RECEIPT = 'ab'.repeat(32); // Public synthetic fixture, never a real receipt.
const URL_VALUE = 'https://worker.example/api/account/deletion/receipt';
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

function fixture() {
  const requests = [], timers = new Map(); let sequence = 0;
  const window = {};
  runInNewContext(script, { window, URL, AbortController,
    setTimeout(callback, delay) { timers.set(++sequence, { callback, delay }); return sequence; },
    clearTimeout(id) { timers.delete(id); },
    fetch(url, options) {
      return new Promise((resolve, reject) => requests.push({ url, options, resolve, reject }));
    } });
  return { api: window.__ww_api, requests, timers };
}

test('receipt fetch contains only header capability, no JWT/cookies/query/body/referrer/redirect', () => {
  const f = fixture();
  const id = f.api.startReceipt(URL_VALUE, RECEIPT);
  assert.equal(id, 1); assert.equal(f.requests.length, 1);
  const { url, options } = f.requests[0];
  assert.equal(url, URL_VALUE);
  assert.equal(options.method, 'GET');
  assert.deepEqual(Object.entries(options.headers), [['X-Waddle-Deletion-Receipt', RECEIPT]]);
  assert.equal(options.body, undefined);
  assert.equal(options.credentials, 'omit'); assert.equal(options.redirect, 'error');
  assert.equal(options.cache, 'no-store'); assert.equal(options.referrerPolicy, 'no-referrer');
  assert.ok(!url.includes(RECEIPT)); assert.equal([...f.timers.values()][0].delay, 20000);
});

test('receipt route rejects other methods/paths, insecure URLs, userinfo, query, fragments and bad capability', () => {
  const f = fixture();
  for (const url of ['http://worker.example/api/account/deletion/receipt',
    'https://worker.example/api/account/delete', 'https://worker.example/api/account/deletion',
    URL_VALUE + '?receipt=' + RECEIPT, URL_VALUE + '#receipt',
    'https://user:pass@worker.example/api/account/deletion/receipt', 'invalid']) {
    assert.equal(f.api.startReceipt(url, RECEIPT), 0);
  }
  for (const receipt of ['', null, RECEIPT.toUpperCase(), RECEIPT + '0', RECEIPT.slice(1), RECEIPT + '\n']) {
    assert.equal(f.api.startReceipt(URL_VALUE, receipt), 0);
  }
  assert.equal(f.requests.length, 0); assert.equal(f.timers.size, 0);
});

test('receipt result consumed once, timeout cleared, no capability in result', async () => {
  const f = fixture(); const id = f.api.startReceipt(URL_VALUE, RECEIPT);
  assert.equal(f.api.poll(id), '');
  f.requests[0].resolve({ ok: true, status: 200, text: async () => '{"requested":true}' });
  await flush();
  const result = f.api.poll(id);
  assert.deepEqual(JSON.parse(result), { done: true, ok: true, status: 200, body: '{"requested":true}' });
  assert.ok(!result.includes(RECEIPT)); assert.equal(f.api.poll(id), ''); assert.equal(f.timers.size, 0);
});

test('receipt timeout aborts; raw fetch exception containing capability never reaches caller', async () => {
  const f = fixture(); const id = f.api.startReceipt(URL_VALUE, RECEIPT);
  [...f.timers.values()][0].callback(); assert.equal(f.requests[0].options.signal.aborted, true);
  f.requests[0].reject(new Error('synthetic exception ' + RECEIPT)); await flush();
  const result = f.api.poll(id);
  assert.deepEqual(JSON.parse(result), { done: true, ok: false, status: 0,
    body: '{"error":"network_unavailable"}' });
  assert.ok(!result.includes(RECEIPT)); assert.equal(f.timers.size, 0);
});

test('authenticated API still uses captured JWT, but no cookie/referrer/redirect transport', async () => {
  const f = fixture(); const id = f.api.start('POST', 'https://worker.example/api/account/delete',
    'synthetic-JWT', '{"confirm":"DELETE_ACCOUNT","recovery_receipt":"' + RECEIPT + '"}');
  assert.equal(f.requests[0].options.headers.Authorization, 'Bearer synthetic-JWT');
  assert.equal(f.requests[0].options.credentials, 'omit'); assert.equal(f.requests[0].options.redirect, 'error');
  f.requests[0].resolve({ ok: false, status: 401, text: async () => '{"error":"unauthorized"}' });
  await flush(); assert.equal(JSON.parse(f.api.poll(id)).status, 401);
});
