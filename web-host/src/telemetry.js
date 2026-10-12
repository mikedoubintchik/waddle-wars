// Anonymous, low-volume game counters. Never accept arbitrary properties or IDs.
const EVENTS = new Set(['app_open', 'run_start', 'run_end', 'client_error']);
const PLATFORMS = new Set(['web', 'ios', 'android']);
const ORIGINS = new Set([
  'https://waddlewars.io',
  'https://play.waddlewars.io',
  'https://waddlewars.ninjaconsulting.ai',
]);
const ERROR_CODES = new Set(['loader', 'scene_load', 'network', 'runtime']);

function reply(status, origin) {
  const headers = new Headers({ 'Cache-Control': 'no-store' });
  if (origin) {
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Content-Type');
    headers.set('Vary', 'Origin');
  }
  return new Response(null, { status, headers });
}

export async function handleTelemetry(request, env) {
  const origin = request.headers.get('Origin');
  if (origin && !ORIGINS.has(origin)) return reply(403);
  if (request.method === 'OPTIONS') return origin ? reply(204, origin) : reply(403);
  if (request.method !== 'POST') return reply(405, origin);
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) return reply(415, origin);
  if (Number(request.headers.get('Content-Length') || 0) > 512) return reply(413, origin);
  let body;
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).length > 512) return reply(413, origin);
    body = JSON.parse(raw);
  } catch { return reply(400, origin); }
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).some(key => !['event', 'platform', 'build', 'distance', 'score', 'fish', 'code'].includes(key)) ||
      !EVENTS.has(body.event) || !PLATFORMS.has(body.platform) ||
      typeof body.build !== 'string' || !/^[a-zA-Z0-9._-]{1,48}$/.test(body.build)) return reply(400, origin);
  const metrics = ['distance', 'score', 'fish'].map(key => body[key] === undefined ? 0 : body[key]);
  if (metrics.some(value => typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1e9) ||
      (body.event !== 'run_end' && metrics.some(value => value !== 0)) ||
      (body.event === 'client_error' ? !ERROR_CODES.has(body.code) : body.code !== undefined)) return reply(400, origin);
  if (!env.GAME_EVENTS || !env.TELEMETRY_LIMITER) return reply(503, origin);
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const { success } = await env.TELEMETRY_LIMITER.limit({ key: `telemetry:${ip}` });
  if (!success) return reply(429, origin);
  // Only validated enum strings and bounded totals enter analytics. IP is used
  // for rate limiting, never written to the dataset or application logs.
  env.GAME_EVENTS.writeDataPoint({
    blobs: [body.event, body.platform, body.build, body.code || ''],
    doubles: metrics,
  });
  return reply(204, origin);
}
