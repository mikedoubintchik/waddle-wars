import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here=path.dirname(fileURLToPath(import.meta.url));
let createdImages=0;
class Element{
  constructor(tag='div'){this.tagName=tag;this.children=[];this.attrs={};this.listeners={};this.hidden=false;this.textContent='';this.className='';this.classList={add:x=>{this.className+=' '+x},toggle:x=>{this.active=!this.active;return this.active}};if(tag==='img')createdImages++;}
  appendChild(x){this.children.push(x);return x}
  replaceChildren(){this.children=[]}
  setAttribute(k,v){this.attrs[k]=v;if(this.tagName==='iframe'&&k==='src'){this.contentLocation=v;this.navigations=(this.navigations||0)+1}}
  getAttribute(k){return this.attrs[k]??null}
  removeAttribute(k){delete this.attrs[k];if(k==='src')delete this.src;if(k==='href')delete this.href}
  addEventListener(k,f){this.listeners[k]=f}
  fire(k,value){this.listeners[k]?.({preventDefault(){},target:{value}})}
}
const ids=['catalogue-data','summary','studio-note','pages','pages-empty','collections','overview-links','overview-groups','group-links','title','tags','note','reference-caption','current-caption','reference','current','reference-open','current-open','reference-empty','current-empty','raw','ref-raw','pair','phone-pair','state','evidence','desktop','mobile','previous','next','stack','filter','scope-all','scope-changed','studio-navigation','page-pane','collection-pane','collection-title','collection-note','collection-frame'];
const pages=[{id:'main_menu',title:'Home',group:'menu'},{id:'equipment_hat_none',title:'Hats · None',group:'equipment',category_title:'Hats',item_id:'hat_none'},{id:'equipment_hat_beanie',title:'Hats · Cozy Beanie',group:'equipment',category_title:'Hats',item_id:'hat_beanie'}];
const entries=pages.flatMap(p=>['desktop','mobile'].map(o=>({id:p.id,title:p.title,orientation:o,actual:p.id==='main_menu'?`${o}.jpg`:null,reference:p.id==='equipment_hat_none'?null:`${p.id}-${o}.png`,reference_kind:p.id==='main_menu'?'full_page':'item_design',source_iteration:p.id==='main_menu'?7:null,current_capture_status:p.id==='main_menu'&&o==='mobile'?'pending':'accepted',dimensions:[160,90],capture_sha256:'a'.repeat(64),capture_provenance:p.id==='main_menu'?{captured_at:'2026-10-08T09:00:00Z',build_sha256:'b'.repeat(64)}:null})));
function boot(extra={},hash=''){
  const nodes=Object.fromEntries(ids.map(id=>[id,new Element(['reference','current'].includes(id)?'img':id==='collection-frame'?'iframe':'div')]));
  nodes['studio-navigation'].hidden=true;nodes['collection-pane'].hidden=true;
  nodes['catalogue-data'].textContent=JSON.stringify({pages,entries,affected_routes:['main_menu'],accepted_views:2,pending_current_views:4,prior_collections:[],overviews:[{path:'all.jpg',group:'all',title:'All pages'},{path:'six.jpg',group:'group-01',title:'Pages 1–6'}],...extra});
  const location={hash},handlers={};
  const context={document:{getElementById:id=>nodes[id],createElement:t=>new Element(t),body:new Element('body')},location,history:{replaceState(_a,_b,h){location.hash=h}},window:{addEventListener(k,f){handlers[k]=f}},URLSearchParams,Map,Set};
  vm.runInNewContext(fs.readFileSync(path.join(here,'gallery.js'),'utf8'),context);
  return {nodes,location,handlers};
}
const {nodes,location,handlers}=boot();
assert.equal(createdImages,2);assert.equal(nodes.current.src,'desktop.jpg');
assert.equal(nodes['overview-links'].children[0].href,'all.jpg');assert.equal(nodes['group-links'].children[0].href,'six.jpg');assert.equal(nodes['overview-groups'].hidden,false);assert.match(nodes['overview-links'].children[0].textContent,/JPEG/);
const flatten=node=>node.children.flatMap(child=>[child,...flatten(child)]);
const links=flatten(nodes.pages).filter(x=>x.tagName==='a');assert.equal(links.length,3);
links[1].fire('click');assert.equal(nodes.current.src,undefined);assert.equal(nodes.reference.src,undefined);assert.equal(nodes['current-open'].hidden,true);assert.equal(nodes['current-empty'].hidden,false);assert.equal(nodes.raw.hidden,true);
links[2].fire('click');assert.equal(nodes.current.src,undefined);assert.equal(nodes.reference.src,'equipment_hat_beanie-desktop.png');assert.equal(nodes['reference-caption'].textContent,'REFERENCE · ITEM DESIGN');
nodes.mobile.fire('click');assert.equal(nodes.reference.src,'equipment_hat_beanie-mobile.png');
links[0].fire('click');assert.equal(nodes.current.src,'mobile.jpg');assert.match(nodes['current-caption'].textContent,/PREVIOUS CAPTURE/);assert.match(nodes.note.textContent,/not accepted for this iteration/);
for(let i=0;i<100;i++){nodes.next.fire('click');nodes.desktop.fire('click');nodes.mobile.fire('click')}
assert.equal(createdImages,2);assert.equal(links.length,3);
nodes.filter.fire('input','Cozy');assert.equal(links[0].hidden,true);assert.equal(links[2].hidden,false);
location.hash='#page=main_menu&view=desktop';handlers.hashchange();assert.equal(nodes.current.src,'desktop.jpg');assert.equal(links[0].attrs['aria-current'],'page');
nodes.filter.fire('input','');nodes['scope-changed'].fire('click');assert.equal(links[0].hidden,false);assert.equal(links[1].hidden,true);assert.equal(links[2].hidden,true);nodes['scope-all'].fire('click');assert.equal(links[2].hidden,false);assert.equal(createdImages,2);
assert.equal(nodes['studio-navigation'].hidden,true);assert.equal(nodes['collection-frame'].getAttribute('src'),null);assert.equal(nodes['page-pane'].hidden,false);
assert.equal(nodes['studio-note'].hidden,true);assert.equal(nodes['studio-note'].textContent,'');
const studies=[{id:'penguin',title:'Penguin model & motion',path:'penguin/studio/index.html',note:'Candidate · review pending'}];
const datedNote='Game pages preserve October 9 evidence. Penguin candidate review is dated October 12.';
const study=boot({studio_collections:studies,studio_note:datedNote},'#page=main_menu&view=mobile');
assert.equal(study.nodes['studio-note'].hidden,false);assert.equal(study.nodes['studio-note'].textContent,datedNote);
const studyPages=flatten(study.nodes.pages).filter(x=>x.tagName==='a');
const studyLink=flatten(study.nodes['studio-navigation']).find(x=>x.tagName==='a');
assert.equal(study.nodes['studio-navigation'].hidden,false);assert.equal(study.nodes['collection-frame'].getAttribute('src'),null);
const summary=study.nodes.summary.textContent;
study.nodes.filter.fire('input','Cozy');study.nodes['scope-changed'].fire('click');studyLink.fire('click');
assert.equal(study.nodes['page-pane'].hidden,true);assert.equal(study.nodes['collection-pane'].hidden,false);
assert.equal(study.nodes['collection-frame'].getAttribute('src'),'penguin/studio/index.html');
assert.equal(study.nodes['collection-frame'].title,'Penguin model & motion');
assert.equal(study.location.hash,'#collection=penguin&view=mobile');assert.equal(studyLink.attrs['aria-current'],'page');
assert.equal(study.nodes.summary.textContent,summary);assert.equal(studyPages.length,3);assert.equal(study.nodes.pages.hidden,false);
assert.equal(study.nodes['scope-changed'].attrs['aria-pressed'],'true');
assert.equal(study.nodes['pages-empty'].hidden,false);assert.equal(study.nodes['pages-empty'].textContent,'No changed game pages match this filter.');
study.nodes['scope-all'].fire('click');assert.equal(study.nodes['page-pane'].hidden,true);assert.equal(studyPages[0].hidden,true);assert.equal(studyPages[2].hidden,false);
assert.equal(study.nodes['pages-empty'].hidden,true);
studyPages[2].fire('click');
assert.equal(study.nodes['collection-frame'].getAttribute('src'),null);assert.equal(study.nodes['collection-pane'].hidden,true);assert.equal(study.nodes['page-pane'].hidden,false);
assert.equal(study.nodes.reference.src,'equipment_hat_beanie-mobile.png');assert.equal(studyPages[0].hidden,true);assert.equal(studyPages[2].hidden,false);
assert.equal(studyLink.attrs['aria-current'],undefined);assert.equal(studyPages[2].attrs['aria-current'],'page');
studyLink.fire('click');study.location.hash='#collection=unknown&view=mobile';study.handlers.hashchange();
assert.equal(study.nodes['collection-frame'].getAttribute('src'),null);assert.equal(study.nodes['page-pane'].hidden,false);assert.equal(study.nodes.reference.src,'equipment_hat_beanie-mobile.png');
assert.equal(study.location.hash,'#page=equipment_hat_beanie&view=mobile');
const deep=boot({studio_collections:studies,studio_note:'   '},'#collection=penguin&view=mobile');
assert.equal(deep.nodes['studio-note'].hidden,true);
assert.equal(deep.nodes['collection-frame'].getAttribute('src'),'penguin/studio/index.html');assert.equal(deep.nodes['page-pane'].hidden,true);
// A link inside the child changes its document without changing iframe.src.
// Returning through the root collection hash must actively restore the index.
const deepFrame=deep.nodes['collection-frame'];
deepFrame.contentLocation='penguin/review/index.html';const navigations=deepFrame.navigations;
deep.location.hash='#collection=penguin';deep.handlers.hashchange();
assert.equal(deepFrame.getAttribute('src'),'penguin/studio/index.html');assert.equal(deepFrame.contentLocation,'penguin/studio/index.html');assert.equal(deepFrame.navigations,navigations+1);
deepFrame.contentLocation='penguin/another-review/index.html';
flatten(deep.nodes['studio-navigation']).find(x=>x.tagName==='a').fire('click');
assert.equal(deepFrame.contentLocation,'penguin/studio/index.html');assert.equal(deepFrame.navigations,navigations+2);
deep.location.hash='#page=main_menu&view=desktop';deep.handlers.hashchange();assert.equal(deep.nodes.current.src,'desktop.jpg');assert.equal(deep.nodes['collection-frame'].getAttribute('src'),null);
const unsafe=['https://example.com/studio.html','//example.com/studio.html','/outside.html','../escape.html','penguin/../escape.html','penguin/%2e%2e/escape.html','penguin/studio.html?redirect=other','javascript:alert(1)'];
const rejected=boot({studio_collections:unsafe.map((p,i)=>({id:`bad${i}`,title:'Unsafe',path:p}))},'#collection=bad0');
assert.equal(rejected.nodes['studio-navigation'].hidden,true);assert.equal(rejected.nodes['collection-frame'].getAttribute('src'),null);assert.equal(rejected.nodes['page-pane'].hidden,false);
const unchanged=boot({studio_collections:studies,affected_routes:[]});
unchanged.nodes['scope-changed'].fire('click');assert.equal(unchanged.nodes['pages-empty'].hidden,false);assert.equal(unchanged.nodes['pages-empty'].textContent,'No game page captures changed in this update.');
assert.equal(unchanged.nodes['studio-navigation'].hidden,false);assert.equal(flatten(unchanged.nodes.pages).filter(x=>x.tagName==='a'&&!x.hidden).length,0);
unchanged.nodes['scope-all'].fire('click');assert.equal(unchanged.nodes['pages-empty'].hidden,true);assert.equal(flatten(unchanged.nodes.pages).filter(x=>x.tagName==='a'&&!x.hidden).length,3);
assert.equal(createdImages,10);
const template=fs.readFileSync(path.join(here,'template.html'),'utf8');
assert.match(template,/<title>Waddle Wars Studio<\/title>/);assert.equal((template.match(/<img\b/g)||[]).length,2);
assert.ok(template.indexOf('id="studio-navigation"')<template.indexOf('id="pages"'));
assert.equal((template.match(/<iframe\b/g)||[]).length,1);assert.doesNotMatch(template,/<iframe[^>]+\bsrc=/);
console.log('Gallery interaction contracts passed: two reusable root images; optional local studies, unknown/unsafe hashes, filter/orientation preservation and return-to-page cleanup.');
