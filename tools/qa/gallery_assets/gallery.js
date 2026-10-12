/* Exactly two reusable image elements. Sidebar is text only; no prefetching. */
const manifest = JSON.parse(document.getElementById('catalogue-data').textContent);
const $ = id => document.getElementById(id);
const pages = manifest.pages, rows = manifest.entries;
const ids = pages.map(page => page.id);
const params = new URLSearchParams(location.hash.slice(1));
let selected = ids.includes(params.get('page')) ? params.get('page') : ids[0];
let orientation = params.get('view') === 'mobile' ? 'mobile' : 'desktop';
// Only explicitly packaged local HTML studies may become frame destinations.
// Excludes remote URLs, absolute paths, traversal, escaped paths and query URLs.
const studies = new Map(), studyLinks = new Map();
for (const study of Array.isArray(manifest.studio_collections) ? manifest.studio_collections : []) {
  if (!study || !/^[a-z][a-z0-9_-]*$/.test(study.id || '') || studies.has(study.id)
      || typeof study.title !== 'string' || !study.title.trim() || typeof study.path !== 'string'
      || !/^(?:[A-Za-z0-9_-][A-Za-z0-9_.-]*\/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*\.html$/.test(study.path)) continue;
  studies.set(study.id, study);
}
let collection = studies.has(params.get('collection')) ? params.get('collection') : null;
const links = new Map();
let changedOnly = false, needle = "";
const changed = new Set(manifest.affected_routes || []);
$('summary').textContent = `${pages.length} pages · ${manifest.accepted_views} accepted views · ${manifest.pending_current_views} pending views`;
const studioNote=typeof manifest.studio_note==='string'?manifest.studio_note.trim():'';
$('studio-note').textContent=studioNote;$('studio-note').hidden=!studioNote;
const groupNames = {menu:'Menus',settings:'Settings',equipment:'Equipment',run:'Waddle Run'};
for (const group of ['menu','settings','equipment','run']) {
  const section = document.createElement('section'); section.className = 'nav-group';
  const heading = document.createElement('h2'); heading.textContent = groupNames[group]; section.appendChild(heading);
  for (const page of pages.filter(page => page.group === group)) {
    const link = document.createElement('a'); link.className = 'page-link';
    if (page.state_kind === 'category') link.classList.add('category');
    else if (page.item_id) link.classList.add('item');
    link.href = `#page=${page.id}&view=${orientation}`;
    const title = document.createElement('span'); title.textContent = page.title; link.appendChild(title);
    const state = document.createElement('small');
    const captured = rows.filter(row => row.id === page.id && row.actual);
    const references = rows.filter(row => row.id === page.id && row.reference);
    const versions = [...new Set(captured.map(row => row.source_iteration))].sort();
    const pending = rows.filter(row => row.id === page.id && row.current_capture_status === 'pending').length;
    state.textContent = pending ? `${pending}/2 refresh pending · previous evidence retained` : captured.length ? `${captured.length}/2 views · Iteration ${versions.join('/')}` : references.length ? `${references.length}/2 references · capture pending` : 'Reference / capture pending';
    link.appendChild(state);
    link.addEventListener('click', event => {event.preventDefault();collection=null;selected=page.id;render();});
    links.set(page.id,link); section.appendChild(link);
  }
  $('pages').appendChild(section);
}
if (studies.size) {
  $('studio-navigation').hidden=false;
  const section=document.createElement('section');section.className='nav-group';
  const heading=document.createElement('h2');heading.textContent='Character studies';section.appendChild(heading);
  for (const [id,study] of studies) {
    const link=document.createElement('a');link.className='page-link';
    const title=document.createElement('span');title.textContent=study.title;link.appendChild(title);
    if(typeof study.note==='string'){const note=document.createElement('small');note.textContent=study.note;link.appendChild(note);}
    link.addEventListener('click',event=>{event.preventDefault();collection=id;render();});
    studyLinks.set(id,link);section.appendChild(link);
  }
  $('studio-navigation').appendChild(section);
}
for (const prior of manifest.prior_collections) {
  const link=document.createElement('a');link.href=prior.url;link.target='_blank';link.rel='noopener';link.textContent=`Iteration ${prior.iteration} archive`;$('collections').appendChild(link);
}
for(const sheet of manifest.overviews||[]){const link=document.createElement('a');link.href=sheet.path;link.target='_blank';link.rel='noopener';link.textContent=`${sheet.title} · JPEG`;$(sheet.group==='all'?'overview-links':'group-links').appendChild(link);if(sheet.group!=='all')$('overview-groups').hidden=false;}
function image(id,path,title) {
  const node=$(id), anchor=$(id+'-open');
  // Removing the previous URL also prevents a stale screenshot on pending pages.
  node.removeAttribute('src'); node.alt=''; anchor.removeAttribute('href');
  anchor.hidden=!path;$(id+'-empty').hidden=Boolean(path);
  if(path){node.src=path;node.alt=title;anchor.href=path;}
}
function download(id,path){$(id).hidden=!path;if(path)$(id).href=path;else $(id).removeAttribute('href');}
function render(){
  for(const [id,link] of links){link.href=`#page=${id}&view=${orientation}`;if(!collection&&id===selected)link.setAttribute('aria-current','page');else link.removeAttribute('aria-current');}
  for(const [id,link] of studyLinks){link.href=`#collection=${id}&view=${orientation}`;if(id===collection)link.setAttribute('aria-current','page');else link.removeAttribute('aria-current');}
  for(const id of ['desktop','mobile'])$(id).setAttribute('aria-pressed',String(id===orientation));
  $('page-pane').hidden=Boolean(collection);$('collection-pane').hidden=!collection;
  if(collection){
    const study=studies.get(collection),frame=$('collection-frame');
    $('collection-title').textContent=study.title;$('collection-note').textContent=typeof study.note==='string'?study.note:'';
    frame.title=study.title;
    // Child navigation does not update the iframe's src attribute. Assign it
    // even when unchanged so returning to the collection restores its index.
    frame.setAttribute('src',study.path);
    history.replaceState(null,'',`#collection=${collection}&view=${orientation}`);
    return;
  }
  $('collection-frame').removeAttribute('src');
  const page=pages.find(page=>page.id===selected);
  const row=rows.find(row=>row.id===selected&&row.orientation===orientation);
  const p=row.capture_provenance||{};
  $('title').textContent=page.title;
  const referenceLabels={item_design:'REFERENCE · ITEM DESIGN',category_composition:'REFERENCE · DESIGN FAMILY (PENGUINS)',base_composition_new_behavior:'REFERENCE · BASE HUD COMPOSITION'};
  $('reference-caption').textContent=row.reference_label||referenceLabels[row.reference_kind]||'REFERENCE · PAGE DESIGN';
  const stale = row.current_capture_status === 'pending';
  $('current-caption').textContent=stale&&row.actual?`PREVIOUS CAPTURE · REFRESH PENDING · ${(p.captured_at||'').slice(0,10)}`:row.actual?`GAME · ITERATION ${row.source_iteration} · ${(p.captured_at||'').slice(0,10)}`:'CURRENT CAPTURE · PENDING';
  $('tags').replaceChildren();
  for(const text of row.actual?[`Captured ${(p.captured_at||'').replace('T',' ').replace('Z',' UTC')}`,`Build ${(p.build_sha256||'').slice(0,12)}`]:['No accepted current frame']){const tag=document.createElement('span');tag.className='tag';tag.textContent=text;$('tags').appendChild(tag);}
  $('note').textContent=[row.reference_state_note,p.note, stale?'Source changed since this evidence. Current view is pending; the displayed previous capture is not accepted for this iteration.':row.actual?`Latest accepted evidence from iteration ${row.source_iteration}; original capture date/build preserved.`:'No current screenshot is inferred from an item asset or another selection.'].filter(Boolean).join(' ');
  image('reference',row.reference,`${page.title} · reference · ${orientation}`);
  image('current',row.actual,`${page.title} · Chrome game · ${orientation}`);
  for(const [id,path] of [['raw',row.actual],['ref-raw',row.reference],['pair',row.pair],['phone-pair',row.phone],['state',row.sidecar]])download(id,path);
  $('evidence').textContent=row.actual?`Original ${row.dimensions.join(' × ')}. ${p.capture_scope||''} Source ${p.url||''}. Build SHA256 ${p.build_sha256||''}. Capture SHA256 ${row.capture_sha256}. Reviewed ${p.reviewed_at||''}. Input: ${row.input_mode||p.input_mode||p.capture_scope||'prior capture; see scope'}. No physical-device or performance acceptance.`:'Reference and current-capture coverage are tracked separately. No placeholder or different item is counted as a captured view.';
  history.replaceState(null,'',`#page=${selected}&view=${orientation}`);
}
for(const id of ['desktop','mobile'])$(id).addEventListener('click',()=>{orientation=id;render();});
function visibleIds(){return pages.filter(page=>(!changedOnly||changed.has(page.id))&&`${page.title} ${page.category_title||''} ${page.item_id||''}`.toLowerCase().includes(needle)).map(p=>p.id);}
function filterPages(){const visible=new Set(visibleIds());for(const [id,link]of links)link.hidden=!visible.has(id);$('scope-all').setAttribute('aria-pressed',String(!changedOnly));$('scope-changed').setAttribute('aria-pressed',String(changedOnly));$('pages-empty').hidden=!(changedOnly&&!visible.size);$('pages-empty').textContent=changed.size?'No changed game pages match this filter.':'No game page captures changed in this update.';}
function move(direction){const visible=visibleIds();if(!visible.length)return;collection=null;selected=visible[(Math.max(0,visible.indexOf(selected))+direction+visible.length)%visible.length];render();}
$('previous').addEventListener('click',()=>move(-1));$('next').addEventListener('click',()=>move(1));
$('stack').addEventListener('click',()=>{const active=document.body.classList.toggle('stacked');$('stack').setAttribute('aria-pressed',String(active));});
$('filter').addEventListener('input',event=>{needle=event.target.value.trim().toLowerCase();filterPages();});
for(const mode of ['all','changed'])$('scope-'+mode).addEventListener('click',()=>{changedOnly=mode==='changed';filterPages();const visible=visibleIds();if(visible.length&&!visible.includes(selected)){selected=visible[0];if(!collection)render();}});
window.addEventListener('hashchange',()=>{const value=new URLSearchParams(location.hash.slice(1));collection=studies.has(value.get('collection'))?value.get('collection'):null;if(ids.includes(value.get('page')))selected=value.get('page');if(value.has('view'))orientation=value.get('view')==='mobile'?'mobile':'desktop';render();});
filterPages();render();
