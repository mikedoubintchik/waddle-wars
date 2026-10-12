import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { RuntimeSwitcher, bounded } from './web_lifecycle.mjs';
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => {resolve=a; reject=b;}); return {promise,resolve,reject}; };
const tick = () => new Promise(r => setImmediate(r));

test('reload waits for exit and removal, coalesces changes during teardown', async () => {
  const exit = deferred(), events=[];
  const s = new RuntimeSwitcher({ report(){}, settle:async()=>{}, mount(b) {
    events.push(`mount:${b.id}`);
    return { id:b.id, ready:Promise.resolve(), stop:()=>exit.promise, remove:()=>events.push(`remove:${b.id}`) };
  }});
  await s.request({id:'a'});
  const work = s.request({id:'b'}); await tick();
  await s.request({id:'c'});
  assert.deepEqual(events,['mount:a']);
  exit.resolve(); await work;
  assert.deepEqual(events,['mount:a','remove:a','mount:c']);
  assert.equal(s.active.id,'c');
  assert.equal(s.history.filter(e=>e.type==='exit_observed').length,1);
});

test('unconfirmed teardown blocks new runtime; explicit retry can finish', async()=>{
  let fail=true, mounts=0, removes=0;
  const s=new RuntimeSwitcher({report(){},settle:async()=>{},mount(b){mounts++;return{
    id:b.id,ready:Promise.resolve(),stop:async()=>{if(fail)throw Error('timeout');},remove:()=>removes++};}});
  await s.request({id:'a'}); await s.request({id:'b'}); await s.request({id:'c'});
  assert.equal(mounts,1);assert.equal(removes,0);assert.equal(s.blocked,true);
  fail=false;await s.retry();assert.equal(mounts,2);assert.equal(removes,1);assert.equal(s.active.id,'c');
});

test('replacement while first runtime starts waits for startup and then exit',async()=>{
  const started=deferred(),exit=deferred(),events=[];
  const s=new RuntimeSwitcher({report(){},settle:async()=>{},mount(b){events.push(`mount:${b.id}`);return{
    id:b.id,ready:b.id==='a'?started.promise:Promise.resolve(),stop:()=>{events.push('quit');return exit.promise;},remove:()=>events.push('removed')};}});
  const task=s.request({id:'a'});await s.request({id:'b'});assert.deepEqual(events,['mount:a']);
  started.resolve();await tick();assert.deepEqual(events,['mount:a','quit']);
  exit.resolve();await task;assert.deepEqual(events,['mount:a','quit','removed','mount:b']);
});

test('bounded teardown rejects without swallowing underlying promise',async()=>{
  await assert.rejects(bounded(new Promise(()=>{}),5,'exit timeout'),/exit timeout/);
});

test('actual injected bridge uses Dummy and resolves stop only on cleanup callback',async()=>{
  const startup=deferred();let config,quit=0;
  const context={window:{},GODOT_CONFIG:{args:[]},engine:{
    startGame(c){config=c;return startup.promise;},requestQuit(){quit++;}}};
  vm.runInNewContext(fs.readFileSync(new URL('./runtime_bridge.js',import.meta.url),'utf8'),context);
  const starting=context.engine.startGame({});const bridge=context.window.__wwDevRuntime;
  let stopped=false;const stop=bridge.stop().then(()=>{stopped=true;});
  assert.equal(quit,0);assert.deepEqual(Array.from(config.args),['--audio-driver','Dummy']);
  startup.resolve();await starting;await tick();assert.equal(quit,1);assert.equal(stopped,false);
  config.onExit(0);await stop;assert.equal(stopped,true);
});
