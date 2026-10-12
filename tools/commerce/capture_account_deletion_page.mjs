// Isolated installed-Chrome QA. Synthetic Clerk and routed API responses only;
// never uses the owner's profile, game, provider credentials or live services.
import { mkdir, writeFile, lstat } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { handleAccountDeletionPage } from '../../leaderboard/src/account_deletion_page.mjs';

const output = process.argv[2];
const packagePath = process.argv[3];
if (!output || !path.isAbsolute(output) || !packagePath || !path.isAbsolute(packagePath)) {
  throw new Error('Fresh absolute output directory and installed Playwright package required');
}
for (let item = output; item !== path.dirname(item); item = path.dirname(item)) {
  try { if ((await lstat(item)).isSymbolicLink()) throw new Error('Symlink output refused'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}
await mkdir(output, { mode: 0o700 }); // Refuse an existing output directory.
const { chromium } = createRequire(import.meta.url)(packagePath);
const origin = 'https://request.waddle.invalid';
const issuer = 'https://fixture.clerk.accounts.dev';
const env = {
  ACCOUNT_DELETION_ENABLED: 'true',
  ACCOUNT_DELETION_LIMITER: { limit: async () => ({ success: true }) },
  CLERK_SECRET_KEY: 'synthetic-only-never-a-provider-key',
  CLERK_ISSUER: issuer,
  COMMERCE_ALLOWED_ORIGINS: origin,
  COMMERCE_CLERK_PUBLISHABLE_KEY: `pk_test_${Buffer.from('fixture.clerk.accounts.dev$').toString('base64').replace(/=+$/, '')}`,
};
const accepted = {
  requested: true, account_data_erased: true, identity_deleted: false,
  state: 'identity_pending', deletion_complete: false, retention_review_required: true,
};
const report = { browser: '', layouts: [], real_indexeddb: {}, page_errors: 0,
  unexpected_requests: 0, owner_profile_used: false, live_provider_used: false,
  game_or_performance_test: false, device_acceptance: false };
function requireCheck(ok, message) { if (!ok) throw new Error(message); }

function syntheticClerk({ signedIn }) {
  if (location.origin === 'https://request.waddle.invalid' && localStorage.getItem('synthetic-sign-out') === 'true') signedIn = false;
  let listener;
  const owner = 'synthetic-browser-owner', session = 'sess_synthetic_browser_session';
  window.Clerk = {
    user: signedIn ? { id: owner, primaryEmailAddress: { emailAddress: 'qa@example.invalid' } } : null,
    session: signedIn ? { id: session, getToken: async () => {
      const now = Math.floor(Date.now() / 1000);
      return `synthetic.${btoa(JSON.stringify({ sub: owner, sid: session, iat: now, exp: now + 600 }))}.synthetic`;
    } } : null,
    load: async () => {}, addListener: callback => { listener = callback; },
    mountSignIn: () => {}, unmountSignIn: () => {},
  };
  // Fixture-only hook; absent from shipped HTML/script.
  window.__syntheticAuthChanged = () => listener?.();
}

async function setup(context, { enabled = true, signedIn = true, posts = [], gets = [] } = {}) {
  await context.addInitScript(syntheticClerk, { signedIn });
  await context.route('**/*', async route => {
    const request = route.request(), url = new URL(request.url());
    if (url.origin !== origin) { report.unexpected_requests++; await route.abort(); return; }
    if (url.pathname === '/account/delete' && request.method() === 'GET') {
      const response = handleAccountDeletionPage(new Request(url), enabled ? env : {});
      await route.fulfill({ status: response.status, headers: Object.fromEntries(response.headers), body: await response.text() });
      return;
    }
    if (url.pathname === '/api/account/delete' && request.method() === 'POST') {
      const body = request.postDataJSON(), headers = request.headers();
      requireCheck(Object.keys(body).length === 2 && body.confirm === 'DELETE_ACCOUNT' &&
        /^[0-9a-f]{64}$/.test(body.recovery_receipt), 'POST contract mismatch');
      requireCheck(headers.authorization?.startsWith('Bearer synthetic.') &&
        !headers.cookie && !url.search && !headers.referer, 'POST transport mismatch');
      posts.push(true); // Never preserve the raw receipt/token.
      await route.fulfill({ status: 202, contentType: 'application/json', body: JSON.stringify(accepted) });
      return;
    }
    if (url.pathname === '/api/account/deletion/receipt' && request.method() === 'GET') {
      const headers = request.headers();
      requireCheck(/^[0-9a-f]{64}$/.test(headers['x-waddle-deletion-receipt']) &&
        !headers.authorization && !headers.cookie && !headers.referer && !url.search &&
        request.postData() === null, 'Receipt transport mismatch');
      gets.push(true);
      await route.fulfill({ status: 404, contentType: 'application/json', body: '{"error":"status_unavailable"}' });
      return;
    }
    // Chrome may request a favicon; no external request is allowed.
    if (url.pathname === '/favicon.ico') { await route.fulfill({ status: 204, body: '' }); return; }
    report.unexpected_requests++; await route.abort();
  });
  context.on('page', page => page.on('pageerror', () => report.page_errors++));
}
async function open(context) {
  const page = await context.newPage();
  await page.goto(`${origin}/account/delete`, { waitUntil: 'domcontentloaded' });
  return page;
}
async function ready(page) {
  await page.getByText('Signed in as qa@example.invalid', { exact: true }).waitFor();
  await page.waitForFunction(() => !document.getElementById('consent').disabled);
}
async function confirm(page) {
  await ready(page);
  await page.locator('#consent').check();
  await page.locator('#confirmation').fill('DELETE_ACCOUNT');
  await page.waitForFunction(() => !document.getElementById('delete-button').disabled);
}
const browser = await chromium.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true, timeout: 20000,
});
try {
  report.browser = browser.version();
  for (const [width, height] of [[320, 568], [390, 844], [844, 390], [1280, 800]]) {
    for (const enabled of [false, true]) {
      const context = await browser.newContext({ viewport: { width, height }, reducedMotion: 'reduce', serviceWorkers: 'block' });
      try {
        await setup(context, { enabled });
        const page = await open(context);
        if (enabled) await ready(page);
        const layout = await page.evaluate(() => ({
          noHorizontalOverflow: document.documentElement.scrollWidth <= window.innerWidth,
          buttons: [...document.querySelectorAll('button')].map(button => {
            const box = button.getBoundingClientRect();
            return { height: box.height, left: box.left, right: box.right };
          }),
          hasRequestControls: Boolean(document.getElementById('delete-button')),
        }));
        requireCheck(layout.noHorizontalOverflow, 'Horizontal layout overflow');
        requireCheck(layout.hasRequestControls === enabled, 'Availability controls mismatch');
        requireCheck(layout.buttons.every(b => b.height >= 48 && b.left >= 0 && b.right <= width), 'Touch button bounds mismatch');
        const filename = `${enabled ? 'synthetic-enabled' : 'disabled'}-${width}x${height}.png`;
        await page.screenshot({ path: path.join(output, filename), fullPage: true });
        report.layouts.push({ width, height, enabled, filename, no_horizontal_overflow: true, button_targets_48px: true });
      } finally { await context.close(); }
    }
  }
  const posts = [], gets = [];
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, serviceWorkers: 'block' });
  try {
    await setup(context, { posts, gets });
    const first = await open(context), second = await open(context);
    await Promise.all([confirm(first), confirm(second)]);
    await Promise.all([first.locator('#delete-button').click(), second.locator('#delete-button').click()]);
    await first.waitForFunction(() => !document.getElementById('check-button').disabled);
    await second.waitForFunction(() => !document.getElementById('check-button').disabled);
    requireCheck(posts.length === 1, 'Concurrent tabs dispatched duplicate deletion');
    const journal = await first.evaluate(async () => {
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('waddle-wars-account-deletion', 1);
        request.onsuccess = () => resolve(request.result); request.onerror = () => reject(new Error('storage unavailable'));
      });
      const tx = db.transaction(['journal'], 'readonly');
      const records = await new Promise((resolve, reject) => {
        const request = tx.objectStore('journal').getAll();
        request.onsuccess = () => resolve(request.result); request.onerror = () => reject(new Error('storage unavailable'));
      });
      const strict = db.transaction(['journal'], 'readwrite', { durability: 'strict' });
      const supported = strict.durability === 'strict'; strict.abort(); db.close();
      return { count: records.length, state: records[0]?.state, receiptValid: /^[0-9a-f]{64}$/.test(records[0]?.receipt), strictHintSupported: supported };
    });
    requireCheck(journal.count === 1 && journal.state === 'retired' && journal.receiptValid && journal.strictHintSupported,
      'Actual IndexedDB persistence/durability contract mismatch');
    await first.evaluate(() => localStorage.setItem('synthetic-sign-out', 'true'));
    await first.close(); await second.close();
    const restarted = await open(context);
    await restarted.getByText('Not signed in', { exact: true }).waitFor();
    await restarted.waitForFunction(() => !document.getElementById('check-button').disabled);
    await restarted.locator('#check-button').click();
    await restarted.getByText('Deletion status is not confirmed. Keep this browser request record and use Check status later.', { exact: true }).waitFor();
    requireCheck(gets.length === 1 && posts.length === 1, 'Signed-out check retried destructive POST');
    await restarted.screenshot({ path: path.join(output, 'signed-out-synthetic-recovery.png'), fullPage: true });
    report.real_indexeddb = { cross_tab_posts: 1, records: 1, strict_hint_supported: true, signed_out_header_only_gets: 1, unknown_status_did_not_retry_post: true };
  } finally { await context.close(); }
  requireCheck(report.page_errors === 0 && report.unexpected_requests === 0, 'Browser script or request error');
  await writeFile(path.join(output, 'report.json'), `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600 });
  console.log(JSON.stringify({ layouts: report.layouts.length, ...report.real_indexeddb, live_provider_used: false, device_acceptance: false }));
} finally { await browser.close(); }
