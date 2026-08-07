// Static host for the web export, backed by R2.
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
  js: 'text/javascript; charset=utf-8',
  wasm: 'application/wasm',
  png: 'image/png',
  json: 'application/json',
  pck: 'application/octet-stream',
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
  if (key.endsWith('.png')) return 'public, max-age=86400';
  return 'public, max-age=0, must-revalidate';
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    let key = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
    if (key === '' || key.endsWith('/')) key += 'index.html';

    // Answer the conditional request without a body when the client already
    // holds this exact object. This is what makes must-revalidate cheap: a
    // reload costs one small round trip instead of the whole WASM + pck.
    const object = await env.SITE.get(key, {
      onlyIf: request.headers,
    });
    if (object === null) {
      return new Response('Not found', { status: 404 });
    }
    const ext0 = key.split('.').pop().toLowerCase();
    if (!('body' in object) || object.body === undefined) {
      const notModified = new Headers();
      notModified.set('Cache-Control', cacheControl(key));
      notModified.set('Cross-Origin-Opener-Policy', 'same-origin');
      notModified.set('Cross-Origin-Embedder-Policy', 'require-corp');
      notModified.set('Cross-Origin-Resource-Policy', 'cross-origin');
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
    headers.set('etag', object.httpEtag);
    return new Response(object.body, { headers });
  },
};
