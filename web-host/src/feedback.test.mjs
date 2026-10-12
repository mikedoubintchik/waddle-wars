import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { handleFeedback } from './feedback.js';

globalThis.crypto ??= webcrypto;

const endpoint = 'https://waddlewars.io/api/feedback';
const env = {
  FEEDBACK_LIMITER: { limit: async () => ({ success: true }) },
  AWS_ACCESS_KEY_ID: 'test-key',
  AWS_SECRET_ACCESS_KEY: 'test-secret',
  AWS_REGION: 'us-east-1',
  SES_FROM_EMAIL: 'support@waddlewars.io',
  FEEDBACK_TO_EMAIL: 'support@waddlewars.io',
};

function request(body, headers = {}) {
  return new Request(endpoint, {
    method: 'POST',
    headers: { Origin: 'https://waddlewars.io', 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

test('valid feedback sends SES mail with reply address', async () => {
  const originalFetch = globalThis.fetch;
  let sent;
  globalThis.fetch = async (url, options) => {
    sent = { url, options };
    return new Response('{}', { status: 200 });
  };
  try {
    const response = await handleFeedback(request({
      category: 'bug', message: 'Jump button stopped responding.', email: 'player@example.com',
    }), env);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true });
    assert.equal(sent.url, 'https://email.us-east-1.amazonaws.com/v2/email/outbound-emails');
    assert.match(sent.options.headers.Authorization, /^AWS4-HMAC-SHA256 /);
    const mail = JSON.parse(sent.options.body);
    assert.equal(mail.FromEmailAddress, 'support@waddlewars.io');
    assert.deepEqual(mail.Destination.ToAddresses, ['support@waddlewars.io']);
    assert.deepEqual(mail.ReplyToAddresses, ['player@example.com']);
    assert.match(mail.Content.Simple.Body.Text.Data, /Jump button stopped responding/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('game origins support preflight and readable validation errors', async () => {
  for (const origin of ['https://play.waddlewars.io', 'https://waddlewars.ninjaconsulting.ai']) {
    const preflight = await handleFeedback(new Request(endpoint, {
      method: 'OPTIONS', headers: { Origin: origin },
    }), env);
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), origin);
    assert.equal(preflight.headers.get('Access-Control-Allow-Headers'), 'Content-Type');
    const invalid = await handleFeedback(request({ category: 'bug', message: '' }, { Origin: origin }), env);
    assert.equal(invalid.status, 400);
    assert.equal(invalid.headers.get('Access-Control-Allow-Origin'), origin);
  }
  const blocked = await handleFeedback(new Request(endpoint, {
    method: 'OPTIONS', headers: { Origin: 'https://evil.example' },
  }), env);
  assert.equal(blocked.status, 403);
  assert.equal(blocked.headers.get('Access-Control-Allow-Origin'), null);
});

test('optional build context and recipient default reach SES without requiring email', async () => {
  const originalFetch = globalThis.fetch;
  let mail;
  globalThis.fetch = async (_url, options) => {
    mail = JSON.parse(options.body);
    return new Response('{}');
  };
  try {
    const response = await handleFeedback(request({ category: 'other', message: 'The new snow looks great.',
      context: 'local-test | macOS' }, { Origin: 'https://play.waddlewars.io' }), { ...env, FEEDBACK_TO_EMAIL: undefined });
    assert.equal(response.status, 200);
    assert.deepEqual(mail.Destination.ToAddresses, ['support@waddlewars.io']);
    assert.equal(mail.ReplyToAddresses, undefined);
    assert.match(mail.Content.Simple.Body.Text.Data, /Game: local-test \| macOS/);
  } finally { globalThis.fetch = originalFetch; }
});

test('invalid categories, emails, context and oversized requests never send', async () => {
  const valid = { category: 'bug', message: 'Enough detail about this bug.' };
  for (const body of [
    { ...valid, category: 'spam' }, { ...valid, email: 'not-an-email' },
    { ...valid, email: 'a@b.com\r\nBcc: spam@example.com' },
    { ...valid, context: 'x'.repeat(161) }, { ...valid, context: 'line1\nline2' },
    { ...valid, message: 'x'.repeat(2001) }, null, [],
  ]) assert.equal((await handleFeedback(request(body), env)).status, 400);
  assert.equal((await handleFeedback(request({ ...valid, message: 'x'.repeat(12001) }), env)).status, 413);
  assert.equal((await handleFeedback(request(valid, { 'Content-Type': 'text/plain' }), env)).status, 415);
});

test('rejects invalid, cross-origin, and excessive submissions before SES', async () => {
  assert.equal((await handleFeedback(request({ category: 'bug', message: 'short' }), env)).status, 400);
  assert.equal((await handleFeedback(request({ category: 'bug', message: 'A useful report here.' },
    { Origin: 'https://evil.example' }), env)).status, 403);
  assert.equal((await handleFeedback(request({ category: 'bug', message: 'A useful report here.' }),
    { ...env, FEEDBACK_LIMITER: { limit: async () => ({ success: false }) } })).status, 429);
  assert.equal((await handleFeedback(request({ category: 'bug', message: 'A useful report here.' }),
    { ...env, AWS_ACCESS_KEY_ID: '' })).status, 503);
  assert.equal((await handleFeedback(request({ website: 'spam.example' }), env)).status, 200);
});

test('SES failure stays visible to visitor', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('{}', { status: 403 });
  try {
    const response = await handleFeedback(request({ category: 'idea', message: 'Please add a new race mode.' }), env);
    assert.equal(response.status, 502);
    assert.match((await response.json()).error, /Could not send/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
