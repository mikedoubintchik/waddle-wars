// Actual standalone page script; synthetic DOM, Clerk, IndexedDB and fetch only.
// Fixtures contain public fake identities and receipts. Never contacts a provider.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runInNewContext } from 'node:vm';
import { ACCOUNT_DELETION_PAGE_SCRIPT, handleAccountDeletionPage } from '../leaderboard/src/account_deletion_page.mjs';

const ORIGIN = 'https://worker.example';
const ISSUER = 'https://fixture.clerk.accounts.dev';
const PUBLISHABLE_KEY = `pk_test_${Buffer.from('fixture.clerk.accounts.dev$').toString('base64').replace(/=+$/, '')}`;
const OWNER = 'synthetic-page-owner';
const SESSION = 'sess_synthetic_page_session';
const TOKEN_TIME = Math.floor(Date.now() / 1000);
const RECEIPT = 'ab'.repeat(32);
const config = { issuer: ISSUER, publishableKey: PUBLISHABLE_KEY };
const clone = value => value === undefined ? undefined : JSON.parse(JSON.stringify(value));
const flush = async () => { for (let count = 0; count < 80; count++) await Promise.resolve(); };
const accepted = (identityDeleted = false) => ({
  requested: true, account_data_erased: true, identity_deleted: identityDeleted,
  state: identityDeleted ? 'identity_deleted_retention_pending' : 'identity_pending',
  deletion_complete: false, retention_review_required: true,
});
const token = (owner = OWNER, session = SESSION) => `synthetic.${Buffer.from(JSON.stringify({
  sub: owner, sid: session, iat: TOKEN_TIME, exp: TOKEN_TIME + 600,
})).toString('base64url')}.synthetic`;

class Element {
  constructor(id = '') {
    this.id = id; this.textContent = ''; this.value = ''; this.checked = false;
    this.disabled = false; this.hidden = false; this.children = []; this.listeners = new Map();
    this.attributes = new Map(); this.style = {}; this.classList = { add() {}, remove() {}, toggle() {} };
  }
  addEventListener(name, listener) {
    if (!this.listeners.has(name)) this.listeners.set(name, []);
    this.listeners.get(name).push(listener);
  }
  setAttribute(name, value) { this.attributes.set(name, String(value)); this[name] = String(value); }
  removeAttribute(name) { this.attributes.delete(name); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  focus() {}
  emit(name) {
    const event = { target: this, preventDefault() {}, stopPropagation() {} };
    for (const listener of this.listeners.get(name) || []) listener(event);
  }
}

// Readwrite transactions serialize across all page fixtures, commit atomically,
// and roll back on injected failure. Receipt writes cannot become visible early.
function indexedDatabase() {
  const stores = new Map(); const queue = []; const completed = []; const transactions = []; let active = null;
  const state = {
    stores, completed, transactions, opened: false, failOpen: false, failNextWrite: false, holdWrites: false,
    rejectStrictDurability: false, downgradeDurability: false,
    journal: () => stores.get('journal')?.values || new Map(),
    meta: () => stores.get('meta')?.values || new Map(),
    seed(owner = OWNER, receipt = RECEIPT, status = 'pending') {
      stores.set('journal', { keyPath: 'owner', values: new Map([[owner, { owner, receipt, state: status }]]) });
      stores.set('meta', { keyPath: undefined, values: new Map([['recovery', owner]]) });
      state.opened = true;
    },
    queueWrite(operation) {
      const tx = transaction(['journal', 'meta'], 'readwrite', { durability: 'strict' });
      operation(tx); return tx;
    },
    releaseWrites() { state.holdWrites = false; if (active) active.pump(); },
  };
  function startNext() {
    if (active || !queue.length) return;
    active = queue.shift(); active.begin();
  }
  function transaction(names, mode = 'readonly', options) {
    const scope = Array.isArray(names) ? names : [names]; const operations = [];
    transactions.push({ mode, names: [...scope], options: clone(options) });
    if (mode === 'readwrite' && state.rejectStrictDurability) throw new Error('Synthetic unsupported durability options');
    let view = null; let begun = false; let finished = false; let scheduled = false;
    const tx = {
      mode, error: null, oncomplete: null, onerror: null, onabort: null,
      durability: state.downgradeDurability ? 'default' : options?.durability || 'default',
      objectStore(name) {
        if (!scope.includes(name)) throw new Error('Synthetic IDB transaction scope violation');
        return {
          get(key) { return enqueue(name, 'get', key); },
          getAll() { return enqueue(name, 'all'); },
          add(value, key) { return enqueue(name, 'add', key, value); },
          put(value, key) { return enqueue(name, 'put', key, value); },
          delete(key) { return enqueue(name, 'delete', key); },
        };
      },
      abort() { fail(new Error('Synthetic transaction abort')); },
      begin() {
        begun = true;
        view = new Map([...stores].map(([name, store]) => [name,
          { keyPath: store.keyPath, values: new Map([...store.values].map(([key, value]) => [key, clone(value)])) }]));
        tx.pump();
      },
      pump() {
        if (!begun || finished || scheduled) return;
        scheduled = true;
        queueMicrotask(() => {
          scheduled = false;
          if (finished) return;
          if (operations.length) {
            const { name, operation, key, value, request } = operations.shift();
            const store = view.get(name);
            if (!store) return fail(new Error('Synthetic missing object store'));
            try {
              const actualKey = store.keyPath ? value?.[store.keyPath] : key;
              if (operation === 'get') request.result = clone(store.values.get(key));
              else if (operation === 'all') request.result = [...store.values.values()].map(clone);
              else {
                if (mode !== 'readwrite') throw new Error('Synthetic readonly write');
                if (operation === 'add' && store.values.has(actualKey)) throw new Error('Synthetic ConstraintError');
                if (operation === 'delete') store.values.delete(key);
                else store.values.set(actualKey, clone(value));
                request.result = actualKey;
              }
              request.onsuccess?.({ target: request });
            } catch (error) {
              request.error = error; request.onerror?.({ target: request, preventDefault() {} });
              return fail(error);
            }
            tx.pump();
          } else if (mode === 'readwrite' && state.holdWrites) {
            // Tests release this commit explicitly; queued tabs stay serialized.
          } else if (mode === 'readwrite' && state.failNextWrite) {
            state.failNextWrite = false; fail(new Error('Synthetic commit failure'));
          } else {
            finished = true;
            if (mode === 'readwrite') for (const name of scope) stores.set(name, view.get(name));
            completed.push({ mode, names: [...scope] });
            tx.oncomplete?.({ target: tx }); active = null; startNext();
          }
        });
      },
    };
    function enqueue(name, operation, key, value) {
      if (finished) throw new Error('Synthetic inactive transaction');
      const request = { result: undefined, error: null, onsuccess: null, onerror: null };
      operations.push({ name, operation, key, value, request }); tx.pump(); return request;
    }
    function fail(error) {
      if (finished) return;
      finished = true; tx.error = error;
      queueMicrotask(() => {
        tx.onerror?.({ target: tx, preventDefault() {} }); tx.onabort?.({ target: tx });
        active = null; startNext();
      });
    }
    queue.push(tx); queueMicrotask(startNext); return tx;
  }
  const db = {
    objectStoreNames: { contains: name => stores.has(name) },
    createObjectStore(name, options = {}) {
      stores.set(name, { keyPath: options.keyPath, values: new Map() });
      return {};
    },
    transaction, close() {},
  };
  state.factory = { open(name, version) {
    assert.equal(name, 'waddle-wars-account-deletion'); assert.equal(version, 1);
    const request = { result: db, error: null, onupgradeneeded: null, onsuccess: null, onerror: null, onblocked: null };
    queueMicrotask(() => {
      if (state.failOpen) {
        request.error = new Error('Synthetic storage failure'); request.onerror?.({ target: request }); return;
      }
      if (!state.opened) { state.opened = true; request.onupgradeneeded?.({ target: request, oldVersion: 0 }); }
      request.onsuccess?.({ target: request });
    });
    return request;
  } };
  return state;
}

async function fixture({ owner = OWNER, sessionId = SESSION, database = indexedDatabase(), randomSeed = 1,
  presetClerk = true, failClerk = false } = {}) {
  const ids = ['notice', 'account-label', 'signin', 'consent', 'confirmation', 'delete-button',
    'check-button', 'delete-form', 'cancel-button'];
  const elements = new Map(ids.map(id => [id, new Element(id)]));
  const requests = []; const tokenRequests = []; const scripts = []; const signouts = [];
  const timers = new Map(); let timerId = 0; let randomCalls = 0;
  const listeners = []; const windowEvents = new Map();
  const makeSession = id => ({ id, getToken(options) {
    return new Promise((resolve, reject) => tokenRequests.push({ owner: clerk.user?.id, session: id, options, resolve, reject }));
  } });
  const clerk = {
    user: owner ? { id: owner, username: `Account ${owner}`, fullName: `Account ${owner}` } : null,
    session: owner ? makeSession(sessionId) : null,
    load: async () => { if (failClerk) throw new Error('Synthetic Clerk failure'); },
    addListener(listener) { listeners.push(listener); },
    mountSignIn() {}, unmountSignIn() {},
    signOut() { signouts.push({ owner: clerk.user?.id, session: clerk.session?.id }); return Promise.resolve(); },
  };
  const location = { origin: ORIGIN, href: `${ORIGIN}/account/delete`, pathname: '/account/delete', search: '', hash: '' };
  const window = { __ww_deletion_page_config: config, location,
    addEventListener(name, listener) { windowEvents.set(name, listener); },
    ...(presetClerk ? { Clerk: clerk } : {}),
  };
  const document = {
    readyState: 'complete', currentScript: { nonce: 'synthetic-page-nonce' }, hidden: false,
    getElementById(id) { return elements.get(id) || null; },
    createElement() { return new Element(); },
    head: { appendChild(element) { scripts.push(element); return element; } },
    addEventListener() {},
  };
  const getRandomValues = bytes => { randomCalls++; for (let i = 0; i < bytes.length; i++) bytes[i] = (randomSeed + i) & 255; return bytes; };
  const context = {
    window, document, location, indexedDB: database.factory, crypto: { getRandomValues },
    URL, Uint8Array, TextDecoder, TextEncoder, AbortController, atob: value => Buffer.from(value, 'base64').toString('binary'),
    setTimeout(callback, delay) { timers.set(++timerId, { callback, delay }); return timerId; },
    clearTimeout(id) { timers.delete(id); },
    fetch(url, options) {
      return new Promise((resolve, reject) => requests.push({ url, options, resolve, reject,
        committedJournal: clone([...database.journal().values()]), committedRecovery: database.meta().get('recovery') }));
    },
    console: { log() { assert.fail('Deletion page must not log'); }, error() { assert.fail('Deletion page must not log'); }, warn() { assert.fail('Deletion page must not log'); } },
  };
  window.indexedDB = context.indexedDB; window.crypto = context.crypto;
  runInNewContext(ACCOUNT_DELETION_PAGE_SCRIPT, context);
  await flush();
  const result = {
    elements, requests, tokenRequests, scripts, signouts, database, timers, window, clerk,
    element: id => elements.get(id),
    visibleText: () => [...elements.values()].map(element => element.textContent).join('\n'),
    randomCalls: () => randomCalls,
    async change(nextOwner, nextSession = SESSION) {
      clerk.user = nextOwner ? { id: nextOwner, username: `Account ${nextOwner}`, fullName: `Account ${nextOwner}` } : null;
      clerk.session = nextOwner ? makeSession(nextSession) : null;
      for (const listener of listeners) listener({ user: clerk.user, session: clerk.session });
      await flush();
    },
    async confirm(text = 'DELETE_ACCOUNT') {
      elements.get('consent').checked = true; elements.get('consent').emit('change');
      elements.get('confirmation').value = text; elements.get('confirmation').emit('input'); await flush();
    },
    async submit() { elements.get('delete-form').emit('submit'); await flush(); },
    async check() { elements.get('check-button').emit('click'); await flush(); },
    async resolveToken(index = 0, value = token(owner, sessionId)) { tokenRequests[index].resolve(value); await flush(); },
    async respond(index, payload, status = 200) {
      requests[index].resolve({ ok: status >= 200 && status < 300, status,
        json: async () => clone(payload), text: async () => JSON.stringify(payload) }); await flush();
    },
    async reject(index, message = 'Synthetic transport failure') { requests[index].reject(new Error(message)); await flush(); },
  };
  return result;
}

function enabledEnvironment(overrides = {}) {
  return { ACCOUNT_DELETION_ENABLED: 'true', ACCOUNT_DELETION_LIMITER: { limit: async () => ({ success: true }) },
    COMMERCE_ALLOWED_ORIGINS: ORIGIN, CLERK_ISSUER: ISSUER, COMMERCE_CLERK_PUBLISHABLE_KEY: PUBLISHABLE_KEY,
    CLERK_SECRET_KEY: 'synthetic-fixture-provider-secret', ...overrides };
}

test('public deletion page is independent of game boot and disabled page loads no auth or executable script', async () => {
  const request = new Request(`${ORIGIN}/account/delete`);
  const response = await handleAccountDeletionPage(request, enabledEnvironment({ ACCOUNT_DELETION_ENABLED: 'false' }));
  assert.equal(response.status, 503);
  const html = await response.text();
  assert.ok(/not (?:currently )?(?:available|enabled)|unavailable|disabled/i.test(html));
  assert.ok(!html.includes('<script')); assert.ok(!html.includes('clerk.browser.js'));
  assert.ok(!html.includes('.wasm')); assert.ok(!html.includes('JavaScriptBridge'));
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
});

test('enabled public deletion page has exact route/config and no sensitive URL inputs', async () => {
  const response = await handleAccountDeletionPage(new Request(`${ORIGIN}/account/delete`), enabledEnvironment());
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.ok(html.includes('__ww_deletion_page_config')); assert.ok(html.includes(PUBLISHABLE_KEY));
  for (const id of ['notice', 'account-label', 'signin', 'consent', 'confirmation', 'delete-button', 'check-button']) {
    assert.ok(html.includes(`id="${id}"`), id);
  }
  assert.ok(!html.includes('.wasm')); assert.ok(!html.includes('JavaScriptBridge'));
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
  assert.equal((await handleAccountDeletionPage(new Request(`${ORIGIN}/account/delete?receipt=${RECEIPT}`), enabledEnvironment())).status, 400);
  assert.equal((await handleAccountDeletionPage(new Request(`${ORIGIN}/account/delete#receipt`), enabledEnvironment())).status, 400);
  const wrongMethod = await handleAccountDeletionPage(new Request(`${ORIGIN}/account/delete`, { method: 'POST' }), enabledEnvironment());
  assert.equal(wrongMethod.status, 405); assert.equal(wrongMethod.headers.get('Allow'), 'GET');
  assert.equal(await handleAccountDeletionPage(new Request(`${ORIGIN}/other`), enabledEnvironment()), null);
});

test('misconfigured page fails closed without loading Clerk or exposing provider configuration', async () => {
  const mismatchedKey = `pk_test_${Buffer.from('other.clerk.accounts.dev$').toString('base64').replace(/=+$/, '')}`;
  const cases = [
    { ACCOUNT_DELETION_ENABLED: 'TRUE' },
    { ACCOUNT_DELETION_LIMITER: undefined }, { ACCOUNT_DELETION_LIMITER: {} },
    { CLERK_SECRET_KEY: undefined }, { CLERK_SECRET_KEY: '' }, { CLERK_SECRET_KEY: 123 },
    { COMMERCE_CLERK_PUBLISHABLE_KEY: undefined }, { COMMERCE_CLERK_PUBLISHABLE_KEY: mismatchedKey },
    { COMMERCE_CLERK_PUBLISHABLE_KEY: 'pk_test_invalid!' },
    { CLERK_ISSUER: 'http://fixture.clerk.accounts.dev' },
    { CLERK_ISSUER: `${ISSUER}/path` }, { CLERK_ISSUER: `${ISSUER}/` },
    { COMMERCE_ALLOWED_ORIGINS: 'https://other.example' },
  ];
  for (const overrides of cases) {
    const response = await handleAccountDeletionPage(new Request(`${ORIGIN}/account/delete`), enabledEnvironment(overrides));
    assert.equal(response.status, 503, JSON.stringify(overrides));
    const html = await response.text();
    assert.ok(!html.includes('<script')); assert.ok(!html.includes(PUBLISHABLE_KEY));
    assert.ok(!html.includes('synthetic-fixture-provider-secret'));
  }
  const insecure = await handleAccountDeletionPage(new Request('http://worker.example/account/delete'),
    enabledEnvironment({ COMMERCE_ALLOWED_ORIGINS: 'http://worker.example' }));
  assert.equal(insecure.status, 503); assert.ok(!(await insecure.text()).includes('<script'));
});

test('fresh captured JWT and durable random receipt precede exact POST; double submit sends nothing extra', async () => {
  const f = await fixture(); await f.confirm(); await f.submit();
  assert.equal(f.tokenRequests.length, 1); assert.deepEqual(clone(f.tokenRequests[0].options), { skipCache: true });
  assert.equal(f.requests.length, 0); await f.resolveToken();
  assert.equal(f.requests.length, 1); assert.equal(f.randomCalls(), 1);
  const { url, options, committedJournal, committedRecovery } = f.requests[0];
  assert.equal(url, '/api/account/delete'); assert.equal(options.method, 'POST');
  const body = JSON.parse(options.body);
  assert.deepEqual(Object.keys(body).sort(), ['confirm', 'recovery_receipt']); assert.equal(body.confirm, 'DELETE_ACCOUNT');
  assert.match(body.recovery_receipt, /^[0-9a-f]{64}$/);
  assert.deepEqual(committedJournal, [{ owner: OWNER, receipt: body.recovery_receipt, state: 'pending' }]);
  assert.equal(committedRecovery, OWNER); assert.equal(options.headers.Authorization, `Bearer ${token()}`);
  assert.deepEqual(f.database.transactions.filter(transaction => transaction.mode === 'readwrite'),
    [{ mode: 'readwrite', names: ['journal', 'meta'], options: { durability: 'strict' } }]);
  assert.equal(options.credentials, 'omit'); assert.equal(options.redirect, 'error');
  assert.equal(options.cache, 'no-store'); assert.equal(options.referrerPolicy, 'no-referrer');
  assert.ok(!url.includes(body.recovery_receipt)); assert.ok(!f.visibleText().includes(body.recovery_receipt));
  await f.submit(); assert.equal(f.requests.length, 1); assert.equal(f.tokenRequests.length, 1);
});

test('exact explicit consent required, and owner/session changes invalidate old confirmation', async () => {
  const f = await fixture(); await f.submit(); assert.equal(f.tokenRequests.length, 0);
  await f.confirm('DELETE'); await f.submit(); assert.equal(f.tokenRequests.length, 0);
  await f.confirm(); await f.change('synthetic-other');
  assert.equal(f.element('consent').checked, false); assert.equal(f.element('confirmation').value, '');
  await f.submit(); assert.equal(f.tokenRequests.length, 0);
  await f.confirm(); await f.change('synthetic-other', 'sess_synthetic_new_session');
  await f.submit(); assert.equal(f.tokenRequests.length, 0);
  assert.equal(f.requests.length, 0); assert.equal(f.database.journal().size, 0);
});

test('A to B to A and same-owner new session reject token completions from original consent', async () => {
  for (const sameOwner of [false, true]) {
    const f = await fixture(); await f.confirm(); await f.submit();
    if (sameOwner) await f.change(OWNER, 'sess_synthetic_new_session');
    else { await f.change('synthetic-other'); await f.change(OWNER, SESSION); }
    await f.resolveToken();
    assert.equal(f.requests.length, 0); assert.equal(f.database.journal().size, 0);
  }
});

test('JWT subject and session mismatch never create a receipt or send POST', async () => {
  for (const badToken of [token('synthetic-other', SESSION), token(OWNER, 'sess_synthetic_other_session'), 'malformed-token']) {
    const f = await fixture(); await f.confirm(); await f.submit(); await f.resolveToken(0, badToken);
    assert.equal(f.requests.length, 0); assert.equal(f.database.journal().size, 0);
    assert.ok(!f.visibleText().includes(badToken));
  }
});

test('storage open or atomic commit failure sends no deletion request', async () => {
  for (const failure of ['open', 'commit']) {
    const database = indexedDatabase(); if (failure === 'open') database.failOpen = true;
    const f = await fixture({ database }); await f.confirm(); await f.submit();
    if (f.tokenRequests.length) {
      if (failure === 'commit') database.failNextWrite = true;
      await f.resolveToken();
    }
    assert.equal(f.requests.length, 0); assert.equal(database.journal().size, 0);
  }
});

test('POST waits for journal and recovery pointer atomic transaction completion', async () => {
  const database = indexedDatabase(); const f = await fixture({ database });
  database.holdWrites = true; await f.confirm(); await f.submit(); await f.resolveToken();
  assert.equal(f.requests.length, 0); assert.equal(database.journal().size, 0); assert.equal(database.meta().size, 0);
  database.releaseWrites(); await flush();
  assert.equal(f.requests.length, 1); assert.equal(database.journal().size, 1); assert.equal(database.meta().get('recovery'), OWNER);
});

test('unsupported or downgraded strict durability aborts registration and sends no POST', async () => {
  for (const failure of ['unsupported', 'downgraded']) {
    const database = indexedDatabase(); const f = await fixture({ database });
    if (failure === 'unsupported') database.rejectStrictDurability = true;
    else database.downgradeDurability = true;
    await f.confirm(); await f.submit(); await f.resolveToken();
    assert.equal(f.requests.length, 0, failure);
    assert.equal(database.journal().size, 0, failure); assert.equal(database.meta().size, 0, failure);
    assert.deepEqual(database.transactions.filter(transaction => transaction.mode === 'readwrite'),
      [{ mode: 'readwrite', names: ['journal', 'meta'], options: { durability: 'strict' } }], failure);
    assert.equal(database.completed.filter(transaction => transaction.mode === 'readwrite').length, 0, failure);
  }
});

test('cancel during atomic commit removes only never-sent receipt and allows fresh reviewed request', async () => {
  const database = indexedDatabase(); const f = await fixture({ database });
  database.holdWrites = true; await f.confirm(); await f.submit(); await f.resolveToken();
  assert.equal(f.requests.length, 0); assert.equal(database.journal().size, 0);
  f.element('cancel-button').emit('click'); await flush();
  assert.equal(f.element('consent').checked, false); assert.equal(f.element('confirmation').value, '');
  database.releaseWrites(); await flush();
  assert.equal(database.journal().size, 0); assert.equal(database.meta().size, 0); assert.equal(f.requests.length, 0);
  const discardedReceipt = Array.from({ length: 32 }, (_, index) => (index + 1).toString(16).padStart(2, '0')).join('');
  assert.ok(!f.visibleText().includes(discardedReceipt)); assert.ok(!f.visibleText().includes(token()));
  await f.confirm(); await f.submit();
  assert.equal(f.tokenRequests.length, 2); await f.resolveToken(1);
  assert.equal(f.requests.length, 1); assert.equal(f.requests[0].options.method, 'POST');
  assert.equal(database.journal().get(OWNER).state, 'pending');
});

test('account switch during held commit removes never-sent original record and fresh original consent can proceed', async () => {
  const database = indexedDatabase(); const f = await fixture({ database });
  database.holdWrites = true; await f.confirm(); await f.submit(); await f.resolveToken();
  await f.change('synthetic-replacement', 'sess_synthetic_replacement_session');
  database.releaseWrites(); await flush();
  assert.equal(f.requests.length, 0); assert.equal(database.journal().size, 0); assert.equal(database.meta().size, 0);
  assert.equal(f.clerk.user.id, 'synthetic-replacement'); assert.equal(f.signouts.length, 0);
  await f.change(OWNER, SESSION); await f.confirm(); await f.submit(); await f.resolveToken(1);
  assert.equal(f.requests.length, 1); assert.equal(f.requests[0].options.method, 'POST');
  assert.equal(database.journal().get(OWNER).state, 'pending');
});

test('unsent cleanup preserves other owner pointer and never deletes replaced or retired original record', async () => {
  const otherOwner = 'synthetic-other-recovery'; const otherReceipt = 'ef'.repeat(32);
  for (const mutation of ['other-owner-pointer', 'replaced-receipt', 'retired-state']) {
    const database = indexedDatabase(); database.seed(otherOwner, otherReceipt, 'retired');
    const f = await fixture({ database });
    database.holdWrites = true; await f.confirm(); await f.submit(); await f.resolveToken();
    f.element('cancel-button').emit('click'); await flush();
    database.queueWrite(tx => {
      tx.objectStore('meta').put(otherOwner, 'recovery');
      if (mutation !== 'other-owner-pointer') {
        const store = tx.objectStore('journal'); const request = store.get(OWNER);
        request.onsuccess = () => store.put({ ...request.result,
          ...(mutation === 'replaced-receipt' ? { receipt: 'cd'.repeat(32) } : { state: 'retired' }) });
      }
    });
    database.releaseWrites(); await flush();
    assert.equal(f.requests.length, 0, mutation);
    assert.deepEqual(database.journal().get(otherOwner), { owner: otherOwner, receipt: otherReceipt, state: 'retired' }, mutation);
    assert.equal(database.meta().get('recovery'), otherOwner, mutation);
    if (mutation === 'other-owner-pointer') assert.equal(database.journal().has(OWNER), false);
    else if (mutation === 'replaced-receipt') {
      assert.deepEqual(database.journal().get(OWNER), { owner: OWNER, receipt: 'cd'.repeat(32), state: 'pending' });
    } else assert.equal(database.journal().get(OWNER).state, 'retired');
  }
});

test('two tabs serialize receipt creation and loser cannot overwrite or issue second POST', async () => {
  const database = indexedDatabase();
  const a = await fixture({ database, randomSeed: 1 }); const b = await fixture({ database, randomSeed: 51 });
  await a.confirm(); await b.confirm(); await a.submit(); await b.submit();
  a.tokenRequests[0].resolve(token()); b.tokenRequests[0].resolve(token()); await flush();
  assert.equal(a.requests.length + b.requests.length, 1);
  const request = [...a.requests, ...b.requests][0];
  assert.equal(database.journal().get(OWNER).receipt, JSON.parse(request.options.body).recovery_receipt);
  assert.equal(database.meta().get('recovery'), OWNER);
});

test('signed-out restart recovers exact stored owner and sends header-only manual status GET', async () => {
  const database = indexedDatabase(); database.seed(); const f = await fixture({ owner: null, database });
  assert.equal(f.requests.length, 0); assert.equal(f.tokenRequests.length, 0);
  await f.check(); assert.equal(f.requests.length, 1);
  const { url, options } = f.requests[0];
  assert.equal(url, '/api/account/deletion/receipt'); assert.equal(options.method, 'GET');
  assert.deepEqual(clone(options.headers), { 'X-Waddle-Deletion-Receipt': RECEIPT });
  assert.ok(!Object.hasOwn(options, 'body') || options.body === undefined);
  assert.equal(options.credentials, 'omit'); assert.equal(options.redirect, 'error');
  assert.equal(options.cache, 'no-store'); assert.equal(options.referrerPolicy, 'no-referrer');
  assert.ok(!url.includes(RECEIPT)); assert.ok(!f.visibleText().includes(RECEIPT));
});

test('unknown status, negative payload and malformed positive retain pending receipt without another POST', async () => {
  for (const [payload, status] of [[{ error: 'status_unavailable' }, 404],
    [{ requested: false, deletion_complete: false }, 200], [{ requested: true, deletion_complete: true }, 200],
    [{ ...accepted(), requested: 'true' }, 200]]) {
    const database = indexedDatabase(); database.seed(); const f = await fixture({ owner: null, database });
    await f.check(); await f.respond(0, payload, status);
    assert.deepEqual(database.journal().get(OWNER), { owner: OWNER, receipt: RECEIPT, state: 'pending' });
    assert.equal(database.meta().get('recovery'), OWNER);
    assert.equal(f.requests.filter(request => request.options.method === 'POST').length, 0);
    assert.ok(!/account.*(?:not deleted|remains active)|deletion complete/i.test(f.visibleText()));
  }
});

test('positive status advances only original receipt owner and never signs out replacement identity', async () => {
  const database = indexedDatabase(); database.seed(); const f = await fixture({ owner: null, database });
  await f.check(); await f.change('synthetic-replacement', 'sess_synthetic_replacement_session');
  await f.respond(0, accepted(true));
  assert.deepEqual(database.journal().get(OWNER), { owner: OWNER, receipt: RECEIPT, state: 'retired' });
  assert.equal(f.clerk.user.id, 'synthetic-replacement'); assert.equal(f.signouts.length, 0);
  assert.ok(!/deletion (?:is )?complete|all.*data.*deleted/i.test(f.visibleText()));
});

test('network exception and timeout never display capability, JWT or success; pending survives', async () => {
  const f = await fixture(); await f.confirm(); await f.submit(); await f.resolveToken();
  const receipt = JSON.parse(f.requests[0].options.body).recovery_receipt;
  await f.reject(0, `Synthetic failure ${receipt} ${token()}`);
  assert.equal(f.database.journal().get(OWNER).state, 'pending');
  assert.ok(!f.visibleText().includes(receipt)); assert.ok(!f.visibleText().includes(token()));
  await f.submit(); assert.equal(f.requests.length, 1);
  await f.check(); assert.equal(f.requests.length, 2);
  const timeout = [...f.timers.values()].find(timer => timer.delay === 20000);
  assert.ok(timeout); timeout.callback();
  assert.equal(f.requests[1].options.signal.aborted, true);
  await f.reject(1, `Synthetic abort ${receipt}`);
  assert.equal(f.database.journal().get(OWNER).state, 'pending'); assert.ok(!f.visibleText().includes(receipt));
});

test('Clerk loader failure is generic and does not issue API requests', async () => {
  const f = await fixture({ presetClerk: false });
  assert.equal(f.scripts.length, 1); assert.equal(f.scripts[0].nonce, 'synthetic-page-nonce');
  f.scripts[0].onerror(new Error('Synthetic SDK failure')); await flush();
  await f.confirm(); await f.submit(); assert.equal(f.requests.length, 0); assert.equal(f.tokenRequests.length, 0);
});
