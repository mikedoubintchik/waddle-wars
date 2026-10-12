// Exact scoped native release in workerd + fresh local D1. No live accounts or network.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { Miniflare } = require('../../leaderboard/node_modules/miniflare');
const [candidateArg, receiptArg] = process.argv.slice(2);
if (!candidateArg || !receiptArg) throw new Error('Usage: node verify_native_auth_runtime.mjs CANDIDATE RECEIPT');
const candidate = resolve(candidateArg), root = resolve(new URL('../..',import.meta.url).pathname);
const issuer='https://clerk.waddlewars.io', web='https://stunning-hen-13.clerk.accounts.dev';
const origin='https://waddlewars.io', rawOwner='user_syntheticNativeRuntime', owner='clerk_live:'+rawOwner;
const auth='/api/commerce/native-auth/', verifier='a'.repeat(43), checks=[], outbound=[];
const key=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk={...await crypto.subtle.exportKey('jwk',key.publicKey),kid:'synthetic-runtime'};
const enc=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
async function token(iss) {
 const unsigned=enc({alg:'RS256',kid:jwk.kid})+'.'+enc({iss,sub:rawOwner,sid:'sess_syntheticRuntime',iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+600});
 return unsigned+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key.privateKey,new TextEncoder().encode(unsigned))).toString('base64url');
}
const liveToken=await token(issuer), webToken=await token(web);
let failIdentityDelete=true;
let tokenHold=null;
const mf=new Miniflare({modules:true,scriptPath:candidate+'/worker.mjs',compatibilityDate:'2026-08-01',
 d1Databases:{DB:'isolated-native-auth-release-check',MIGRATION_CHECK:'isolated-native-auth-upgrade-check'},
 ratelimits:{COMMERCE_AUTH_LIMITER:{namespace_id:'2041',simple:{limit:1000,period:60}},ACCOUNT_DELETION_LIMITER:{namespace_id:'2042',simple:{limit:1000,period:60}}},
 bindings:{CLERK_ISSUER:web,NATIVE_CLERK_ISSUER:issuer,NATIVE_ACCOUNTS_ENABLED:'true',NATIVE_CLERK_SECRET_KEY:'sk_live_syntheticFixtureOnly'},
 outboundService:async request=>{
  const url=request.url;outbound.push(url);
  if([issuer,web].some(i=>url===i+'/.well-known/jwks.json')) return Response.json({keys:[jwk]});
  assert.equal(request.headers.get('Authorization'),'Bearer sk_live_syntheticFixtureOnly');
  if(url==='https://api.clerk.com/v1/sessions/sess_syntheticRuntime')return Response.json({id:'sess_syntheticRuntime',user_id:rawOwner,status:'active'});
  if(url==='https://api.clerk.com/v1/sessions/sess_syntheticRuntime/tokens'){if(tokenHold){tokenHold.reached();await tokenHold.promise}return Response.json({jwt:liveToken});}
  assert.equal(url,'https://api.clerk.com/v1/users/'+rawOwner,'only expected synthetic Clerk endpoint permitted');
  if(request.method==='DELETE' && failIdentityDelete)return Response.json({error:'synthetic_temporary_unavailability'},{status:503});
  return Response.json(request.method==='DELETE'?{deleted:true}:{id:rawOwner});
 }});
async function api(path,{body,method=body?'POST':'GET',bearer,headers={},host=origin}={}){
 return mf.dispatchFetch(host+path,{method,headers:{...headers,...(body?{'Content-Type':'application/json'}:{}),...(bearer?{Authorization:'Bearer '+bearer}:{})},...(body?{body:JSON.stringify(body)}:{})});
}
const challenge=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))).toString('base64url');
async function flow(){const r=await api(auth+'start',{body:{challenge,presentation:'ios'}});assert.equal(r.status,200);return r.json();}
async function json(response,status=200){assert.equal(response.status,status);return response.json();}
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
try{
 const DB=await mf.getD1Database('DB');
 for(const path of [candidate+'/production-base-schema.sql',candidate+'/native-accounts-schema.sql',candidate+'/native-accounts-schema.sql'])
  await DB.exec(readFileSync(path,'utf8').replace(/--[^\n]*/g,'').replace(/\s+/g,' '));
 checks.push('fresh D1 base + additive native migration twice');
 if(existsSync(candidate+'/native-auth-v2-upgrade.sql')) {
  const upgradeDB=await mf.getD1Database('MIGRATION_CHECK');
  for(const path of [candidate+'/production-base-schema.sql',candidate+'/previous-native-accounts-schema.sql'])
   await upgradeDB.exec(readFileSync(path,'utf8').replace(/--[^\n]*/g,'').replace(/\s+/g,' '));
  await upgradeDB.prepare("INSERT INTO commerce_native_auth_requests(request_id,challenge,expires_at,created_at,presentation) VALUES('existing-v1','preserved',9999999999,1,'ios')").run();
  await upgradeDB.exec(readFileSync(candidate+'/native-auth-v2-upgrade.sql','utf8').replace(/--[^\n]*/g,'').replace(/\s+/g,' '));
  const old=await upgradeDB.prepare("SELECT challenge,flow_version,callback_code_hash FROM commerce_native_auth_requests WHERE request_id='existing-v1'").first();
  assert.deepEqual(old,{challenge:'preserved',flow_version:1,callback_code_hash:null});
  checks.push('existing production v7 schema upgrades additively to v2; old in-flight request preserved as v1');
 }

 const tables=await DB.prepare("SELECT name FROM sqlite_master WHERE type='table'").all();assert.ok(!tables.results.some(t=>t.name==='commerce_purchases'));
 const f=await flow(), proof={request_id:f.request_id,verifier};
 assert.equal(f.authorize_url,origin+auth+'authorize-ios?request_id='+f.request_id);
 const page=await api(auth+'authorize-ios?request_id='+f.request_id);assert.equal(page.status,200);assert.ok((await page.text()).includes('pk_live_Y2xlcmsud2FkZGxld2Fycy5pbyQ'));
 assert.equal((await api(auth+'start',{body:{challenge,presentation:'ios'},host:'https://worker.invalid'})).status,503);
 assert.equal((await api(auth+'complete',{body:{request_id:f.request_id},bearer:webToken,headers:{Origin:origin}})).status,401);
 assert.equal((await api(auth+'token',{body:proof})).status,409);
 await json(await api(auth+'complete',{body:{request_id:f.request_id},bearer:liveToken,headers:{Origin:origin}}));
 assert.equal((await json(await api(auth+'token',{body:proof}))).user_id,rawOwner);
 assert.equal((await json(await api(auth+'refresh',{body:proof}))).token,liveToken);
 checks.push('production-only PKCE page approve exchange refresh and origin guard');
 if(existsSync(candidate+'/native-auth-v2-upgrade.sql')) {
  async function v2flow(){return json(await api(auth+'start',{body:{challenge,presentation:'ios',flow_version:2}}));}
  async function v2approve(id){return json(await api(auth+'complete',{body:{request_id:id,flow_version:2},bearer:liveToken,headers:{Origin:origin}}));}
  const f2=await v2flow(),base={request_id:f2.request_id,verifier};assert.equal(f2.flow_version,2);
  assert.equal(f2.authorize_url,origin+auth+'authorize-ios-v2?request_id='+f2.request_id);
  for(const route of ['authorize','authorize-ios'])assert.equal((await api(auth+route+'?request_id='+f2.request_id)).status,400);
  const html=await(await api(auth+'authorize-ios-v2?request_id='+f2.request_id)).text();
  assert.ok(!html.includes('<button'));assert.ok(!html.includes('Connection code:'));assert.ok(html.includes('callback_code'));
  assert.equal((await api(auth+'complete',{body:{request_id:f2.request_id},bearer:liveToken,headers:{Origin:origin}})).status,400);
  assert.equal((await api(auth+'token',{body:base})).status,401);
  const approved=await v2approve(f2.request_id);assert.match(approved.callback_code,/^[A-Za-z0-9_-]{43}$/);
  assert.equal((await api(auth+'token',{body:base})).status,401);
  assert.equal((await api(auth+'token',{body:{...base,callback_code:'x'.repeat(43)}})).status,401);
  const proof2={...base,callback_code:approved.callback_code};
  const concurrent=await Promise.all([api(auth+'token',{body:proof2}),api(auth+'token',{body:proof2})]);
  assert.deepEqual(concurrent.map(r=>r.status).sort(),[200,401]);
  assert.equal((await api(auth+'token',{body:proof2})).status,401);
  assert.equal((await json(await api(auth+'refresh',{body:base}))).user_id,rawOwner);
  const row=await DB.prepare('SELECT callback_code_hash,callback_code_consumed_at FROM commerce_native_auth_requests WHERE request_id=?1').bind(f2.request_id).first();
  assert.notEqual(row.callback_code_hash,approved.callback_code);assert.ok(row.callback_code_consumed_at>0);
  checks.push('v2 production Clerk HTML has no extra step; downgrade and shared-link polling denied; callback+PKCE concurrent exchange has one winner, replay denied, refresh works');
  const fc=await v2flow(),ac=await v2approve(fc.request_id);let reached,release;
  const ready=new Promise(r=>{reached=r}),hold=new Promise(r=>{release=r});tokenHold={reached,promise:hold};
  const pending=api(auth+'token',{body:{request_id:fc.request_id,verifier,callback_code:ac.callback_code}});await ready;
  await json(await api(auth+'cancel',{body:{request_id:fc.request_id,verifier}}));release();
  const cancelled=await pending;tokenHold=null;assert.equal(cancelled.status,401);assert.ok(!Object.hasOwn(await cancelled.json(),'token'));
  assert.equal((await DB.prepare('SELECT count(*) n FROM commerce_native_auth_sessions WHERE request_id=?1').bind(fc.request_id).first()).n,0);
  checks.push('real workerd delayed callback exchange loses cancellation race and creates no session');
 }

 const stored=await DB.prepare('SELECT user_id FROM commerce_native_auth_sessions').first();assert.equal(stored.user_id,owner);
 for(const [bearer,value] of [[webToken,700],[liveToken,1100]]){
  assert.equal((await json(await api('/api/scores',{bearer,body:{mode:'runner',course:'runner',value}}))).best,value);
 }
 const scoreRows=await DB.prepare('SELECT user_id,value FROM scores ORDER BY value').all();assert.deepEqual(scoreRows.results,[{user_id:rawOwner,value:700},{user_id:owner,value:1100}]);
 await json(await api('/api/profile',{bearer:liveToken,body:{name:'Ice Explorer'}}));
 assert.equal((await json(await api('/api/profile',{bearer:liveToken}))).name,'Ice Explorer');
 checks.push('same-sub development/production scores isolated, native custom public name');
 await json(await api('/api/save',{method:'PUT',bearer:webToken,body:{fish:7}}));
 const absent=await json(await api('/api/save?sync=2',{bearer:liveToken}));assert.equal(absent.revision,'absent');assert.equal(absent.sync_protocol,2);
 const saved=await json(await api('/api/save',{method:'PUT',bearer:liveToken,body:{sync_protocol:2,base_revision:'absent',progress:{fish:11,commerce:{private:true},account_deletion_receipts:{private:true}}}}));
 const read=await json(await api('/api/save?sync=2',{bearer:liveToken}));assert.equal(read.revision,saved.revision);assert.equal(JSON.parse(read.data).fish,11);assert.ok(!read.data.includes('private'));
 assert.equal((await api('/api/save',{method:'PUT',bearer:liveToken,body:{sync_protocol:2,base_revision:'absent',progress:{fish:99}}})).status,409);
 assert.equal((await api('/api/save',{method:'PUT',bearer:liveToken,body:{fish:99}})).status,409);
 const concurrent=await Promise.all([12,13].map(fish=>api('/api/save',{method:'PUT',bearer:liveToken,body:{sync_protocol:2,base_revision:saved.revision,progress:{fish}}})));
 assert.deepEqual(concurrent.map(r=>r.status).sort(),[200,409]);
 assert.equal(JSON.parse((await json(await api('/api/save',{bearer:webToken}))).data).fish,7);
 checks.push('native cloud CAS roundtrip, sensitive fields stripped, concurrent writes and legacy downgrade rejected; web save preserved');
 await json(await api(auth+'cancel',{body:proof}));assert.equal((await api(auth+'refresh',{body:proof})).status,401);
 checks.push('cancellation invalidates refresh capability');
 const recovery='b'.repeat(64);
 const deletion=await json(await api('/api/account/delete',{bearer:liveToken,body:{confirm:'DELETE_ACCOUNT',recovery_receipt:recovery}}),202);
 assert.equal(deletion.account_data_erased,true);assert.equal(deletion.identity_deleted,false);
 assert.equal((await api('/api/scores',{bearer:liveToken,body:{mode:'runner',course:'runner',value:9000}})).status,401);
 assert.equal((await api('/api/save?sync=2',{bearer:liveToken})).status,401);
 assert.equal((await json(await api('/api/save',{bearer:webToken}))).exists,true);
 failIdentityDelete=false;
 const worker=await mf.getWorker();
 await worker.scheduled({cron:'17 * * * *'});
 const status=await json(await api('/api/account/deletion/receipt',{headers:{'X-Waddle-Deletion-Receipt':recovery}}));assert.equal(status.account_data_erased,true);assert.equal(status.identity_deleted,true);
 const remaining=await DB.prepare('SELECT user_id FROM scores').all();assert.deepEqual(remaining.results,[{user_id:rawOwner}]);
 checks.push('real D1 transactional deletion, transient provider outage and scheduled identity retry, receipt recovery, retired writes blocked, other issuer untouched');
 const receipt={state:'passed',runtime:'Miniflare/workerd + fresh isolated D1',passed:checks.length,failed:0,skipped:0,production_writes:0,
  worker_sha256:sha(candidate+'/worker.mjs'),schema_sha256:sha(candidate+'/native-accounts-schema.sql'),module_hashes:JSON.parse(readFileSync(candidate+'/receipt.json','utf8')).module_hashes,checks,outbound_requests:outbound};
 writeFileSync(receiptArg,JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify({passed:checks.length,failed:0,skipped:0,receipt:receiptArg}));
}finally{await mf.dispose();}
