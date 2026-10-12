import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
const worker = (await import(process.env.WADDLE_LEADERBOARD_WORKER
  ? pathToFileURL(process.env.WADDLE_LEADERBOARD_WORKER).href
  : '../leaderboard/src/worker.js')).default;

const ISSUER = 'https://synthetic-name-privacy.clerk.accounts.dev';
const USER = 'synthetic-player-name-privacy';
const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5',
  modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
true, ['sign', 'verify']);
const jwk = { ...await crypto.subtle.exportKey('jwk', key.publicKey), kid: 'synthetic-name-privacy' };
const b64 = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const unsigned = `${b64({ alg: 'RS256', kid: jwk.kid })}.${b64({
  sub: USER, iss: ISSUER, exp: Math.floor(Date.now() / 1000) + 600,
  name: 'Synthetic Private Name', email: 'synthetic-private-address@example.invalid',
})}`;
const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key.privateKey,
  new TextEncoder().encode(unsigned));
const token = `${unsigned}.${Buffer.from(signature).toString('base64url')}`;

class D1 {
  constructor() {
    this.db = new DatabaseSync(':memory:');
    this.db.exec(readFileSync(process.env.WADDLE_LEADERBOARD_SCHEMA
      || new URL('../leaderboard/schema.sql', import.meta.url), 'utf8'));
  }
  prepare(sql) {
    const db = this.db;
    const adapter = this;
    const make = (values = []) => {
      const statement = db.prepare(sql);
      statement.setAllowUnknownNamedParameters(true);
      const args = Object.fromEntries(values.map((value, index) => [String(index + 1), value]));
      const execute = (method) => {
        if (/^\s*INSERT INTO scores\b/.test(sql) && adapter.beforeScoreWrite) {
          const interleave = adapter.beforeScoreWrite;
          adapter.beforeScoreWrite = null;
          interleave();
        }
        return statement[method](args);
      };
      return { bind: (...bound) => make(bound), first: async () => execute('get') || null,
        run: async () => execute('run'), all: async () => ({ results: execute('all') }) };
    };
    return make();
  }
}

async function fixture(run) {
  const DB = new D1();
  const previousFetch = globalThis.fetch;
  const providerRequests = [];
  globalThis.fetch = async (url) => {
    if (String(url) === `${ISSUER}/.well-known/jwks.json`) {
      return new Response(JSON.stringify({ keys: [jwk] }));
    }
    providerRequests.push(String(url));
    return new Response(JSON.stringify({ username: 'private-login-handle',
      first_name: 'Synthetic', last_name: 'Private Name',
      email_addresses: [{ email_address: 'synthetic-private-address@example.invalid' }] }));
  };
  const env = { DB, CLERK_ISSUER: ISSUER, CLERK_SECRET_KEY: 'synthetic-unused-secret' };
  const submit = (body = {}) => worker.fetch(new Request('https://worker.example/api/scores', {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ mode: 'time', course: 'glacier', value: 20000, ...body }),
  }), env);
  try {
    await run({ DB: DB.db, env, submit });
    assert.deepEqual(providerRequests, [], 'Public score names must never fetch private account profiles');
  } finally {
    globalThis.fetch = previousFetch;
    DB.db.close();
  }
}

test('score without an explicit public handle uses Penguin, not auth identity', async () => {
  await fixture(async ({ DB, submit }) => {
    const response = await submit();
    assert.equal(response.status, 200);
    assert.equal((await response.json()).name, 'Penguin');
    assert.equal(DB.prepare('SELECT name FROM scores WHERE user_id = ?').get(USER).name, 'Penguin');
    assert.equal(DB.prepare('SELECT COUNT(*) AS n FROM profiles').get().n, 0);
  });
});

test('explicit public handle remains sanitized and is reused on later submissions', async () => {
  await fixture(async ({ DB, submit }) => {
    const response = await submit({ name: '  Ice Waddler!  ' });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).name, 'Ice Waddler');
    assert.equal(DB.prepare('SELECT name FROM profiles WHERE user_id = ?').get(USER).name, 'Ice Waddler');
    const later = await submit({ value: 19000 });
    assert.equal(later.status, 200);
    assert.equal((await later.json()).name, 'Ice Waddler');
  });
});

test('invalid custom handle cannot expose private account fallback', async () => {
  await fixture(async ({ submit }) => {
    const response = await submit({ name: '!' });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).name, 'Penguin');
  });
});

test('public leaderboard reflects safe newly submitted fallback name', async () => {
  await fixture(async ({ env, submit }) => {
    assert.equal((await submit()).status, 200);
    const response = await worker.fetch(new Request('https://worker.example/api/leaderboard?mode=time&course=glacier'), env);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.deepEqual(body.entries.map((entry) => entry.name), ['Penguin']);
    assert.equal(body.me, null);
  });
});

test('all shipped race courses accept real time records; runner and Expedition stay separate', async () => {
  await fixture(async ({ env, submit }) => {
    for (const course of ['glacier', 'aurora', 'iceberg', 'cinder', 'hollow']) {
      assert.equal((await submit({ course })).status, 200, course);
      const board = await worker.fetch(new Request(`https://worker.example/api/leaderboard?mode=time&course=${course}`), env);
      assert.equal(board.status, 200);
      assert.equal((await board.json()).entries.length, 1);
    }
    assert.equal((await submit({ mode: 'runner', course: 'runner', value: 12345 })).status, 200);
    assert.equal((await submit({ mode: 'endless', course: 'endless', value: 987 })).status, 200);
    for (const [mode, course, value] of [['runner', 'runner', 12345], ['endless', 'endless', 987]]) {
      const board = await worker.fetch(new Request(`https://worker.example/api/leaderboard?mode=${mode}&course=${course}`), env);
      const body = await board.json();
      assert.equal(board.status, 200);
      assert.deepEqual(body.entries, [{ rank: 1, name: 'Penguin', value, is_me: false }]);
      assert.equal(body.me, null);
    }
    const source = readFileSync(new URL('../scripts/courses/courses_db.gd', import.meta.url), 'utf8');
    const courses = source.match(/const ORDER: PackedStringArray = \[(.*?)\]/)[1].match(/"([^"]+)"/g).map((v) => JSON.parse(v));
    assert.deepEqual(courses, ['glacier', 'aurora', 'iceberg', 'cinder', 'hollow']);
  });
});

test('invalid cross-mode boards cannot mix time, runner and Expedition scoring systems', async () => {
  await fixture(async ({ env, submit }) => {
    for (const [mode, course] of [['time', 'runner'], ['time', 'endless'], ['runner', 'glacier'],
      ['runner', 'endless'], ['endless', 'runner'], ['endless', 'glacier'], ['invented', 'runner']]) {
      assert.equal((await submit({ mode, course })).status, 400);
      const board = await worker.fetch(new Request(`https://worker.example/api/leaderboard?mode=${mode}&course=${course}`), env);
      assert.equal(board.status, 400);
    }
    for (const value of [0, -1, 1_000_000_001]) {
      assert.equal((await submit({ mode: 'runner', course: 'runner', value })).status, 400);
    }
  });
});

test('simultaneous completed runs and retries retain the real personal best', async () => {
  await fixture(async ({ DB, submit }) => {
    for (const [mode, course, better, worse] of [
      ['runner', 'runner', 9000, 1000], ['endless', 'endless', 900, 100],
      ['time', 'glacier', 20000, 90000],
    ]) {
      const responses = await Promise.all([
        submit({ mode, course, value: better }), submit({ mode, course, value: worse }),
      ]);
      for (const response of responses) assert.equal(response.status, 200);
      assert.equal(DB.prepare('SELECT value FROM scores WHERE user_id = ? AND mode = ? AND course = ?')
        .get(USER, mode, course).value, better);
      DB.prepare('UPDATE scores SET created_at = ? WHERE user_id = ? AND mode = ? AND course = ?')
        .run('2001-01-01 00:00:00', USER, mode, course);
      const replay = await (await submit({ mode, course, value: better })).json();
      assert.equal(replay.improved, false);
      assert.equal(replay.best, better);
      assert.equal(DB.prepare('SELECT created_at FROM scores WHERE user_id = ? AND mode = ? AND course = ?')
        .get(USER, mode, course).created_at, '2001-01-01 00:00:00');
    }
  });
});

test('score values are bounded integer JSON numbers, never coerced strings or flags', async () => {
  await fixture(async ({ DB, submit }) => {
    for (const value of [true, false, null, '12345', [], {}, 1.5, -1, 0, 1_000_000_001]) {
      const response = await submit({ mode: 'runner', course: 'runner', value });
      assert.equal(response.status, 400, JSON.stringify(value));
      assert.deepEqual(await response.json(), { error: 'bad value' });
    }
    assert.equal(DB.prepare('SELECT COUNT(*) AS n FROM scores').get().n, 0);
  });
});

test('in-flight lower score cannot overwrite a better score committed immediately before its write', async () => {
  await fixture(async ({ DB, env, submit }) => {
    assert.equal((await submit({ mode: 'runner', course: 'runner', value: 1000 })).status, 200);
    env.DB.beforeScoreWrite = () => DB.prepare("UPDATE scores SET value = 9000 WHERE user_id = ? AND mode = 'runner'").run(USER);
    const response = await submit({ mode: 'runner', course: 'runner', value: 2000 });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.best, 9000);
    assert.equal(body.improved, false);
    assert.equal(DB.prepare("SELECT value FROM scores WHERE user_id = ? AND mode = 'runner'").get(USER).value, 9000);
  });
});

test('tied ranks identify only authenticated owner and never expose account IDs', async () => {
  await fixture(async ({ DB, env, submit }) => {
    assert.equal((await submit({ mode: 'runner', course: 'runner', value: 12345 })).status, 200);
    const { created_at } = DB.prepare('SELECT created_at FROM scores WHERE user_id = ? AND mode = ? AND course = ?')
      .get(USER, 'runner', 'runner');
    DB.prepare('INSERT INTO scores (user_id, name, mode, course, value, created_at) VALUES (?, ?, ?, ?, ?, ?)')
      .run('synthetic-other-player', 'Penguin', 'runner', 'runner', 12345, created_at);
    const get = (limit, signedIn) => worker.fetch(new Request(`https://worker.example/api/leaderboard?mode=runner&course=runner&limit=${limit}`, {
      headers: signedIn ? { Authorization: `Bearer ${token}` } : {},
    }), env);
    const body = await (await get(20, true)).json();
    assert.deepEqual(body.entries.map((row) => row.rank), [1, 1]);
    assert.equal(body.entries.filter((row) => row.is_me).length, 1);
    assert.deepEqual(body.me, { rank: 1, value: 12345 });
    for (const row of body.entries) assert.deepEqual(Object.keys(row).sort(), ['is_me', 'name', 'rank', 'value']);
    const publicBody = await (await get(20, false)).json();
    assert.equal(publicBody.entries.every((row) => row.is_me === false), true);
    assert.equal(publicBody.me, null);
    // Stable tie order can leave the owner outside a limited top list, even
    // while the owner's true tied rank remains #1.
    const limited = await (await get(1, true)).json();
    assert.equal(limited.entries[0].is_me, false);
    assert.deepEqual(limited.me, { rank: 1, value: 12345 });
  });
});

test('authenticated profile read restores only own explicit public handle', async () => {
  await fixture(async ({ DB, env }) => {
    DB.prepare('INSERT INTO profiles (user_id, name) VALUES (?, ?)').run('other-account', 'Other Name');
    const get = (auth = true) => worker.fetch(new Request('https://worker.example/api/profile?user_id=other-account', {
      headers: auth ? { Authorization: `Bearer ${token}` } : {},
    }), env);
    assert.equal((await get(false)).status, 401);
    assert.deepEqual(await (await get()).json(), { name: '' });
    DB.prepare('INSERT INTO profiles (user_id, name) VALUES (?, ?)').run(USER, 'Chosen Penguin');
    assert.deepEqual(await (await get()).json(), { name: 'Chosen Penguin' });
  });
});
