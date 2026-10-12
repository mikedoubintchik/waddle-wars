// Standalone public request surface. It never starts Godot or changes lifecycle
// policy: the existing authenticated POST and status-only receipt API remain
// authoritative. Production configuration and provider acceptance stay separate.
const PATH = '/account/delete';

function browserPage() {
  'use strict';
  const config = window.__ww_deletion_page_config;
  const notice = document.getElementById('notice');
  const account = document.getElementById('account-label');
  const signin = document.getElementById('signin');
  const consent = document.getElementById('consent');
  const confirmation = document.getElementById('confirmation');
  const remove = document.getElementById('delete-button');
  const check = document.getElementById('check-button');
  const SUBJECT = /^[A-Za-z0-9_-]{1,256}$/;
  const RECEIPT = /^[0-9a-f]{64}$/;
  let database, busy = false, storageFailed = false, authReady = false;
  let epoch = 0, identityKey = '', consentContext = null, consentGeneration = 0, activeRecord = null;
  let journalRead = 0, mounted = false;

  function identity() {
    const clerk = window.Clerk;
    const owner = clerk?.user?.id;
    const session = clerk?.session?.id;
    if (typeof owner !== 'string' || !SUBJECT.test(owner) ||
        typeof session !== 'string' || !/^sess_[A-Za-z0-9_-]{1,256}$/.test(session)) return null;
    return { owner, session, epoch };
  }
  function same(left, right) {
    return Boolean(left && right && left.owner === right.owner &&
      left.session === right.session && left.epoch === right.epoch);
  }
  function resetConsent() {
    consentGeneration++; consentContext = null; consent.checked = false; confirmation.value = '';
  }
  function render() {
    const current = identity();
    remove.disabled = busy || storageFailed || !authReady || Boolean(activeRecord) ||
      !consent.checked || confirmation.value !== 'DELETE_ACCOUNT' || !same(consentContext, current);
    check.disabled = busy || storageFailed || !activeRecord;
    consent.disabled = busy || storageFailed || !authReady || !current || Boolean(activeRecord);
    confirmation.disabled = consent.disabled;
  }
  function inform(message) { notice.textContent = message; }
  function unavailable() {
    authReady = false; resetConsent(); render();
    inform('Sign-in is unavailable. Saved requests remain unresolved; use Check status when available.');
  }
  function bounded(promise, milliseconds = 20000) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('unavailable')), milliseconds);
      Promise.resolve(promise).then(resolve, () => reject(new Error('unavailable')))
        .finally(() => clearTimeout(timer));
    });
  }
  function openDatabase() {
    if (database) return database;
    database = new Promise((resolve, reject) => {
      let settled = false;
      const fail = () => { if (!settled) { settled = true; clearTimeout(timer); reject(new Error('journal_unavailable')); } };
      const timer = setTimeout(fail, 5000);
      try {
        const request = indexedDB.open('waddle-wars-account-deletion', 1);
        request.onupgradeneeded = () => {
          const db = request.result;
          if (!db.objectStoreNames.contains('journal')) db.createObjectStore('journal', { keyPath: 'owner' });
          if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta');
        };
        request.onerror = fail; request.onblocked = fail;
        request.onsuccess = () => {
          if (settled) { request.result.close(); return; }
          settled = true; clearTimeout(timer);
          request.result.onversionchange = () => {
            request.result.close(); storageFailed = true; resetConsent(); render();
            inform('Browser request storage changed. Reload before continuing; no new request was sent.');
          };
          resolve(request.result);
        };
      } catch { fail(); }
    });
    return database;
  }
  function validRecord(value, owner) {
    return Boolean(value && typeof value === 'object' && !Array.isArray(value) &&
      Object.keys(value).length === 3 && value.owner === owner && SUBJECT.test(owner) &&
      typeof value.receipt === 'string' && RECEIPT.test(value.receipt) &&
      ['pending', 'retired'].includes(value.state));
  }
  async function transaction(mode, operation) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      let tx, value, finished = false;
      const fail = () => {
        if (finished) return;
        finished = true; clearTimeout(timer);
        try { tx?.abort(); } catch { /* Already closed. */ }
        reject(new Error('journal_unavailable'));
      };
      const timer = setTimeout(fail, 5000);
      try {
        // A relaxed commit may precede disk flushing. Request strict durability
        // for capability writes and fail closed on unsupported/downgraded hints.
        // https://w3c.github.io/IndexedDB/#transaction-durability
        tx = mode === 'readwrite' ? db.transaction(['journal', 'meta'], mode, { durability: 'strict' }) :
          db.transaction(['journal', 'meta'], mode);
        tx.onabort = fail; tx.onerror = fail;
        if (mode === 'readwrite' && tx.durability !== 'strict') { fail(); return; }
        tx.oncomplete = () => {
          if (!finished) { finished = true; clearTimeout(timer); resolve(value); }
        };
        operation(tx, (result) => { value = result; }, fail);
      } catch { fail(); }
    });
  }
  function readRecord(owner) {
    return transaction('readonly', (tx, result, fail) => {
      const load = (target, recovered) => {
        if (typeof target !== 'string' || !SUBJECT.test(target)) { fail(); return; }
        const request = tx.objectStore('journal').get(target);
        request.onsuccess = () => {
          const row = request.result;
          if (row === undefined && !recovered) result(null);
          else if (validRecord(row, target)) result(row);
          else fail();
        };
      };
      if (owner) { load(owner, false); return; }
      const request = tx.objectStore('meta').get('recovery');
      request.onsuccess = () => {
        if (request.result === undefined) result(null);
        else load(request.result, true);
      };
    });
  }
  function createPending(owner) {
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    const receipt = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
    return transaction('readwrite', (tx, result, fail) => {
      const store = tx.objectStore('journal');
      const request = store.get(owner);
      request.onsuccess = () => {
        if (request.result !== undefined) {
          if (validRecord(request.result, owner)) result({ record: request.result, created: false });
          else fail();
          return;
        }
        const record = { owner, receipt, state: 'pending' };
        store.add(record);
        tx.objectStore('meta').put(owner, 'recovery');
        result({ record, created: true });
      };
    });
  }
  function markRetired(record) {
    return transaction('readwrite', (tx, result, fail) => {
      const store = tx.objectStore('journal');
      const request = store.get(record.owner);
      request.onsuccess = () => {
        if (!validRecord(request.result, record.owner) || request.result.receipt !== record.receipt) { fail(); return; }
        const updated = { ...request.result, state: 'retired' };
        store.put(updated); result(updated);
      };
    });
  }
  function discardUnsubmitted(record) {
    return transaction('readwrite', (tx, result) => {
      const store = tx.objectStore('journal');
      const request = store.get(record.owner);
      request.onsuccess = () => {
        const row = request.result;
        if (!validRecord(row, record.owner) || row.receipt !== record.receipt || row.state !== 'pending') {
          result(false); return;
        }
        // Only this tab's freshly created, never-dispatched preparation may be
        // removed. Other tabs refuse to POST an existing owner record.
        store.delete(record.owner);
        const pointer = tx.objectStore('meta').get('recovery');
        pointer.onsuccess = () => {
          if (pointer.result === record.owner) tx.objectStore('meta').delete('recovery');
          result(true);
        };
      };
    });
  }
  async function refreshJournal(preserveNotice = false) {
    const sequence = ++journalRead;
    const context = identity();
    activeRecord = null; render();
    try {
      const record = await readRecord(context?.owner);
      if (sequence !== journalRead || (context ? !same(context, identity()) : identity())) return;
      activeRecord = record; render();
      if (!preserveNotice) inform(record ?
        'A saved deletion request exists. Use Check status; do not submit another request.' :
        (context ? 'Review the signed-in account before confirming deletion.' : 'Sign in to the account you want to delete.'));
    } catch {
      storageFailed = true; resetConsent(); render();
      inform('Browser request storage is unavailable. No new deletion request can be sent.');
    }
  }
  function syncAuth() {
    const current = identity();
    const key = current ? `${current.owner}:${current.session}` : '';
    if (key !== identityKey) {
      identityKey = key; epoch++; resetConsent();
      void refreshJournal();
    }
    const user = window.Clerk?.user;
    account.textContent = current ? `Signed in as ${String(user?.primaryEmailAddress?.emailAddress || user?.username || 'your account').slice(0, 256)}` : 'Not signed in';
    try {
      if (current && mounted) { window.Clerk.unmountSignIn(signin); mounted = false; }
      else if (!current && !mounted && authReady) {
        // Keep SDK sign-in completion on this real request surface, never the
        // game's home URL or an incoming redirect_url. Clerk SignInProps:
        // https://clerk.com/docs/js-frontend/reference/components/authentication/sign-in
        window.Clerk.mountSignIn(signin, { routing: 'hash', forceRedirectUrl: '/account/delete',
          signUpForceRedirectUrl: '/account/delete' }); mounted = true;
      }
    } catch { unavailable(); return; }
    render();
  }
  function tokenMatches(token, context) {
    try {
      if (typeof token !== 'string' || token.length > 32768) return false;
      const parts = token.split('.');
      if (parts.length !== 3) return false;
      const encoded = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, '=')));
      // This is only a consent-owner check, not authentication. The API verifies
      // the signature, issuer, lifetime and issuance freshness independently.
      return claims.sub === context.owner && claims.sid === context.session;
    } catch { return false; }
  }
  function acknowledged(payload) {
    return Boolean(payload && typeof payload === 'object' && !Array.isArray(payload) &&
      payload.requested === true && payload.account_data_erased === true &&
      typeof payload.identity_deleted === 'boolean' && payload.deletion_complete === false &&
      payload.retention_review_required === true && payload.state ===
        (payload.identity_deleted ? 'identity_deleted_retention_pending' : 'identity_pending'));
  }
  async function responseText(response) {
    if (!response.body?.getReader) {
      const text = await response.text();
      if (typeof text !== 'string' || text.length > 8192) throw new Error('unavailable');
      return text;
    }
    const reader = response.body.getReader(), chunks = [];
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 8192) { await reader.cancel(); throw new Error('unavailable'); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  }
  async function send(path, options) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    try {
      const response = await fetch(path, { ...options, credentials: 'omit', redirect: 'error',
        cache: 'no-store', referrerPolicy: 'no-referrer', signal: controller.signal });
      const payload = JSON.parse(await responseText(response));
      return { ok: response.ok, payload };
    } finally { clearTimeout(timer); }
  }
  async function applyStatus(record, result) {
    if (!result.ok || !acknowledged(result.payload)) {
      inform('Deletion status is not confirmed. Keep this browser request record and use Check status later.');
      return;
    }
    await markRetired(record);
    await refreshJournal(true);
    const replacement = identity();
    inform(replacement && replacement.owner !== record.owner ?
      'Deletion was requested for the previously selected account. The current account was not changed.' :
      (result.payload.identity_deleted ?
        'Cloud account data and sign-in identity were deleted. Retained-record review remains pending; deletion is not complete.' :
        'Cloud account data was erased. Sign-in identity deletion and retained-record review remain pending.'));
  }
  async function submit(event) {
    event?.preventDefault();
    syncAuth();
    const context = identity();
    if (busy || storageFailed || !authReady || activeRecord || !consent.checked ||
        confirmation.value !== 'DELETE_ACCOUNT' || !same(context, consentContext)) { render(); return; }
    const generation = consentGeneration;
    let registration = null, transportAttempted = false;
    busy = true; render(); inform('Preparing the deletion request…');
    try {
      const session = window.Clerk.session;
      // Official Session.getToken({skipCache:true}) bypasses the SDK token cache.
      // https://clerk.com/docs/js-frontend/reference/objects/session#gettoken
      const token = await bounded(session.getToken({ skipCache: true }));
      syncAuth();
      if (generation !== consentGeneration || !same(context, identity()) ||
          !same(context, consentContext) || !tokenMatches(token, context)) {
        inform('Account or session changed. Review the confirmation again.'); return;
      }
      registration = await createPending(context.owner);
      syncAuth();
      const stillConfirmed = generation === consentGeneration && same(context, identity()) &&
        same(context, consentContext) && consent.checked && confirmation.value === 'DELETE_ACCOUNT';
      activeRecord = registration.record; resetConsent(); render();
      if (!registration.created) {
        inform('Another tab already saved this account request. Use Check status; no second request was sent.'); return;
      }
      if (!stillConfirmed) {
        inform('Confirmation was canceled or the account changed. The saved request remains unresolved; no new request was sent.'); return;
      }
      inform('Requesting account deletion…');
      // Once fetch is attempted, even a synchronous exception or lost reply is
      // ambiguous. Never discard that receipt based on a negative status read.
      transportAttempted = true;
      const result = await send('/api/account/delete', { method: 'POST', headers: {
        'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ confirm: 'DELETE_ACCOUNT', recovery_receipt: registration.record.receipt }) });
      await applyStatus(registration.record, result);
    } catch {
      inform('Request unavailable or not confirmed. Keep the saved request, if any, and use Check status later.');
    } finally {
      if (registration?.created && !transportAttempted) {
        try {
          const removed = await discardUnsubmitted(registration.record);
          inform(removed ? 'No deletion request was sent. Review the account again before confirming.' :
            'No deletion request was sent, but the saved record changed. Check its status before continuing.');
        } catch {
          storageFailed = true;
          inform('No deletion request was sent, but browser preparation could not be cleared. Reload before continuing.');
        }
      }
      busy = false; await refreshJournal(true); render();
    }
  }
  async function checkStatus(event) {
    event?.preventDefault();
    if (busy || storageFailed) return;
    busy = true; render();
    try {
      // Re-read committed storage, never an in-memory capability from another
      // account. Signed-out recovery uses only this browser's durable owner.
      const context = identity();
      const record = await readRecord(context?.owner);
      if (!record || (context ? !same(context, identity()) : identity())) return;
      inform('Checking deletion status…');
      const result = await send('/api/account/deletion/receipt', { method: 'GET',
        headers: { 'X-Waddle-Deletion-Receipt': record.receipt } });
      await applyStatus(record, result);
    } catch {
      inform('Status unavailable. The saved request remains unresolved; try Check status later.');
    } finally {
      busy = false; await refreshJournal(true); render();
    }
  }
  consent.addEventListener('change', () => {
    syncAuth(); consentContext = consent.checked ? identity() : null; render();
  });
  confirmation.addEventListener('input', render);
  remove.addEventListener('click', submit);
  document.getElementById('delete-form')?.addEventListener('submit', submit);
  check.addEventListener('click', checkStatus);
  document.getElementById('cancel-button')?.addEventListener('click', () => { resetConsent(); render(); });
  render(); void refreshJournal();
  async function loadClerk() {
    try {
      const clerk = window.Clerk;
      if (!clerk) throw new Error('unavailable');
      await bounded(clerk.load()); authReady = true;
      clerk.addListener(syncAuth); syncAuth();
    } catch { unavailable(); }
  }
  if (window.Clerk) void loadClerk();
  else {
    const script = document.createElement('script');
    script.async = true; script.crossOrigin = 'anonymous';
    script.nonce = document.currentScript?.nonce || '';
    script.setAttribute('data-clerk-publishable-key', config.publishableKey);
    script.src = `${config.issuer}/npm/@clerk/clerk-js@5/dist/clerk.browser.js`;
    let loaded = false;
    const timer = setTimeout(() => { loaded = true; unavailable(); }, 20000);
    script.onload = () => { if (!loaded) { loaded = true; clearTimeout(timer); void loadClerk(); } };
    script.onerror = () => { loaded = true; clearTimeout(timer); unavailable(); };
    document.head.appendChild(script);
  }
}

// Tests execute exactly this embedded script, not a second implementation.
export const ACCOUNT_DELETION_PAGE_SCRIPT = `(${browserPage.toString()})();`;

function publicConfiguration(env, request) {
  if (env.ACCOUNT_DELETION_ENABLED !== 'true' || typeof env.ACCOUNT_DELETION_LIMITER?.limit !== 'function' ||
      typeof env.CLERK_SECRET_KEY !== 'string' || !env.CLERK_SECRET_KEY) return null;
  const publishableKey = env.COMMERCE_CLERK_PUBLISHABLE_KEY;
  try {
    const issuer = new URL(env.CLERK_ISSUER);
    const address = new URL(request.url);
    const origin = address.origin;
    const allowed = String(env.COMMERCE_ALLOWED_ORIGINS || '').split(',').map((item) => item.trim());
    if (address.protocol !== 'https:' || issuer.protocol !== 'https:' || issuer.origin !== env.CLERK_ISSUER ||
        issuer.username || issuer.password || !allowed.includes(origin) ||
        typeof publishableKey !== 'string' || !/^pk_(test|live)_[A-Za-z0-9+/]+={0,2}$/.test(publishableKey) ||
        atob(publishableKey.split('_')[2]) !== `${issuer.host}$`) return null;
    return { issuer: issuer.origin, publishableKey };
  } catch { return null; }
}

export function handleAccountDeletionPage(request, env) {
  const url = new URL(request.url);
  if (url.pathname !== PATH) return null;
  const safeHeaders = { 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY' };
  if (url.search || url.hash) return new Response('Invalid request', { status: 400, headers: safeHeaders });
  if (request.method !== 'GET') return new Response('Method not allowed', {
    status: 405, headers: { ...safeHeaders, Allow: 'GET' } });
  const config = publicConfiguration(env, request);
  const nonce = crypto.randomUUID();
  // Clerk's UI creates inline styles; match the existing native-auth page's
  // style allowance without weakening script nonces or frame/origin guards.
  const csp = `default-src 'none'; script-src 'nonce-${nonce}'${config ? ` ${config.issuer} https://challenges.cloudflare.com https://*.protect.clerk.com` : ''}; style-src ${config ? "'unsafe-inline'" : `'nonce-${nonce}'`}; connect-src 'self'${config ? ` ${config.issuer} https://*.protect.clerk.com:*` : ''}; img-src${config ? ` ${config.issuer} https://img.clerk.com data:` : " 'none'"}; worker-src 'self' blob:; frame-src${config ? ` ${config.issuer} https://challenges.cloudflare.com https://*.protect.clerk.com` : " 'none'"}; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`;
  const title = 'Delete your Waddle Wars account';
  const controls = config ? `<p id="account-label">Loading account sign-in…</p><div id="signin"></div>
<form id="delete-form"><fieldset><legend>Confirm the account request</legend>
<label class="ack"><input id="consent" type="checkbox" disabled> I understand this requests permanent deletion of the signed-in account and its cloud game data.</label>
<label for="confirmation">Type <strong>DELETE_ACCOUNT</strong> to confirm</label>
<input id="confirmation" type="text" autocomplete="off" autocapitalize="none" spellcheck="false" disabled>
<div class="actions"><button id="cancel-button" type="button" autofocus>Cancel confirmation</button><button id="delete-button" class="danger" type="button" disabled>Request account deletion</button></div>
</fieldset></form><button id="check-button" type="button" disabled>Check saved request status</button>` :
    '<p>Account deletion is not enabled in this pre-release service. No deletion request can be sent from this page.</p>';
  const serialized = config ? JSON.stringify(config).replace(/</g, '\\u003c') : '';
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style nonce="${nonce}">*{box-sizing:border-box}body{margin:0;background:#0b1727;color:#edf6ff;font:17px/1.55 system-ui,sans-serif}main{width:min(100%,620px);margin:0 auto;padding:32px max(20px,env(safe-area-inset-right)) 48px max(20px,env(safe-area-inset-left))}h1{font-size:clamp(28px,6vw,36px);line-height:1.15;margin:12px 0 24px}p{overflow-wrap:anywhere}.eyebrow{color:#8ed1ed;font-weight:700;letter-spacing:.07em;font-size:13px}fieldset{border:1px solid #54708c;border-radius:14px;padding:20px;margin:24px 0}legend{padding:0 8px;font-weight:700}label{display:block;margin:14px 0 8px}.ack{display:flex;align-items:flex-start;gap:12px}.ack input{width:22px;height:22px;flex:0 0 auto;margin-top:3px}input[type=text]{width:100%;min-height:48px;font:inherit;padding:10px;border:2px solid #7896b0;border-radius:8px;background:#10243a;color:inherit}button{min-height:48px;max-width:100%;padding:12px 16px;border:2px solid #87bfd8;border-radius:10px;background:#183b54;color:inherit;font:700 16px/1.3 system-ui;cursor:pointer}.actions{display:flex;flex-wrap:wrap;gap:12px;margin-top:20px}.danger{background:#843542;border-color:#eda5af}button:disabled,input:disabled{opacity:.55;cursor:default}:focus-visible{outline:3px solid #ffe194;outline-offset:4px}#notice{padding:16px;background:#152d44;border-radius:10px;min-height:60px}footer{font-size:14px;color:#b9ccdc;margin-top:28px}@media(max-width:400px){fieldset{padding:14px}.actions button{width:100%}}</style></head>
<body><main><p class="eyebrow">WADDLE WARS · ACCOUNT</p><h1>${title}</h1>
<p>This page requests deletion of your Waddle Wars sign-in account, leaderboard profile, scores and cloud save. You do not need to open or install the game.</p>
<p>Identity deletion may still be pending after cloud game data is erased. Retained-record review is not complete; this page does not promise complete deletion or a retention deadline.</p>
<p id="notice" role="status" aria-live="polite">${config ? 'Sign in and review the account before confirming. Saved request status can also be checked without sign-in.' : 'Account deletion is currently unavailable.'}</p>
${controls}<noscript>JavaScript is required for sign-in and secure request recovery. No request has been sent.</noscript>
<footer>This browser keeps a private status receipt before sending a request. Clearing browser storage removes that recovery method. This page does not erase offline progress or purchase caches on your game devices.</footer>
</main>${config ? `<script nonce="${nonce}">window.__ww_deletion_page_config=${serialized};\n${ACCOUNT_DELETION_PAGE_SCRIPT}</script>` : ''}</body></html>`;
  return new Response(html, { status: config ? 200 : 503, headers: { ...safeHeaders,
    'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': csp } });
}
