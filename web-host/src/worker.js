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

// The engine and its data change on every deploy and are content-addressed by
// nothing, so they must revalidate; images are safe to hold longer.
function cacheControl(key) {
  if (key.endsWith('.png')) return 'public, max-age=86400';
  if (key === 'index.html') return 'public, max-age=0, must-revalidate';
  return 'public, max-age=300';
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    let key = decodeURIComponent(url.pathname.replace(/^\/+/, ''));
    if (key === '' || key.endsWith('/')) key += 'index.html';

    const object = await env.SITE.get(key);
    if (object === null) {
      return new Response('Not found', { status: 404 });
    }

    const ext = key.split('.').pop().toLowerCase();
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
