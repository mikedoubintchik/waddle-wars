// Static host for the web export, backed by R2.
import { handleFeedback } from './feedback.js';
import { handleTelemetry } from './telemetry.js';
//
// Why not Cloudflare Pages: Pages rejects any file over 25 MiB and the Godot
// WASM blob is ~38 MiB. R2 has no such limit, so the build lives in a bucket
// and this Worker serves it with the headers the engine needs.
//
// Cross-origin isolation (COOP/COEP) is required for SharedArrayBuffer. This
// build is single-threaded so it runs without them, but sending them keeps
// the door open for a threaded export and costs nothing.

const CONTENT_TYPES = {
  html: 'text/html; charset=utf-8',
  css: 'text/css; charset=utf-8',
  js: 'text/javascript; charset=utf-8',
  wasm: 'application/wasm',
  png: 'image/png',
  ico: 'image/x-icon',
  json: 'application/json',
  xml: 'application/xml; charset=utf-8',
  pck: 'application/octet-stream',
  // Chrome will not treat a page as installable unless its manifest arrives
  // with this exact type, so the extension has to be known here as well as in
  // the upload script.
  webmanifest: 'application/manifest+json',
  webp: 'image/webp',
  avif: 'image/avif',
};

// The engine and its data change on every deploy and carry no version in their
// names, so every one of them must revalidate. Only images may be held.
//
// index.pck used to sit on `max-age=300`, which meant a phone could keep
// serving a five-minute-old build -- and in practice iOS holds it longer than
// that. A fix could be deployed, verified against the origin, and still not be
// what the player was running. Revalidation is only affordable because of the
// If-None-Match handling below: without it, every reload re-downloads ~38 MB.
function cacheControl(key) {
  if (/^oauth-feature(?:-720)?-[0-9a-f]{8}\.(?:avif|webp)$/.test(key)) return 'public, max-age=31536000, immutable';
  if (key.endsWith('.png')) return 'public, max-age=86400';
  // The entry document names the versioned pack URL, so holding a stale copy
  // of it pins the whole build. It is 15 KB; never cache it.
  if (key === 'index.html') return 'no-store';
  return 'public, max-age=0, must-revalidate';
}

function seoHeaders(headers, key) {
  if (key === 'index.html') headers.set('Link', '<https://play.waddlewars.io/>; rel="canonical"');
  if (/^releases\/[a-zA-Z0-9_-]+\/index\.html$/.test(key)) headers.set('X-Robots-Tag', 'noindex');
}

async function recordCta(request, env) {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  if (request.headers.get('Origin') !== 'https://waddlewars.io') return new Response('Forbidden', { status: 403 });
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) {
    return new Response('Expected JSON', { status: 415 });
  }
  if (Number(request.headers.get('Content-Length') || 0) > 256) {
    return new Response('Too long', { status: 413 });
  }
  let data;
  try {
    const body = await request.text();
    if (new TextEncoder().encode(body).length > 256) return new Response('Too long', { status: 413 });
    data = JSON.parse(body);
  } catch { return new Response('Invalid JSON', { status: 400 }); }
  const valid = data && typeof data === 'object' && !Array.isArray(data) &&
    ((data.event === 'play_browser' && ['nav', 'hero'].includes(data.placement)) ||
     (data.event === 'google_play' && ['hero', 'mobile'].includes(data.placement)));
  if (!valid) return new Response('Invalid event', { status: 400 });
  if (!env.CTA_CLICKS || !env.CTA_LIMITER) return new Response('Analytics unavailable', { status: 503 });
  try {
    const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
    const { success } = await env.CTA_LIMITER.limit({ key: `cta:${ip}` });
    if (!success) return new Response('Too many events', { status: 429 });
    // Store only destination and placement. No identity, IP, or user agent.
    env.CTA_CLICKS.writeDataPoint({ blobs: [data.event, data.placement], indexes: [data.event] });
  } catch { return new Response('Analytics unavailable', { status: 503 }); }
  return new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store' } });
}

// A release pack can exceed Wrangler's per-object upload limit. Immutable
// parts are joined as a stream at the origin; the browser receives the exact
// original PCK, with no extra client allocation or change to Godot's loader.
async function splitPack(request, env, key) {
  if (!/^releases\/[a-zA-Z0-9_-]+\/index\.pck$/.test(key)) return null;
  const manifest = await env.SITE.get(`${key}.parts.json`, { onlyIf: request.headers });
  if (manifest === null) return null;
  const headers = new Headers({
    'Content-Type': 'application/octet-stream',
    'Cache-Control': cacheControl(key),
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'cross-origin',
    etag: manifest.httpEtag,
  });
  if (!manifest.body) return new Response(null, { status: 304, headers });
  if (manifest.size > 8192) return new Response('Invalid pack manifest', { status: 502 });
  let spec;
  try { spec = await new Response(manifest.body).json(); }
  catch { return new Response('Invalid pack manifest', { status: 502 }); }
  if (!spec || typeof spec !== 'object' || spec.version !== 1 || !Array.isArray(spec.parts) || spec.parts.length < 1 || spec.parts.length > 16
      || !Number.isSafeInteger(spec.bytes) || spec.bytes < 1
      || !/^[0-9a-f]{64}$/.test(spec.sha256 || '')
      || spec.parts.some((p, i) => !p || p.key !== `${key}.part${i}` || !Number.isSafeInteger(p.bytes)
          || p.bytes < 1 || p.bytes > 100 * 1024 * 1024)
      || spec.parts.reduce((sum, p) => sum + p.bytes, 0) !== spec.bytes) {
    return new Response('Invalid pack manifest', { status: 502 });
  }
  headers.set('Content-Length', String(spec.bytes));
  if (request.method === 'HEAD') return new Response(null, { headers });
  let index = 0, reader = null, remaining = 0, cancelled = false, cancelReason;
  const body = new ReadableStream({
    async pull(controller) {
      try {
        while (true) {
          if (reader === null) {
            if (index === spec.parts.length) { controller.close(); return; }
            const part = spec.parts[index++];
            const object = await env.SITE.get(part.key);
            if (cancelled) { if (object?.body) await object.body.cancel(cancelReason); return; }
            if (!object?.body || object.size !== part.bytes) throw new Error('Incomplete release pack');
            reader = object.body.getReader(); remaining = part.bytes;
          }
          const next = await reader.read();
          if (cancelled) return;
          if (next.done) {
            reader.releaseLock(); reader = null;
            if (remaining !== 0) throw new Error('Truncated release pack');
            continue;
          }
          remaining -= next.value.byteLength;
          if (remaining < 0) throw new Error('Oversized release pack part');
          controller.enqueue(next.value);
          return;
        }
      } catch (error) {
        if (reader) await reader.cancel().catch(() => {});
        if (!cancelled) controller.error(error);
      }
    },
    async cancel(reason) {
      cancelled = true; cancelReason = reason;
      if (reader) await reader.cancel(reason);
    },
  });
  // Workers derives Content-Length from the stream type. Preserve accurate
  // download progress without buffering the pack in memory.
  const output = typeof FixedLengthStream === 'function'
    ? body.pipeThrough(new FixedLengthStream(spec.bytes)) : body;
  return new Response(output, { headers });
}

export default {
  async scheduled(_event, env) {
    // One small probe every five minutes checks both delivery and the public
    // leaderboard's database query. Alert rules watch these fixed error codes.
    try {
      const [home, game] = await Promise.all([
        env.SITE.head('oauth-home.html'), env.SITE.head('index.html'),
      ]);
      if (!home || !game) console.error('monitor: web_entries_unavailable');
    } catch { console.error('monitor: web_r2_unavailable'); }
    try {
      const response = await fetch('https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev/api/leaderboard?mode=runner&course=runner&limit=1', {
        headers: { 'User-Agent': 'WaddleWarsHealth/1' },
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok || !Array.isArray((await response.json()).entries)) {
        console.error('monitor: leaderboard_unavailable');
      }
    } catch { console.error('monitor: leaderboard_unavailable'); }
  },
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === 'www.waddlewars.io') {
      url.hostname = 'waddlewars.io';
      return Response.redirect(url.toString(), 308);
    }
    if (url.pathname === '/api/feedback') {
      if (url.hostname !== 'waddlewars.io') return new Response('Not found', { status: 404 });
      return handleFeedback(request, env);
    }
    if (url.pathname === '/api/analytics') {
      if (url.hostname !== 'waddlewars.io') return new Response('Not found', { status: 404 });
      return recordCta(request, env);
    }
    if (url.pathname === '/api/telemetry') {
      if (url.hostname !== 'waddlewars.io') return new Response('Not found', { status: 404 });
      return handleTelemetry(request, env);
    }
    if (url.pathname === '/api/health') {
      if (request.method !== 'GET' && request.method !== 'HEAD') return new Response(null, { status: 405 });
      try {
        const [home, game] = await Promise.all([
          env.SITE.head('oauth-home.html'), env.SITE.head('index.html'),
        ]);
        if (!home || !game) throw new Error('missing entry document');
        return new Response(request.method === 'HEAD' ? null : '{"ok":true}', {
          headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
        });
      } catch {
        console.error('web health check failed: R2 entry document unavailable');
        return new Response(request.method === 'HEAD' ? null : '{"ok":false}', {
          status: 503, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
        });
      }
    }
    let key = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
    // The new apex is a readable public home for visitors and OAuth review.
    // The game remains at play.waddlewars.io and the legacy hostname.
    if (key === '' && url.hostname === 'waddlewars.io') {
      key = 'oauth-home.html';
    } else if (key === '' || key.endsWith('/')) {
      key += 'index.html';
    }

    // Answer the conditional request without a body when the client already
    // holds this exact object. This is what makes must-revalidate cheap: a
    // reload costs one small round trip instead of the whole WASM + pck.
    const object = await env.SITE.get(key, {
      onlyIf: request.headers,
    });
    if (object === null) {
      const pack = await splitPack(request, env, key);
      if (pack) return pack;
      return new Response('Not found', { status: 404 });
    }
    const ext0 = key.split('.').pop().toLowerCase();
    if (!('body' in object) || object.body === undefined) {
      const notModified = new Headers();
      notModified.set('Cache-Control', cacheControl(key));
      notModified.set('Cross-Origin-Opener-Policy', 'same-origin');
      notModified.set('Cross-Origin-Embedder-Policy', 'require-corp');
      notModified.set('Cross-Origin-Resource-Policy', 'cross-origin');
      seoHeaders(notModified, key);
      notModified.set('etag', object.httpEtag);
      return new Response(null, { status: 304, headers: notModified });
    }

    const ext = ext0;
    const headers = new Headers();
    headers.set('Content-Type', CONTENT_TYPES[ext] || 'application/octet-stream');
    headers.set('Cache-Control', cacheControl(key));
    headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
    headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
    seoHeaders(headers, key);
    headers.set('etag', object.httpEtag);
    return new Response(object.body, { headers });
  },
};
