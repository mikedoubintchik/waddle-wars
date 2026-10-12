const encoder = new TextEncoder();
const CATEGORIES = new Set(['bug', 'idea', 'other']);
const ORIGINS = new Set([
  'https://waddlewars.io',
  'https://play.waddlewars.io',
  'https://waddlewars.ninjaconsulting.ai',
]);

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

function validEmail(value) {
  return value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export async function handleFeedback(request, env) {
  const origin = request.headers.get('Origin');
  if (!ORIGINS.has(origin)) {
    return json({ error: 'Invalid origin' }, 403);
  }
  // Native clients send the game origin explicitly. Browser clients supply it
  // themselves. Origin is a browser boundary, not a substitute for rate limits.
  const response = request.method === 'OPTIONS'
    ? new Response(null, { status: 204 })
    : await submitFeedback(request, env);
  response.headers.set('Access-Control-Allow-Origin', origin);
  response.headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  response.headers.set('Vary', 'Origin');
  return response;
}

async function submitFeedback(request, env) {
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) {
    return json({ error: 'Expected JSON' }, 415);
  }
  const declaredSize = Number(request.headers.get('Content-Length') || 0);
  if (declaredSize > 12000) return json({ error: 'Feedback too long' }, 413);
  let data;
  try {
    const raw = await request.text();
    if (encoder.encode(raw).length > 12000) return json({ error: 'Feedback too long' }, 413);
    data = JSON.parse(raw);
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return json({ error: 'Invalid feedback' }, 400);
  }
  // Hidden field catches simple bots without revealing which check fired.
  if (data.website) return json({ ok: true });
  const category = data.category;
  const message = typeof data.message === 'string' ? data.message.trim() : '';
  const email = typeof data.email === 'string' ? data.email.trim() : '';
  const context = typeof data.context === 'string' ? data.context.trim() : '';
  if (!CATEGORIES.has(category) || message.length < 10 || message.length > 2000 ||
      context.length > 160 || /[\r\n]/.test(context) || (email && !validEmail(email))) {
    return json({ error: 'Check category, message, and email' }, 400);
  }
  if (!env.FEEDBACK_LIMITER || !env.AWS_ACCESS_KEY_ID || !env.AWS_SECRET_ACCESS_KEY) {
    return json({ error: 'Feedback unavailable. Please email support.' }, 503);
  }
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const { success } = await env.FEEDBACK_LIMITER.limit({ key: `feedback:${ip}` });
  if (!success) return json({ error: 'Too many messages. Try again later.' }, 429);
  try {
    await sendFeedbackEmail(env, { category, message, email, context });
  } catch {
    return json({ error: 'Could not send feedback. Please email support.' }, 502);
  }
  return json({ ok: true });
}

async function sendFeedbackEmail(env, feedback) {
  const region = env.AWS_REGION || 'us-east-1';
  const from = env.SES_FROM_EMAIL || 'support@waddlewars.io';
  const to = env.FEEDBACK_TO_EMAIL || 'support@waddlewars.io';
  const payload = JSON.stringify({
    FromEmailAddress: from,
    Destination: { ToAddresses: [to] },
    ...(feedback.email ? { ReplyToAddresses: [feedback.email] } : {}),
    Content: { Simple: {
      Subject: { Data: `Waddle Wars feedback: ${feedback.category}`, Charset: 'UTF-8' },
      Body: { Text: { Data: [
        `Category: ${feedback.category}`,
        `Reply email: ${feedback.email || 'Not provided'}`,
        ...(feedback.context ? [`Game: ${feedback.context}`] : []),
        '',
        feedback.message,
      ].join('\n'), Charset: 'UTF-8' } },
    } },
  });
  const endpoint = `https://email.${region}.amazonaws.com/v2/email/outbound-emails`;
  const headers = await awsHeaders({
    accessKeyId: env.AWS_ACCESS_KEY_ID,
    secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
    region,
    payload,
  });
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' },
    body: payload,
  });
  if (!response.ok) throw new Error(`SES ${response.status}`);
}

async function sha256Hex(value) {
  const bytes = typeof value === 'string' ? encoder.encode(value) : value;
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    byte => byte.toString(16).padStart(2, '0')).join('');
}

async function hmac(keyBytes, value) {
  const key = await crypto.subtle.importKey('raw', keyBytes,
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(value)));
}

async function awsHeaders({ accessKeyId, secretAccessKey, region, payload }) {
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const date = amzDate.slice(0, 8);
  const signedHeaders = 'content-type;host;x-amz-date';
  const canonicalRequest = [
    'POST', '/v2/email/outbound-emails', '',
    `content-type:application/json\nhost:email.${region}.amazonaws.com\nx-amz-date:${amzDate}\n`,
    signedHeaders, await sha256Hex(payload),
  ].join('\n');
  const scope = `${date}/${region}/ses/aws4_request`;
  const stringToSign = ['AWS4-HMAC-SHA256', amzDate, scope,
    await sha256Hex(canonicalRequest)].join('\n');
  const kDate = await hmac(encoder.encode(`AWS4${secretAccessKey}`), date);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, 'ses');
  const signingKey = await hmac(kService, 'aws4_request');
  const signature = Array.from(await hmac(signingKey, stringToSign),
    byte => byte.toString(16).padStart(2, '0')).join('');
  return {
    Authorization: `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`,
    'x-amz-date': amzDate,
  };
}
