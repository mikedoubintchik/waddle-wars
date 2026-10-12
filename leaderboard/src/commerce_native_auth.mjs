import { CommerceError, boundedText, sha256 } from './commerce_providers.mjs';
import { requireActiveSubject } from './account_lifecycle.mjs';
import { nativeStorageSubject, providerSubject, NATIVE_SUBJECT_PREFIX } from './native_accounts_policy.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const VERIFIER = /^[A-Za-z0-9_-]{43,128}$/;
const CALLBACK_CODE = /^[A-Za-z0-9_-]{43}$/;
const changedRows = result => Number(result?.meta?.changes ?? result?.changes ?? 0);
const nowSeconds = () => Math.floor(Date.now() / 1000);

function configuration(env, request) {
  if (env.COMMERCE_NATIVE_AUTH_ENABLED !== 'true' || !env.CLERK_SECRET_KEY ||
      !env.COMMERCE_AUTH_LIMITER ||
      !/^pk_(test|live)_[A-Za-z0-9]+$/.test(env.COMMERCE_CLERK_PUBLISHABLE_KEY || '')) {
    throw new CommerceError('native_auth_unavailable', 503);
  }
  let origin; let issuer;
  try { origin = new URL(env.COMMERCE_NATIVE_AUTH_ORIGIN); issuer = new URL(env.CLERK_ISSUER); }
  catch { throw new CommerceError('native_auth_unavailable', 503); }
  if (origin.protocol !== 'https:' || origin.origin !== env.COMMERCE_NATIVE_AUTH_ORIGIN ||
      issuer.protocol !== 'https:' || issuer.username || issuer.password || issuer.search || issuer.hash ||
      !String(env.COMMERCE_ALLOWED_ORIGINS || '').split(',').map((value) => value.trim()).includes(origin.origin) ||
      new URL(request.url).origin !== origin.origin) throw new CommerceError('native_auth_unavailable', 503);
  const incoming = request.headers.get('Origin');
  if (incoming && incoming !== origin.origin) throw new CommerceError('origin_not_allowed', 403);
  return { origin: origin.origin, issuer: issuer.origin };
}

async function jsonBody(request) {
  try {
    const body = JSON.parse(await boundedText(request, 4096));
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
    return body;
  } catch (error) {
    if (error instanceof CommerceError) throw error;
    throw new CommerceError('invalid_json');
  }
}

function response(env, request, value, status = 200) {
  const origin = request.headers.get('Origin');
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json',
    'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', Vary: 'Origin',
    ...(origin === env.COMMERCE_NATIVE_AUTH_ORIGIN ? { 'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Allow-Headers': 'Authorization, Content-Type' } : {}) } });
}

async function pkceChallenge(verifier) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function requestWithVerifier(env, body, { allowExchanged = false } = {}) {
  if (!UUID.test(body.request_id || '') || !VERIFIER.test(body.verifier || '')) throw new CommerceError('invalid_auth_request');
  const row = await env.DB.prepare('SELECT * FROM commerce_native_auth_requests WHERE request_id = ?1').bind(body.request_id).first();
  if (!row || row.challenge !== await pkceChallenge(body.verifier) || row.state === 'cancelled') throw new CommerceError('invalid_auth_request', 401);
  if (row.expires_at <= nowSeconds() && !(allowExchanged && row.state === 'exchanged')) throw new CommerceError('auth_request_expired', 410);
  return row;
}

async function clerkToken(env, userId, sessionId, authenticate, fetcher) {
  await requireActiveSubject(env, userId);
  const providerUserId = providerSubject(env, userId);
  if (!/^sess_[A-Za-z0-9]+$/.test(sessionId || '')) throw new CommerceError('auth_session_invalid', 401);
  const headers = { Authorization: `Bearer ${env.CLERK_SECRET_KEY}`, 'Content-Type': 'application/json' };
  const check = await fetcher(`https://api.clerk.com/v1/sessions/${sessionId}`, { headers });
  if (!check.ok) throw new CommerceError('auth_session_unavailable', check.status === 404 ? 401 : 503);
  const session = await check.json();
  if (session.id !== sessionId || session.user_id !== providerUserId || session.status !== 'active') throw new CommerceError('auth_session_invalid', 401);
  const issued = await fetcher(`https://api.clerk.com/v1/sessions/${sessionId}/tokens`, {
    method: 'POST', headers, body: JSON.stringify({ expires_in_seconds: 60 }),
  });
  if (!issued.ok) throw new CommerceError('auth_session_unavailable', 503);
  const token = (await issued.json()).jwt;
  if (typeof token !== 'string') throw new CommerceError('auth_session_unavailable', 503);
  // Verify the fresh provider JWT with the same host verifier as every game API.
  const claims = await authenticate(env, new Request('https://native-auth.internal', { headers: { Authorization: `Bearer ${token}` } }));
  if (claims?.sub !== providerUserId || claims?.sid !== sessionId || !Number.isFinite(claims.exp) || claims.exp <= nowSeconds()) {
    throw new CommerceError('auth_session_invalid', 401);
  }
  await requireActiveSubject(env, userId);
  return { token, user_id: providerUserId, expires_in: Math.min(claims.exp - nowSeconds(), 60) };
}

// iOS presents this inside ASWebAuthenticationSession. Keep explicit account
// confirmation: a browser gesture or sessionStorage marker cannot prove that
// an authorization URL was opened by the same device that owns the PKCE proof.
// The callback contains no credential, and /token still requires that proof.
function iosAuthorizationMarkup(id, nonce) {
  const callback = `com.blubberandbyte.waddlewars.auth://native-auth/return?request_id=${id}`;
  return `<main class="ios"><h1>Sign in to Waddle Wars</h1><p id="notice" role="status" aria-live="polite">Loading secure sign-in…</p><div id="signin"></div><button id="connect" hidden disabled>Continue</button><p class="help">Continue only if you opened sign-in from Waddle Wars on this device.</p><details class="help"><summary>Security details</summary><p>Connection code: <strong>${id.slice(0, 8).toUpperCase()}</strong></p><p>This code should match the one shown in your game.</p></details></main>
<script nonce="${nonce}">(()=>{
  const button=document.getElementById('connect'),notice=document.getElementById('notice'),signin=document.getElementById('signin');
  const requestID=${JSON.stringify(id)};
  let mounted=false,phase='idle',loads=0;
  const fail=message=>{phase='failed';button.hidden=true;button.disabled=true;notice.textContent=message};
  async function connect(){
    if(phase!=='idle')return;
    const session=window.Clerk.session,user=window.Clerk.user;
    if(!session||!user)return;
    phase='connecting';button.disabled=true;button.hidden=true;notice.textContent='Signing you in…';
    try{
      const token=await session.getToken();
      if(!token||window.Clerk.session!==session||window.Clerk.user!==user)throw Error();
      const result=await fetch('/api/commerce/native-auth/complete',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify({request_id:requestID})});
      if(!result.ok||(await result.json()).connected!==true)throw Error();
      phase='done';notice.textContent='Signed in. Returning to Waddle Wars…';window.location.replace(${JSON.stringify(callback)});
    }catch{fail('Sign-in could not finish. Close this sheet and try again from the game.')}
  }
  button.onclick=connect;
  async function setup(){try{
    if(!window.Clerk){if(++loads>150){fail('Sign-in is unavailable. Close this sheet and try again.');return}setTimeout(setup,100);return}
    await window.Clerk.load();
    const sync=()=>{
      if(phase!=='idle')return;
      if(window.Clerk.user&&window.Clerk.session){
        if(mounted){window.Clerk.unmountSignIn(signin);mounted=false}
        const name=window.Clerk.user.primaryEmailAddress?.emailAddress||window.Clerk.user.fullName||'your account';
        notice.textContent='Continue with '+name+'?';button.textContent='Continue to Waddle Wars';button.hidden=false;button.disabled=false;
      }else{
        button.hidden=true;button.disabled=true;notice.textContent='Sign in to save your progress.';
        if(!mounted){window.Clerk.mountSignIn(signin,{routing:'virtual',forceRedirectUrl:window.location.href,signUpForceRedirectUrl:window.location.href});mounted=true}
      }
    };
    sync();window.Clerk.addListener(sync);
  }catch{fail('Sign-in is unavailable. Close this sheet and try again.')}}
  setup();
})();</script>`;
}

// v2 may finish as soon as Clerk signs in: the requester cannot exchange
// until this browser delivers its one-use proof through the native callback.
function iosV2AuthorizationMarkup(id, nonce) {
  const callback = `com.blubberandbyte.waddlewars.auth://native-auth/return?request_id=${id}&code=`;
  return `<main class="ios"><p id="notice" role="status" aria-live="polite">Loading secure sign-in…</p><div id="signin"></div></main>
<script nonce="${nonce}">(()=>{
  const notice=document.getElementById('notice'),signin=document.getElementById('signin');
  let mounted=false,phase='idle',loads=0;
  const fail=()=>{phase='failed';notice.textContent='Sign-in could not finish. Close this sheet and try again from the game.'};
  async function complete(){
    if(phase!=='idle')return;
    const session=window.Clerk.session,user=window.Clerk.user;if(!session||!user)return;
    phase='connecting';notice.textContent='Signing you in…';
    try{
      const token=await session.getToken();
      if(!token||window.Clerk.session!==session||window.Clerk.user!==user)throw Error();
      const result=await fetch('/api/commerce/native-auth/complete',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify({request_id:${JSON.stringify(id)},flow_version:2})});
      if(!result.ok)throw Error();const reply=await result.json();
      if(reply.connected!==true||typeof reply.callback_code!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(reply.callback_code))throw Error();
      phase='done';notice.textContent='Returning to Waddle Wars…';window.location.replace(${JSON.stringify(callback)}+reply.callback_code);
    }catch{fail()}
  }
  async function setup(){try{
    if(!window.Clerk){if(++loads>150){fail();return}setTimeout(setup,100);return}
    await window.Clerk.load();
    const sync=()=>{if(phase!=='idle')return;
      if(window.Clerk.user&&window.Clerk.session){if(mounted){window.Clerk.unmountSignIn(signin);mounted=false}void complete()}
      else{notice.textContent='Sign in to save your progress.';if(!mounted){window.Clerk.mountSignIn(signin,{routing:'virtual',forceRedirectUrl:window.location.href,signUpForceRedirectUrl:window.location.href});mounted=true}}
    };sync();window.Clerk.addListener(sync);
  }catch{fail()}}setup();
})();</script>`;
}

function authorizationPage(env, configurationValue, id, nonce, presentation, flowVersion) {
  const scriptURL = `${configurationValue.issuer}/npm/@clerk/clerk-js@5/dist/clerk.browser.js`;
  const pk = env.COMMERCE_CLERK_PUBLISHABLE_KEY;
  // The iOS callback is a fixed, credential-free native-session return. It
  // never authorizes the device; /token still requires its private PKCE proof.
  const callback = presentation === 'ios' ? `com.blubberandbyte.waddlewars.auth://native-auth/return?request_id=${id}` : null;
  const returnScript = callback ? `window.location.replace(${JSON.stringify(callback)});` : '';
  const html = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${presentation === 'ios' ? 'Sign in to Waddle Wars' : 'Connect Waddle Wars'}</title>
<style nonce="${nonce}">body{margin:0;background:#102038;color:#edf5ff;font:18px system-ui}main{max-width:520px;margin:6vh auto;padding:24px}h1{font-size:30px}#connect{padding:14px 22px;border:0;border-radius:12px;background:#80d0f7;color:#102038;font:700 18px system-ui}#connect:disabled{opacity:.4}#notice{line-height:1.5}#signin{margin:24px 0}.ios{box-sizing:border-box;max-width:440px;margin:24px auto;padding:24px;background:#faf7ef;color:#112b50;border-radius:20px}.ios h1{font-size:26px;line-height:1.2;margin:0 0 16px}.ios #signin{display:flex;justify-content:center;margin:20px 0;min-width:0}.ios #signin>div{width:100%;max-width:100%;min-width:0}.ios #signin .cl-rootBox,.ios #signin .cl-cardBox,.ios #signin .cl-card{max-width:100%;min-width:0;box-sizing:border-box}.ios .help{font-size:14px;line-height:1.5;color:#49617a}.ios #connect{background:#ef4d3e;color:white;width:100%}@media(max-width:480px){.ios{margin:16px 12px;padding:20px 12px}}#connect[hidden]{display:none}</style>
<script nonce="${nonce}" async crossorigin="anonymous" data-clerk-publishable-key="${pk}" src="${scriptURL}"></script>
${presentation === 'ios' ? (flowVersion === 2 ? iosV2AuthorizationMarkup(id, nonce) : iosAuthorizationMarkup(id, nonce)) : `<main><h1>Connect Waddle Wars</h1><p>Connection code: <strong>${id.slice(0, 8).toUpperCase()}</strong></p><p>Match this code with your game. Only connect if you started sign-in on your own device.</p><p id="notice">Loading account sign-in…</p><div id="signin"></div><button id="connect" disabled>Connect this account to my game</button><p>No payment occurs here. Return to the game after connecting.</p></main>
<script nonce="${nonce}">(()=>{const button=document.getElementById('connect'),notice=document.getElementById('notice'),signin=document.getElementById('signin');let mounted=false;async function setup(){try{if(!window.Clerk){setTimeout(setup,100);return}await window.Clerk.load();const sync=()=>{if(window.Clerk.user&&window.Clerk.session){button.disabled=false;notice.textContent='Signed in as '+(window.Clerk.user.primaryEmailAddress?.emailAddress||window.Clerk.user.fullName||'your account')+'.';if(mounted){window.Clerk.unmountSignIn(signin);mounted=false}}else{button.disabled=true;notice.textContent='Sign in, then connect your account.';if(!mounted){window.Clerk.mountSignIn(signin,{routing:'virtual',forceRedirectUrl:window.location.href,signUpForceRedirectUrl:window.location.href});mounted=true}}};sync();window.Clerk.addListener(sync);button.onclick=async()=>{button.disabled=true;notice.textContent='Connecting…';try{const token=await window.Clerk.session.getToken();const result=await fetch('/api/commerce/native-auth/complete',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify({request_id:'${id}'})});if(!result.ok||(await result.json()).connected!==true)throw Error();notice.textContent='Account connected. Return to Waddle Wars.';button.hidden=true;${returnScript}}catch{notice.textContent='Connection expired or unavailable. Start sign-in again from your game.'}}}catch{notice.textContent='Account sign-in unavailable. Return to your game and try again.'}}setup()})();</script>`}</html>`;
  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY',
    // Clerk's official CSP guidance requires runtime inline styles and narrowly
    // scoped fraud-protection/image/worker hosts. Scripts still require our
    // nonce or a trusted provider host; never allow arbitrary inline script.
    'Content-Security-Policy': `default-src 'none'; script-src 'nonce-${nonce}' ${configurationValue.issuer} https://challenges.cloudflare.com https://*.protect.clerk.com; style-src 'unsafe-inline'; connect-src 'self' ${configurationValue.issuer} https://*.protect.clerk.com:*; img-src ${configurationValue.issuer} https://img.clerk.com data:; worker-src 'self' blob:; frame-src ${configurationValue.issuer} https://challenges.cloudflare.com https://*.protect.clerk.com; form-action 'self'; base-uri 'none'; frame-ancestors 'none'` } });
}

export async function handleNativeAuth(request, env, authenticate, { fetcher = fetch } = {}) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (!path.startsWith('/api/commerce/native-auth/')) return null;
  try {
    const config = configuration(env, request);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204,
      headers: response(env, request, {}).headers });
    const peer = request.headers.get('CF-Connecting-IP') || 'native-auth-unknown';
    const limit = await env.COMMERCE_AUTH_LIMITER.limit({ key: `native-auth:${peer}:${path.endsWith('/start') ? 'start' : 'flow'}` });
    if (!limit.success) throw new CommerceError('auth_rate_limited', 429);
    if (['/api/commerce/native-auth/authorize', '/api/commerce/native-auth/authorize-ios', '/api/commerce/native-auth/authorize-ios-v2'].includes(path) && request.method === 'GET') {
      const id = url.searchParams.get('request_id');
      if (!UUID.test(id || '')) throw new CommerceError('invalid_auth_request');
      const row = await env.DB.prepare('SELECT * FROM commerce_native_auth_requests WHERE request_id = ?1').bind(id).first();
      if (!row || row.expires_at <= nowSeconds() || !['pending', 'approved'].includes(row.state)) throw new CommerceError('auth_request_expired', 410);
      const presentation = path.endsWith('/authorize') ? 'browser' : 'ios';
      const flowVersion = path.endsWith('/authorize-ios-v2') ? 2 : 1;
      if (row.presentation !== presentation || Number(row.flow_version || 1) !== flowVersion || [...url.searchParams.keys()].some((key) => key !== 'request_id') ||
          url.searchParams.getAll('request_id').length !== 1) throw new CommerceError('invalid_auth_request');
      return authorizationPage(env, config, id, crypto.randomUUID(), presentation, flowVersion);
    }
    if (request.method !== 'POST') throw new CommerceError('not_found', 404);
    const body = await jsonBody(request);
    if (path.endsWith('/start')) {
      if (!/^[A-Za-z0-9_-]{43}$/.test(body.challenge || '')) throw new CommerceError('invalid_auth_request');
      if (body.presentation !== undefined && body.presentation !== 'ios') throw new CommerceError('invalid_auth_request');
      if ('redirect_url' in body || 'callback_url' in body) throw new CommerceError('invalid_auth_request');
      const presentation = body.presentation === 'ios' ? 'ios' : 'browser';
      const flowVersion = body.flow_version === undefined ? 1 : body.flow_version;
      if (![1, 2].includes(flowVersion) || (flowVersion === 2 && presentation !== 'ios')) throw new CommerceError('invalid_auth_request');
      const id = crypto.randomUUID(); const now = nowSeconds();
      await env.DB.batch([
        env.DB.prepare('DELETE FROM commerce_native_auth_sessions WHERE expires_at < ?1 OR revoked = 1').bind(now),
        env.DB.prepare(`DELETE FROM commerce_native_auth_requests WHERE expires_at < ?1
          AND request_id NOT IN (SELECT request_id FROM commerce_native_auth_sessions WHERE expires_at > ?2 AND revoked = 0)`)
          .bind(now - 300, now),
      ]);
      await env.DB.prepare('INSERT INTO commerce_native_auth_requests(request_id, challenge, expires_at, created_at, presentation, flow_version) VALUES (?1, ?2, ?3, ?4, ?5, ?6)')
        .bind(id, body.challenge, now + 300, now, presentation, flowVersion).run();
      return response(env, request, { request_id: id, expires_in: 300, interval: 3,
        presentation, flow_version: flowVersion,
        authorize_url: `${config.origin}/api/commerce/native-auth/${flowVersion === 2 ? 'authorize-ios-v2' : presentation === 'ios' ? 'authorize-ios' : 'authorize'}?request_id=${id}` });
    }
    if (path.endsWith('/complete')) {
      if (request.headers.get('Origin') !== config.origin) throw new CommerceError('origin_not_allowed', 403);
      const claims = await authenticate(env, request);
      if (!claims?.sub || !/^sess_[A-Za-z0-9]+$/.test(claims.sid || '')) throw new CommerceError('unauthorized', 401);
      const userId = env.ACCOUNT_SUBJECT_PREFIX === NATIVE_SUBJECT_PREFIX ? nativeStorageSubject(claims.sub) : claims.sub;
      await requireActiveSubject(env, userId);
      const row = await env.DB.prepare('SELECT * FROM commerce_native_auth_requests WHERE request_id = ?1').bind(body.request_id || '').first();
      if (!row || row.expires_at <= nowSeconds() || !['pending', 'approved'].includes(row.state)) throw new CommerceError('auth_request_expired', 410);
      const flowVersion = body.flow_version === undefined ? 1 : body.flow_version;
      if (![1, 2].includes(flowVersion) || Number(row.flow_version || 1) !== flowVersion) throw new CommerceError('invalid_auth_request');
      if (flowVersion === 2) {
        if (row.presentation !== 'ios' || row.state !== 'pending') throw new CommerceError('auth_request_already_approved', 409);
        const bytes = crypto.getRandomValues(new Uint8Array(32));
        const code = btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
        const hash = await sha256(code), now = nowSeconds();
        const approved = await env.DB.prepare(`UPDATE commerce_native_auth_requests SET state = 'approved', user_id = ?2,
          clerk_session_id = ?3, callback_code_hash = ?4, callback_code_expires_at = ?5
          WHERE request_id = ?1 AND state = 'pending' AND expires_at > ?6 AND flow_version = 2 AND presentation = 'ios'`)
          .bind(row.request_id, userId, claims.sid, hash, Math.min(row.expires_at, now + 120), now).run();
        if (changedRows(approved) !== 1) throw new CommerceError('auth_request_already_approved', 409);
        await requireActiveSubject(env, userId);
        return response(env, request, { connected: true, callback_code: code });
      }
      if (row.state === 'approved' && (row.user_id !== userId || row.clerk_session_id !== claims.sid)) throw new CommerceError('auth_account_conflict', 409);
      await env.DB.prepare('UPDATE commerce_native_auth_requests SET state = \'approved\', user_id = ?2, clerk_session_id = ?3 WHERE request_id = ?1 AND state = \'pending\' AND expires_at > ?4')
        .bind(row.request_id, userId, claims.sid, nowSeconds()).run();
      const approved = await env.DB.prepare('SELECT user_id, clerk_session_id FROM commerce_native_auth_requests WHERE request_id = ?1').bind(row.request_id).first();
      if (approved?.user_id !== userId || approved?.clerk_session_id !== claims.sid) throw new CommerceError('auth_account_conflict', 409);
      await requireActiveSubject(env, userId);
      return response(env, request, { connected: true });
    }
    if (path.endsWith('/cancel')) {
      const row = await requestWithVerifier(env, body, { allowExchanged: true });
      await env.DB.batch([
        env.DB.prepare('UPDATE commerce_native_auth_requests SET state = \'cancelled\' WHERE request_id = ?1').bind(row.request_id),
        env.DB.prepare('UPDATE commerce_native_auth_sessions SET revoked = 1 WHERE request_id = ?1').bind(row.request_id),
      ]);
      return response(env, request, { cancelled: true });
    }
    if (path.endsWith('/token')) {
      const row = await requestWithVerifier(env, body);
      if (Number(row.flow_version || 1) === 2) {
        // The caller's verifier alone must never authorize token delivery.
        if (!CALLBACK_CODE.test(body.callback_code || '') || row.presentation !== 'ios' || row.state !== 'approved' ||
            row.callback_code_consumed_at != null || row.callback_code_expires_at <= nowSeconds() ||
            row.callback_code_hash !== await sha256(body.callback_code)) throw new CommerceError('invalid_callback_code', 401);
        const token = await clerkToken(env, row.user_id, row.clerk_session_id, authenticate, fetcher);
        const now = nowSeconds(), verifierHash = await sha256(body.verifier);
        // Recheck every immutable binding after provider I/O. One concurrent
        // exchange can consume the code; cancellation/expiry wins the fence.
        const consumed = await env.DB.prepare(`UPDATE commerce_native_auth_requests SET state = 'exchanged', callback_code_consumed_at = ?7
          WHERE request_id = ?1 AND state = 'approved' AND user_id = ?2 AND clerk_session_id = ?3
          AND callback_code_hash = ?4 AND challenge = ?5 AND callback_code_expires_at > ?6 AND expires_at > ?6
          AND callback_code_consumed_at IS NULL AND flow_version = 2 AND presentation = 'ios'`)
          .bind(row.request_id, row.user_id, row.clerk_session_id, row.callback_code_hash, row.challenge, now, now).run();
        if (changedRows(consumed) !== 1) throw new CommerceError('invalid_callback_code', 401);
        await env.DB.prepare(`INSERT INTO commerce_native_auth_sessions(request_id, verifier_hash, user_id, clerk_session_id, expires_at)
          SELECT request_id, ?2, user_id, clerk_session_id, ?5 FROM commerce_native_auth_requests
          WHERE request_id = ?1 AND user_id = ?3 AND clerk_session_id = ?4 AND state = 'exchanged'
          AND callback_code_consumed_at = ?6 AND callback_code_hash = ?7 ON CONFLICT DO NOTHING`)
          .bind(row.request_id, verifierHash, row.user_id, row.clerk_session_id, now + 86400, now, row.callback_code_hash).run();
        await requireActiveSubject(env, row.user_id);
        const active = await env.DB.prepare(`SELECT s.* FROM commerce_native_auth_sessions s
          JOIN commerce_native_auth_requests r ON r.request_id = s.request_id
          WHERE s.request_id = ?1 AND r.state = 'exchanged' AND r.flow_version = 2`).bind(row.request_id).first();
        if (!active || active.revoked || active.verifier_hash !== verifierHash || active.user_id !== row.user_id ||
            active.clerk_session_id !== row.clerk_session_id || active.expires_at <= nowSeconds()) throw new CommerceError('auth_session_invalid', 401);
        return response(env, request, token);
      }
      if (row.state === 'pending') return response(env, request, { error: 'authorization_pending' }, 409);
      if (!['approved', 'exchanged'].includes(row.state)) throw new CommerceError('invalid_auth_request', 401);
      const token = await clerkToken(env, row.user_id, row.clerk_session_id, authenticate, fetcher);
      const hash = await sha256(body.verifier);
      await env.DB.batch([
        env.DB.prepare(`INSERT INTO commerce_native_auth_sessions(request_id, verifier_hash, user_id, clerk_session_id, expires_at)
          SELECT request_id, ?2, user_id, clerk_session_id, ?5 FROM commerce_native_auth_requests
          WHERE request_id = ?1 AND user_id = ?3 AND clerk_session_id = ?4 AND state IN ('approved', 'exchanged')
          ON CONFLICT DO NOTHING`)
          .bind(row.request_id, hash, row.user_id, row.clerk_session_id, nowSeconds() + 86400),
        env.DB.prepare('UPDATE commerce_native_auth_requests SET state = \'exchanged\' WHERE request_id = ?1 AND state = \'approved\'').bind(row.request_id),
      ]);
      const active = await env.DB.prepare('SELECT * FROM commerce_native_auth_sessions WHERE request_id = ?1').bind(row.request_id).first();
      if (!active || active.revoked || active.verifier_hash !== hash || active.expires_at <= nowSeconds()) throw new CommerceError('auth_session_invalid', 401);
      await requireActiveSubject(env, active.user_id);
      return response(env, request, token);
    }
    if (path.endsWith('/refresh')) {
      if (!UUID.test(body.request_id || '') || !VERIFIER.test(body.verifier || '')) throw new CommerceError('invalid_auth_request');
      const hash = await sha256(body.verifier);
      const active = await env.DB.prepare('SELECT * FROM commerce_native_auth_sessions WHERE request_id = ?1').bind(body.request_id).first();
      if (!active || active.revoked || active.expires_at <= nowSeconds() || active.verifier_hash !== hash) throw new CommerceError('auth_session_invalid', 401);
      const token = await clerkToken(env, active.user_id, active.clerk_session_id, authenticate, fetcher);
      // Cancellation or cleanup can race the provider request. The original
      // snapshot no longer authorizes delivery; never recreate or extend it.
      const current = await env.DB.prepare('SELECT * FROM commerce_native_auth_sessions WHERE request_id = ?1').bind(body.request_id).first();
      if (!current || current.request_id !== body.request_id || current.verifier_hash !== hash ||
          current.user_id !== active.user_id || current.clerk_session_id !== active.clerk_session_id ||
          current.revoked || current.expires_at <= nowSeconds()) throw new CommerceError('auth_session_invalid', 401);
      await requireActiveSubject(env, current.user_id);
      return response(env, request, token);
    }
    throw new CommerceError('not_found', 404);
  } catch (error) {
    return response(env, request, { error: error instanceof CommerceError ? error.code : 'native_auth_unavailable' },
      error instanceof CommerceError ? error.status : 503);
  }
}
