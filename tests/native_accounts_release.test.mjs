import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { acceptedClerkIssuer, nativeAccountEnvironment } from '../leaderboard/src/native_accounts_policy.mjs';

const candidate = resolve(process.env.WADDLE_NATIVE_AUTH_CANDIDATE || 'qa_shots/tests/phone-fixes-20261009/native-auth-candidate-v7');
const worker = (await import(pathToFileURL(`${candidate}/worker.mjs`))).default;
const schema = readFileSync(`${candidate}/native-accounts-schema.sql`, 'utf8');
const ORIGIN = 'https://waddlewars.io';
const ISSUER = 'https://clerk.waddlewars.io';
const WEB = 'https://stunning-hen-13.clerk.accounts.dev';
const verifier = 'a'.repeat(43);
const encoder = new TextEncoder();
const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

class D1 {
  constructor() {
    this.db = new DatabaseSync(':memory:');
    this.db.exec(readFileSync(candidate+'/production-base-schema.sql', 'utf8'));
    this.db.exec(schema);
  }
  prepare(sql) {
    const statement = this.db.prepare(sql); statement.setAllowUnknownNamedParameters(true);
    const make = (values = []) => {
      const args = Object.fromEntries(values.map((value, i) => [String(i + 1), value]));
      return { bind: (...values) => make(values), first: async () => statement.get(args) || null,
        all: async () => ({ results: statement.all(args) }), run: async () => statement.run(args) };
    }; return make();
  }
  async batch(statements) {
    this.db.exec('BEGIN'); try { for (const statement of statements) await statement.run(); this.db.exec('COMMIT'); }
    catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
}
const limiter = { limit: async () => ({ success: true }) };
const env = () => ({ DB: new D1(), CLERK_ISSUER: WEB, NATIVE_CLERK_ISSUER: ISSUER,
  NATIVE_ACCOUNTS_ENABLED: 'true', NATIVE_CLERK_SECRET_KEY: 'sk_live_syntheticFixtureOnly',
  COMMERCE_AUTH_LIMITER: limiter, ACCOUNT_DELETION_LIMITER: limiter });
const req = (path, body, bearer, origin) => new Request(ORIGIN + path, {
  method: body ? 'POST' : 'GET', headers: { ...(body ? { 'Content-Type': 'application/json' } : {}),
    ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}), ...(origin ? { Origin: origin } : {}) },
  ...(body ? { body: JSON.stringify(body) } : {}) });
const route = (suffix) => '/api/commerce/native-auth/' + suffix;
const key = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
  publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const jwk = { ...await crypto.subtle.exportKey('jwk', key.publicKey), kid: 'synthetic-native-key' };
async function token(issuer = ISSUER, sub = 'user_nativeFixture') {
  const unsigned = `${encode({alg:'RS256',kid:jwk.kid})}.${encode({iss:issuer,sub,sid:'sess_nativeFixture',
    iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+60})}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key.privateKey, encoder.encode(unsigned));
  return `${unsigned}.${Buffer.from(signature).toString('base64url')}`;
}
async function start(environment) {
  const challenge = Buffer.from(await crypto.subtle.digest('SHA-256',encoder.encode(verifier))).toString('base64url');
  const result = await worker.fetch(req(route('start'),{challenge,presentation:'ios'}),environment);
  assert.equal(result.status,200); return result.json();
}
async function providerRun(run) {
  const original = globalThis.fetch; const issued = await token(); const seen = [];
  globalThis.fetch = async (url, init) => {
    seen.push(String(url));
    if ([ISSUER,WEB].some((issuer) => String(url) === issuer+'/.well-known/jwks.json')) return Response.json({keys:[jwk]});
    assert.equal(init.headers.Authorization,'Bearer sk_live_syntheticFixtureOnly');
    if (String(url).endsWith('/tokens')) return Response.json({jwt:issued});
    if (String(url).includes('/v1/users/') && init.method === 'DELETE') return Response.json({deleted:true});
    if (String(url).includes('/v1/users/')) return Response.json({id:'user_nativeFixture'});
    assert.equal(String(url),'https://api.clerk.com/v1/sessions/sess_nativeFixture');
    return Response.json({id:'sess_nativeFixture',user_id:'user_nativeFixture',status:'active'});
  };
  try { return await run(issued, seen); } finally {globalThis.fetch=original;}
}

test('native enablement never silently switches development web or accepts foreign JWKS',()=>{
  const e=env();
  assert.equal(acceptedClerkIssuer(e,WEB),WEB);
  assert.equal(acceptedClerkIssuer(e,ISSUER),ISSUER);
  assert.equal(acceptedClerkIssuer(e,'https://attacker.invalid'),null);
  assert.equal(acceptedClerkIssuer({...e,NATIVE_ACCOUNTS_ENABLED:'false'},ISSUER),null);
  assert.equal(nativeAccountEnvironment({...e,NATIVE_CLERK_SECRET_KEY:'sk_test_fixture'}),null);
  assert.equal(nativeAccountEnvironment({...e,NATIVE_CLERK_ISSUER:WEB}),null);
  const native = nativeAccountEnvironment(e);
  assert.equal(native.CLERK_ISSUER,ISSUER); assert.equal(acceptedClerkIssuer(native,WEB),null);
});

test('scoped schema is additive and idempotent without enabling commerce',()=>{
  const e=env(); e.DB.db.exec(schema);
  const tables=e.DB.db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(x=>x.name);
  assert.ok(tables.includes('commerce_native_auth_requests'));
  assert.ok(tables.includes('account_retirements'));
  assert.ok(!tables.includes('commerce_purchases'));
  assert.ok(!tables.includes('commerce_checkouts'));
});

test('native start requires live secret, limiter and primary authorization origin',async()=>{
  for (const extra of [{NATIVE_CLERK_SECRET_KEY:''},{NATIVE_ACCOUNTS_ENABLED:'false'},{COMMERCE_AUTH_LIMITER:null}]) {
    assert.equal((await worker.fetch(req(route('start'),{challenge:'a'.repeat(43)}),{...env(),...extra})).status,503);
  }
  assert.equal((await worker.fetch(new Request('https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev'+route('start'),{
    method:'POST',body:JSON.stringify({challenge:'a'.repeat(43)})}),env())).status,503);
});

test('native authorize page uses only production Clerk and returns social login to connection page',async()=>{
  const e=env(), flow=await start(e);
  assert.equal(flow.authorize_url,ORIGIN+route('authorize-ios')+'?request_id='+flow.request_id);
  const page=await worker.fetch(new Request(flow.authorize_url),e); const html=await page.text();
  assert.equal(page.status,200); assert.match(html,/pk_live_Y2xlcmsud2FkZGxld2Fycy5pbyQ/);
  assert.ok(html.includes(ISSUER+'/npm/@clerk/clerk-js@5/dist/clerk.browser.js'));
  assert.ok(html.includes("routing:'virtual',forceRedirectUrl:window.location.href"));
  assert.ok(!html.includes(e.NATIVE_CLERK_SECRET_KEY)); assert.ok(!html.includes(verifier));
  assert.ok(!html.includes(WEB));
});

test('development token cannot approve native production session',async()=>providerRun(async()=>{
  const e=env(),flow=await start(e);
  const response=await worker.fetch(req(route('complete'),{request_id:flow.request_id},await token(WEB),ORIGIN),e);
  assert.equal(response.status,401);
  assert.equal(e.DB.db.prepare('SELECT state FROM commerce_native_auth_requests').get().state,'pending');
}));

test('production native start approve exchange refresh and leaderboard post work together',async()=>providerRun(async(issued)=>{
  const e=env(),flow=await start(e), body={request_id:flow.request_id,verifier};
  assert.equal((await worker.fetch(req(route('token'),body),e)).status,409);
  assert.equal((await worker.fetch(req(route('complete'),{request_id:flow.request_id},issued,ORIGIN),e)).status,200);
  const result=await worker.fetch(req(route('token'),body),e); assert.equal(result.status,200);
  const credential=await result.json(); assert.equal(credential.token,issued); assert.equal(credential.user_id,'user_nativeFixture');
  assert.equal((await worker.fetch(req(route('refresh'),body),e)).status,200);
  const posted=await worker.fetch(req('/api/scores',{mode:'runner',course:'runner',value:1000},credential.token),e);
  assert.equal(posted.status,200); assert.equal((await posted.json()).best,1000);
  const board=await worker.fetch(req('/api/leaderboard?mode=runner&course=runner',null,credential.token),e);
  const data=await board.json(); assert.equal(data.me.rank,1); assert.equal(data.entries[0].name,'Penguin');
  const web=await worker.fetch(req('/api/scores',{mode:'runner',course:'runner',value:900},await token(WEB,'user_webFixture')),e);
  assert.equal(web.status,200); assert.equal(e.DB.db.prepare('SELECT COUNT(*) n FROM scores').get().n,2);
  assert.equal((await worker.fetch(req('/api/save',null,credential.token),e)).status,200);
}));

test('cancel invalidates native verifier and sessions',async()=>providerRun(async(issued)=>{
  const e=env(),flow=await start(e), body={request_id:flow.request_id,verifier};
  await worker.fetch(req(route('complete'),{request_id:flow.request_id},issued,ORIGIN),e);
  await worker.fetch(req(route('token'),body),e);
  assert.equal((await worker.fetch(req(route('cancel'),body),e)).status,200);
  assert.equal((await worker.fetch(req(route('refresh'),body),e)).status,401);
  assert.equal((await worker.fetch(req(route('token'),body),e)).status,401);
}));

test('optional native account keeps explicit deletion and blocks retired score writes',async()=>providerRun(async(issued)=>{
  const e=env(),flow=await start(e),body={request_id:flow.request_id,verifier};
  await worker.fetch(req(route('complete'),{request_id:flow.request_id},issued,ORIGIN),e);
  await worker.fetch(req(route('token'),body),e);
  await worker.fetch(req('/api/scores',{mode:'runner',course:'runner',value:1000},issued),e);
  assert.equal((await worker.fetch(req('/api/account/delete',{confirm:'no'},issued),e)).status,400);
  const response=await worker.fetch(req('/api/account/delete',{confirm:'DELETE_ACCOUNT',recovery_receipt:'b'.repeat(64)},issued),e);
  assert.equal(response.status,202); assert.equal((await response.json()).account_data_erased,true);
  assert.equal(e.DB.db.prepare('SELECT COUNT(*) n FROM scores').get().n,0);
  assert.equal((await worker.fetch(req('/api/scores',{mode:'runner',course:'runner',value:9999},issued),e)).status,401);
  assert.equal((await worker.fetch(req(route('refresh'),body),e)).status,401);
}));

test('same subject across Clerk instances cannot share scores, cloud saves or deletion',async()=>providerRun(async(live)=>{
  const e=env(),web=await token(WEB,'user_nativeFixture');
  for (const [credential,value] of [[web,700],[live,1100]]) {
    assert.equal((await worker.fetch(req('/api/scores',{mode:'runner',course:'runner',value},credential),e)).status,200);
    const save=new Request(ORIGIN+'/api/save',{method:'PUT',headers:{Authorization:`Bearer ${credential}`},body:JSON.stringify({fish:value})});
    assert.equal((await worker.fetch(save,e)).status,200);
  }
  const rows=e.DB.db.prepare('SELECT user_id,value FROM scores ORDER BY value').all();
  assert.deepEqual(rows.map(x=>({...x})),[{user_id:'user_nativeFixture',value:700},{user_id:'clerk_live:user_nativeFixture',value:1100}]);
  for (const [credential,value] of [[web,700],[live,1100]]) {
    const save=await worker.fetch(req('/api/save',null,credential),e);
    assert.equal(JSON.parse((await save.json()).data).fish,value);
  }
  assert.equal((await worker.fetch(req('/api/account/delete',{confirm:'DELETE_ACCOUNT',recovery_receipt:'c'.repeat(64)},live),e)).status,202);
  assert.equal(e.DB.db.prepare('SELECT value FROM scores WHERE user_id = ?').get('user_nativeFixture').value,700);
  assert.equal((await worker.fetch(req('/api/save',null,web),e)).status,200);
  assert.equal((await worker.fetch(req('/api/save',null,live),e)).status,401);
}));
