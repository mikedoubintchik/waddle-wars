import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../tools/qa/chrome_reference_bridge.js',import.meta.url),'utf8');
let checks=0;
function context(host='127.0.0.1',search='?qa_token=local-test') {
  const window={__wwQABuild:{source_fingerprint:'frozen'}};
  const c={window,URLSearchParams,Date,location:{hostname:host,search,href:`http://${host}/${search}`},
    document:{hidden:false,hasFocus:()=>true,getElementById:()=>({width:1080,height:1920,clientWidth:540,clientHeight:960})},
    innerWidth:540,innerHeight:960,devicePixelRatio:2,navigator:{maxTouchPoints:5}};
  vm.runInNewContext(source,c);return c;
}
function check(value,message){assert.ok(value,message);checks++;}
for(const host of ['example.org','127.0.0.1.example.org','localhost.example.org'])check(!context(host).window.__wwQA,'reject nonlocal host');
check(!context('localhost','').window.__wwQA,'query token required');
const c=context(),q=c.window.__wwQA;let reads=0,last=null;
q.bind_callbacks(()=>{reads++;q._reply={status:'ready',route:'settings_audio',audio:{master_bus_muted:true}};},command=>{last=JSON.parse(command);});
let row=q.read();
check(row.audio.master_bus_muted===true,'returns real engine scalar unmodified');
check(row.build.source_fingerprint==='frozen','observed build fingerprint included');
check(row.canvas_backing.join() === '1080,1920','backing dimensions measured');
check(row.canvas_css.join() === '540,960','CSS dimensions measured');
check(row.browser_focused&&row.browser_visible&&row.touch_points===5,'browser state measured');
q.route('settings_audio');check(last.op==='route'&&last.name==='settings_audio','named route marshaled');
q.release();check(last.op==='release','explicit release marshaled');
q.stop();check(last.op==='stop','own engine stop marshaled');
check(reads===3,'no timer sampling or read history');
check(!('history' in q),'no growing history');
console.log(`[chrome-reference-shell] ${checks}/${checks} passed`);
