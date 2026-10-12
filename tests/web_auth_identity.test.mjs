import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const preset = readFileSync(new URL('../export_presets.cfg', import.meta.url), 'utf8');
const shell = preset.match(/html\/head_include="([\s\S]*?)"\n/)[1]
  .replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
const script = [...shell.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map(match => match[1]).find(source => source.includes('window.__ww_auth = auth;'));
const flush = async () => { await Promise.resolve(); await Promise.resolve(); };

async function fixture({ finishLoad = true } = {}) {
  const events = {}; const pending = []; const intervals = []; const scripts = []; const timeouts = new Map();
  let nextTimeout = 0;
  const window = { addEventListener(name, callback) { events[name] = callback; } };
  const document = { hidden: false, addEventListener() {}, head: { appendChild(node) { scripts.push(node); } },
    createElement() { return { setAttribute() {} }; } };
  runInNewContext(script, { window, document,
    setTimeout(fn, ms) { if (ms === 6000) { fn(); return 0; } const id = ++nextTimeout; timeouts.set(id, fn); return id; },
    clearTimeout(id) { timeouts.delete(id); }, setInterval(fn) { intervals.push(fn); } });
  events.load();
  const session = id => ({ id, getToken() { return new Promise((resolve, reject) => pending.push({ resolve, reject })); } });
  if (finishLoad) {
    window.Clerk = { user: { id: 'a', username: 'A' }, session: session('a1'), load: async () => {},
      addListener(fn) { this.listener = fn; } };
    scripts[0].onload(); await flush();
  }
  return { window, pending, intervals, scripts, timeouts, auth: window.__ww_auth,
    change(owner, sessionId = `${owner}1`) {
      window.Clerk.user = owner ? { id: owner, username: owner } : null;
      window.Clerk.session = owner ? session(sessionId) : null;
      window.Clerk.listener();
    } };
}

test('account switch clears token synchronously and ignores old-owner completion', async () => {
  const f = await fixture(); f.pending[0].resolve('a-old'); await flush();
  f.intervals[0](); const oldA = f.pending[1];
  f.change('b'); assert.equal(f.auth.token, ''); assert.equal(f.auth.signedIn, true);
  f.pending[2].resolve('b-current'); await flush(); oldA.resolve('a-late'); await flush();
  assert.equal(f.auth.token, 'b-current');
});

test('A to B to A rejects original A result despite matching owner again', async () => {
  const f = await fixture(); const original = f.pending[0];
  const firstEpoch = f.auth.identityEpoch;
  f.change('b'); f.change('a'); f.pending[2].resolve('a-new'); await flush();
  original.resolve('a-original'); f.pending[1].resolve('b-late'); await flush();
  assert.equal(f.auth.token, 'a-new');
  assert.equal(f.auth.identityEpoch, firstEpoch + 2);
});

test('same-session refresh preserves current token and newest completion wins', async () => {
  const f = await fixture(); f.pending[0].resolve('current'); await flush();
  const epoch = f.auth.identityEpoch;
  f.intervals[0](); assert.equal(f.auth.token, 'current');
  f.intervals[0](); f.pending[2].resolve('newest'); await flush();
  f.pending[1].reject(new Error('old failure')); await flush();
  assert.equal(f.auth.token, 'newest');
  assert.equal(f.auth.identityEpoch, epoch);
});

test('signout cannot be undone by delayed success or failure', async () => {
  const f = await fixture(); f.change(null); f.pending[0].resolve('late'); await flush();
  assert.equal(f.auth.token, ''); assert.equal(f.auth.signedIn, false);
});

test('session changes before listener runs reject stale token without relying on polling', async () => {
  const f = await fixture(); f.window.Clerk.user = { id: 'b' };
  f.pending[0].resolve('a-stale'); await flush(); assert.equal(f.auth.token, '');
});

test('same owner new Clerk session clears old credential and rejects prior session completion', async () => {
  const f = await fixture(); f.pending[0].resolve('a1'); await flush();
  f.intervals[0](); f.change('a', 'a2'); assert.equal(f.auth.token, '');
  f.pending[2].resolve('a2'); await flush(); f.pending[1].resolve('a1-late'); await flush();
  assert.equal(f.auth.token, 'a2');
});

test('first sign-in tap opens Clerk modal after lazy bundle finishes', async () => {
  const f = await fixture({ finishLoad: false });
  let opened = 0;
  f.auth.signIn();
  f.window.Clerk = { user: null, session: null, load: async () => {},
    addListener() {}, openSignIn() { opened += 1; } };
  f.scripts[0].onload(); await flush();
  assert.equal(opened, 1);
  assert.equal(f.auth.ready, true);
  assert.equal(f.auth.loading, false);
  assert.equal(f.auth.error, '');
});

test('script load failure ends Opening and next sign-in retries Clerk', async () => {
  const f = await fixture({ finishLoad: false });
  f.scripts[0].onerror();
  assert.equal(f.auth.loading, false);
  assert.equal(f.auth.error, 'script');
  f.auth.signIn();
  assert.equal(f.scripts.length, 2);
  assert.equal(f.auth.loading, true);
  assert.equal(f.auth.error, '');
});

test('stalled Clerk loader times out and exposes retry', async () => {
  const f = await fixture({ finishLoad: false });
  f.auth.signIn();
  const watchdog = [...f.timeouts.values()][0];
  assert.equal(typeof watchdog, 'function');
  watchdog();
  assert.equal(f.auth.loading, false);
  assert.equal(f.auth.error, 'timeout');
});
