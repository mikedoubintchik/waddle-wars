#!/usr/bin/env python3
"""One end-of-turn capture pass, source-bound incremental galleries. No engine, browser or remote writes.

All source receipts are content inventories, including untracked files. Review drafts
never authorize images. Every accepted frame is checked again at build/delivery.
"""
from __future__ import annotations
import argparse
import copy
import datetime as dt
import fnmatch
import hashlib
import json
from pathlib import Path
import re
import shutil
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ORIENTATIONS = ('desktop', 'mobile')
SCOPE = {'directories': ['assets', 'data', 'scenes', 'scripts', 'shaders', 'addons', 'native', 'web'],
         'files': ['project.godot', 'export_presets.cfg'],
         'exclude_suffixes': ['.import', '.pyc'], 'exclude_parts': ['.godot', '__pycache__']}
EXPORT_SCOPE = {'directories': ['assets', 'data', 'scenes', 'scripts'], 'files': ['project.godot', 'export_presets.cfg'],
                'exclude_suffixes': ['.import', '.pyc'], 'exclude_parts': ['.godot', '__pycache__']}

def now(): return dt.datetime.now(dt.timezone.utc).isoformat()
def read(p): return json.loads(Path(p).read_text())
def digest(value): return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(ok, message):
    if not ok: raise ValueError(message)
def write(p, value, immutable=False):
    p = Path(p); p.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, indent=2, ensure_ascii=False)+'\n'
    if immutable and p.exists():
        require(p.read_text() == text, f'Immutable receipt already exists: {p}')
        return
    if immutable:
        with p.open('x') as stream: stream.write(text)
    else:
        temp = p.with_suffix(p.suffix+'.tmp'); temp.write_text(text); temp.replace(p)
def path_at(value, base):
    p = Path(value)
    return p if p.is_absolute() else Path(base)/p
def safe(value):
    if isinstance(value, dict): return {k: safe(v) for k,v in value.items() if k != 'qa_token'}
    if isinstance(value, list): return [safe(x) for x in value]
    if isinstance(value, str):
        return re.sub(r'https?://[^\s<>"\']+', lambda m: scrub_url(m.group()), value)
    return value
def scrub_url(value):
    p = urlsplit(value)
    return urlunsplit((p.scheme,p.netloc,p.path,urlencode([(k,v) for k,v in parse_qsl(p.query) if k != 'qa_token']),p.fragment))
def within_scope(path, scope):
    p = Path(path)
    return (path in scope['files'] or any(path.startswith(d+'/') for d in scope['directories'])) and not any(x in p.parts for x in scope['exclude_parts']) and not path.endswith(tuple(scope['exclude_suffixes']))
def snapshot(root, scope=SCOPE):
    root = Path(root); paths = set()
    for name in scope['directories']:
        folder = root/name
        if folder.exists(): paths.update(p for p in folder.rglob('*') if p.is_file())
    paths.update(root/name for name in scope['files'] if (root/name).is_file())
    files = {p.relative_to(root).as_posix():sha(p) for p in sorted(paths) if within_scope(p.relative_to(root).as_posix(),scope)}
    return {'schema':1,'captured_at':now(),'scope':scope,'files':files,'fingerprint':digest(files)}
def exported_source(manifest):
    files = dict(manifest['source_sha256']); files['export_presets.cfg'] = manifest['source_preset_sha256']
    require(digest(manifest['source_sha256']) == manifest['source_fingerprint'], 'Export source fingerprint mismatch')
    return {'scope':EXPORT_SCOPE,'files':files,'fingerprint':digest(files)}
def difference(before, after):
    return [{'path':p,'before':before.get(p),'after':after.get(p),
             'kind':'added' if p not in before else 'deleted' if p not in after else 'modified'}
            for p in sorted(before.keys() | after.keys()) if before.get(p) != after.get(p)]
def scoped_files(source, scope): return {p:h for p,h in source.items() if within_scope(p,scope)}
def impacts(changes, pages, dependencies):
    ids = {p['id'] for p in pages}; reasons = {}; unknown = []
    for change in changes:
        matches = [r for r in dependencies['rules'] if any(fnmatch.fnmatchcase(change['path'], pattern) for pattern in r['paths'])]
        if not matches:
            unknown.append(change['path']); matches = [{'routes':['*'],'reason':'Unmapped runtime change; conservative full-catalogue refresh'}]
        for rule in matches:
            chosen = set()
            for selector in rule['routes']:
                if selector == '*': chosen |= ids
                elif selector.startswith('group:'): chosen |= {p['id'] for p in pages if p.get('group') == selector[6:]}
                else:
                    require(selector in ids, f'Dependency route is not in catalogue: {selector}')
                    chosen.add(selector)
            for route in chosen: reasons.setdefault(route,[]).append({'path':change['path'],'reason':rule['reason']})
    return reasons, unknown
def config(directory): return read(Path(directory)/'iteration.json')
def get_plan(directory):
    directory = Path(directory); pointer = read(directory/'capture-request.json')
    p = directory/pointer['plan_path']; value = read(p)
    require(sha(p) == pointer['plan_sha256'], 'Plan receipt modified')
    return value
def start(directory, base, label, root=ROOT, base_source=None, dependencies=None):
    directory, base, root = Path(directory).resolve(), Path(base).resolve(), Path(root).resolve()
    require(not (directory/'iteration.json').exists(), 'Iteration already initialized')
    directory.mkdir(parents=True,exist_ok=True)
    # An early coordinator snapshot can precede tool initialization; never rewrite it.
    initial = directory/'source-start.json'
    if not initial.exists(): write(initial,snapshot(root),True)
    initial_value = read(initial)
    require(digest(initial_value['files']) == initial_value['fingerprint'], 'Invalid start snapshot')
    dep = Path(dependencies or HERE/'gallery_dependencies.json')
    write(directory/'dependencies.json',read(dep),True)
    m = read(base)
    if base_source is None and m.get('schema') == 2:
        prior_snapshot=base.parent.parent/'plans'/m['plan_id']/'source-end.json'
        require(prior_snapshot.is_file() and sha(prior_snapshot)==m['sources']['source_end_sha256'], 'Previous incremental source snapshot missing or changed')
        base_source=prior_snapshot
    if base_source:
        source = read(base_source)
        source = exported_source(source) if 'source_sha256' in source else source
        write(directory/'base-source.json',source,True)
    require(len({p['id'] for p in m['pages']}) == len(m['pages']), 'Duplicate base pages')
    write(directory/'iteration.json',{'schema':1,'label':label,'created_at':now(),'root':str(root),
        'base_manifest':str(base),'base_manifest_sha256':sha(base),'start_sha256':sha(initial),
        'dependencies_sha256':sha(directory/'dependencies.json'),
        'base_source_sha256':sha(directory/'base-source.json') if base_source else None},True)
    return plan(directory)
def inputs(directory):
    directory = Path(directory); c = config(directory)
    for field, p in [('base_manifest_sha256',Path(c['base_manifest'])),('start_sha256',directory/'source-start.json'),('dependencies_sha256',directory/'dependencies.json')]:
        require(sha(p) == c[field], f'Frozen {field} changed')
    if c['base_source_sha256']: require(sha(directory/'base-source.json') == c['base_source_sha256'], 'Frozen base source changed')
    base=read(c['base_manifest'])
    expected={(page['id'],o) for page in base['pages'] for o in ORIENTATIONS}
    actual=[(r['id'],r['orientation']) for r in base['entries']]
    require(len(actual)==len(set(actual)) and set(actual)==expected,'Base gallery must contain exactly one row per page/orientation; missing rows cannot count as accepted')
    return c, base, read(directory/'source-start.json'), read(directory/'dependencies.json')
def plan(directory, routes=()):
    directory = Path(directory); c,base,initial,dep = inputs(directory)
    end = snapshot(c['root'],initial['scope']); changes = difference(initial['files'],end['files'])
    reasons, unknown = impacts(changes,base['pages'],dep)
    backlog = []
    if c['base_source_sha256']:
        previous = read(directory/'base-source.json')
        backlog = difference(previous['files'],scoped_files(initial['files'],previous['scope']))
        inherited, inherited_unknown = impacts(backlog,base['pages'],dep)
        unknown = sorted(set(unknown+inherited_unknown))
        for route, why in inherited.items(): reasons.setdefault(route,[]).extend([{**r,'carried_from_prior_iteration':True} for r in why])
    # A previously pending route remains pending in later iterations.
    for row in base['entries']:
        if row.get('current_capture_status') == 'pending': reasons.setdefault(row['id'],[]).append({'reason':'Prior iteration refresh still pending','path':None})
    for route in routes:
        require(route in {p['id'] for p in base['pages']}, f'Unknown requested route: {route}')
        reasons.setdefault(route,[]).append({'reason':'Explicit additional visual check','path':None})
    core = {'schema':1,'label':c['label'],'start_fingerprint':initial['fingerprint'],'end_fingerprint':end['fingerprint'],
        'base_manifest_sha256':c['base_manifest_sha256'],'dependencies_sha256':c['dependencies_sha256'],
        'changes':changes,'carried_changes':backlog,'unknown_paths':unknown,'affected_routes':sorted(reasons),
        'requests':[{'id':p['id'],'orientation':o,'path':f'originals/{o}/{p["id"]}.jpg','sidecar':f'originals/{o}/{p["id"]}.json','reasons':reasons[p['id']]} for p in base['pages'] if p['id'] in reasons for o in ORIENTATIONS]}
    revision = digest(core); target = directory/'plans'/revision
    if not (target/'plan.json').exists():
        target.mkdir(parents=True,exist_ok=True); write(target/'source-end.json',end,True)
        write(target/'plan.json',{**core,'plan_id':revision,'planned_at':now(),'source_end_path':str((target/'source-end.json').relative_to(directory)),'source_end_sha256':sha(target/'source-end.json')},True)
    receipt = read(target/'plan.json')
    write(directory/'capture-request.json',{'plan_path':str((target/'plan.json').relative_to(directory)),'plan_sha256':sha(target/'plan.json'),**receipt})
    return {'plan_id':revision,'changed_files':len(changes),'carried_files':len(backlog),'routes':len(reasons),'views':len(core['requests']),'unknown_paths':unknown}
def current_end(directory):
    c,base,initial,dep = inputs(directory); p = get_plan(directory); end = read(Path(directory)/p['source_end_path'])
    require(sha(Path(directory)/p['source_end_path']) == p['source_end_sha256'], 'End snapshot receipt changed')
    require(snapshot(c['root'],initial['scope'])['files'] == end['files'], 'Runtime source changed after plan; run plan again before accepting captures')
    return c,base,dep,p,end
def verify_export(export_dir, end=None):
    export_dir = Path(export_dir); m = read(export_dir/'manifest.json'); b = read(export_dir/'build.json')
    require(not any(key in m for key in ('hero_candidate', 'hero_shape', 'hero_motion', 'runner_color_review')), 'Candidate-only export cannot be accepted into the shipping gallery')
    source = exported_source(m)
    require(b['source_fingerprint'] == m['source_fingerprint'], 'Build/export source mismatch')
    pack = b['files']['index.pck']['sha256']
    require(sha(export_dir/'web/index.pck') == pack, 'Actual export PCK hash mismatch')
    for name,metadata in b['files'].items():
        require(not Path(name).is_absolute() and '..' not in Path(name).parts,'Unsafe export file path')
        require(sha(export_dir/'web'/name)==metadata['sha256'],f'Actual export file hash mismatch: {name}')
    if end:
        require(scoped_files(end['files'],source['scope']) == source['files'], 'Export does not match planned current source')
    return m,b,source,pack
def state_of(sidecar):
    value = read(sidecar)
    require(isinstance(value,dict),'Malformed sidecar: expected JSON object')
    state=value.get('state',value)
    require(isinstance(state,dict),'Malformed sidecar state: expected JSON object')
    require(isinstance(state.get('build'),dict),'Malformed sidecar build: expected JSON object')
    stamp=state.get('capture_utc')
    require(isinstance(stamp,str) and bool(stamp),'Malformed capture_utc: expected UTC timestamp')
    try: parsed=dt.datetime.fromisoformat(stamp.replace('Z','+00:00'))
    except ValueError: raise ValueError('Malformed capture_utc: expected UTC timestamp') from None
    require(parsed.tzinfo is not None and parsed.utcoffset()==dt.timedelta(0),'Malformed capture_utc: expected UTC timestamp')
    touch=state.get('touch_points',0)
    require(type(touch) in (int,float) and touch >= 0 and touch < float('inf'),'Malformed touch_points: expected nonnegative finite number')
    size=state.get('canvas_backing')
    require(isinstance(size,list) and len(size)==2 and all(type(x) is int and x>0 for x in size),'Malformed canvas_backing: expected two positive integers')
    return state
def inspect_capture(capture, export_dir, root, page_ids, require_review=True, verified_export=None):
    from PIL import Image
    c = capture; key = (c.get('id'),c.get('orientation'))
    require(key[0] in page_ids and key[1] in ORIENTATIONS, f'Unknown capture key: {key}')
    if require_review:
        require(c.get('accepted') is True and bool(c.get('reviewed_by')) and bool(c.get('reviewed_at')), f'Explicit human/coordinator review missing: {key}')
    require(not c.get('validation_errors'), f'Unresolved capture errors: {key}')
    m,b,source,pack = verified_export or verify_export(export_dir)
    actual,sidecar = path_at(c['path'],root),path_at(c['sidecar'],root)
    require(sha(actual) == c['sha256'] and sha(sidecar) == c['sidecar_sha256'], f'Capture or sidecar bytes changed: {key}')
    s = state_of(sidecar); build = s.get('build',{})
    require(s.get('status') == 'ready' and not s.get('error'), f'Capture not ready/error: {key}')
    require(s.get('route') == c.get('state_route',key[0]), f'Wrong actual route: {key}')
    if c.get('state_route',key[0]) != key[0]:
        require(bool(c.get('state_checks')), f'Alias requires explicit state predicates: {key}')
    require(c.get('browser') == 'Chrome', f'Wrong browser: {key}')
    require(c['build_sha256'] == pack == build.get('pack_sha256'), f'Wrong PCK: {key}')
    require(c['source_fingerprint'] == m['source_fingerprint'] == build.get('source_fingerprint'), f'Wrong source fingerprint: {key}')
    require(c['captured_at'] == s.get('capture_utc'), f'Capture timestamp mismatch: {key}')
    require(build.get('runtime_audio_driver') == 'Dummy' and build.get('qa_auth_isolation') == 'offline_visual_qa', f'Expected silent isolated QA capture: {key}')
    with Image.open(actual) as image:
        require(image.format == 'JPEG', f'Original Chrome capture must be JPEG: {key}')
        require(list(image.size) == c['dimensions'] == s.get('canvas_backing'), f'Capture/canvas dimensions mismatch: {key}')
    w,h = c['dimensions']; require((w >= h) == (key[1]=='desktop'), f'Orientation mismatch: {key}')
    require(c.get('input_mode') == ('touch_emulation' if s.get('touch_points',0)>0 else 'desktop_input'), f'Input evidence mismatch: {key}')
    # Alternative stage on same route must explicitly state its identity and evidence.
    for dotted, expected in c.get('state_checks',{}).items():
        value = s
        for part in dotted.split('.'): value = value.get(part) if isinstance(value,dict) else None
        require(value == expected, f'State predicate failed {dotted}: {key}')
    if key[0].startswith('equipment_'):
        wardrobe = s.get('equipment',s.get('wardrobe',{}))
        require(wardrobe.get('saved_equipment_unchanged',wardrobe.get('saved_unchanged')) is True, f'Equipment capture changed save: {key}')
        require(wardrobe.get('temporary_preview') is True, f'Equipment preview state missing: {key}')
        expected=key[0].removeprefix('equipment_')
        if expected.startswith('category_'):
            require(wardrobe.get('category')==expected.removeprefix('category_'),f'Wrong equipment category: {key}')
        elif expected.endswith('_none'):
            require(wardrobe.get('category')==expected.removesuffix('_none') and wardrobe.get('none') is True and wardrobe.get('item_id')=='',f'Wrong empty equipment slot: {key}')
        else:
            require(wardrobe.get('item_id')==expected,f'Wrong selected equipment item: {key}')
    return s,source
def review(directory, export_dir, captures=None, output=None, historical_map=None):
    directory = Path(directory); c,base,dep,p,end = current_end(directory)
    m,b,source,pack = verify_export(export_dir,None if historical_map else end)
    captures = Path(captures or directory/'originals'); rows=[]
    requests=read(historical_map)['captures'] if historical_map else p['requests']
    for request in requests:
        route,orientation = request['id'],request['orientation']
        image=path_at(request['path'],c['root']) if historical_map else captures/orientation/(route+'.jpg')
        sidecar=path_at(request['sidecar'],c['root']) if historical_map else image.with_suffix('.json')
        row={'id':route,'orientation':orientation,'accepted':False,'reviewed_by':None,'reviewed_at':None,'browser':'Chrome',
            'path':str(image.resolve()),'sidecar':str(sidecar.resolve()),'build_sha256':pack,'source_fingerprint':m['source_fingerprint']}
        for name in ('state_route','state_checks','note','source_iteration'):
            if name in request:row[name]=request[name]
        errors=[]
        try:
            s=state_of(sidecar)
            row.update(sha256=sha(image),sidecar_sha256=sha(sidecar),captured_at=s.get('capture_utc'),dimensions=s.get('canvas_backing'),
                       input_mode='touch_emulation' if s.get('touch_points',0)>0 else 'desktop_input',
                       capture_scope=s.get('synthetic_state',''),url=s.get('source_url',''))
            inspect_capture(row,export_dir,c['root'],{x['id'] for x in base['pages']},False,(m,b,source,pack))
        except (ValueError,KeyError,OSError) as error: errors.append(str(error))
        row['validation_errors']=errors;rows.append(row)
    receipt={'schema':1,'label':c['label'],'accepted':False,'historical':bool(historical_map),'plan_id':p['plan_id'],'export_dir':str(Path(export_dir).resolve()),
             'export_manifest_sha256':sha(Path(export_dir)/'manifest.json'),'export_build_sha256':sha(Path(export_dir)/'build.json'),
             'build_sha256':pack,'source_fingerprint':m['source_fingerprint'],'captures':rows}
    target=Path(output or directory/'review-draft.json'); write(target,receipt)
    return {'draft':str(target),'views':len(rows),'valid_unaccepted':sum(not x['validation_errors'] for x in rows),'accepted':False}
def copy_verified(source, dest, expected):
    require(sha(source)==expected,f'Image/evidence source hash mismatch: {source}')
    dest.parent.mkdir(parents=True,exist_ok=True)
    if dest.exists() and sha(dest)==expected:return
    # Copies, not symlinks/hardlinks: later staging cannot mutate historical evidence.
    shutil.copyfile(source,dest)
def retain_row(row, base_dir, output):
    row=copy.deepcopy(row)
    for field,hash_field in [('reference','reference_sha256'),('actual','capture_sha256'),('sidecar','sidecar_public_sha256'),('pair','pair_sha256'),('phone','phone_sha256')]:
        if not row.get(field):continue
        source=base_dir/row[field]; expected=row.get(hash_field) or sha(source)
        # Preserve nested paths and bytes while preventing paths outside gallery output.
        require(not Path(row[field]).is_absolute() and '..' not in Path(row[field]).parts,'Unsafe gallery path')
        copy_verified(source,output/row[field],expected)
        row[hash_field]=expected
    return row
def comparisons(row, output):
    from PIL import Image,ImageDraw,ImageOps
    reference=Image.open(output/row['reference']).convert('RGB'); actual=Image.open(output/row['actual']).convert('RGB')
    for field,size,boxes in [('pair',(1636,854),[(12,42,800,800),(824,42,800,800)]),('phone',(824,1696),[(12,42,800,800),(12,884,800,800)])]:
        canvas=Image.new('RGB',size,'#102035');draw=ImageDraw.Draw(canvas)
        for image,box,label in zip([reference,actual],boxes,['REFERENCE',f'GAME · {row["source_iteration"]} · {row["capture_provenance"]["captured_at"][:10]}']):
            x,y,w,h=box; tile=ImageOps.contain(image,(w,h),Image.Resampling.LANCZOS)
            draw.text((x,y-25),label,fill='white');canvas.paste(tile,(x+(w-tile.width)//2,y+(h-tile.height)//2))
        rel=f'{"pairs" if field=="pair" else "phone"}/{row["orientation"]}-{row["id"]}.jpg';p=output/rel;p.parent.mkdir(parents=True,exist_ok=True);canvas.save(p,quality=92)
        row[field]=rel;row[field+'_sha256']=sha(p)
def changed_overviews(rows, output):
    """Only changed pages are recomposed; exact raw files stay untouched."""
    from PIL import Image,ImageDraw,ImageOps
    sheets=[]
    for orientation in ORIENTATIONS:
        selected=[r for r in rows if r['orientation']==orientation and r.get('changed_this_iteration')]
        if not selected:continue
        # Six states per sheet keeps phone zoom useful without huge allocations.
        for start in range(0,len(selected),6):
            batch=selected[start:start+6];canvas=Image.new('RGB',(1236,450*len(batch)),'#102035');draw=ImageDraw.Draw(canvas)
            for i,row in enumerate(batch):
                y=i*450;status='REFRESH PENDING — PREVIOUS FRAME' if row['current_capture_status']=='pending' else 'ACCEPTED'
                draw.text((12,y+8),f'{row["title"]} · {status}',fill='white')
                for j,field in enumerate(['reference','actual']):
                    if not row.get(field):continue
                    with Image.open(output/row[field]) as original:image=ImageOps.contain(original.convert('RGB'),(600,400),Image.Resampling.LANCZOS)
                    x=12+j*612;canvas.paste(image,(x+(600-image.width)//2,y+40+(400-image.height)//2))
            path=f'overviews/{orientation}-changed-{start//6+1:02}.jpg';target=output/path;target.parent.mkdir(exist_ok=True);canvas.save(target,quality=92)
            sheets.append({'path':path,'sha256':sha(target),'orientation':orientation,'group':'changed','ids':[r['id'] for r in batch],
                           'title':f'{orientation.title()} · Changed pages {start+1}–{start+len(batch)}','dimensions':list(canvas.size)})
    return sheets
def acceptance_rows(path,directory,end,base,dep,plan_value,historical=False):
    approval=read(path);require(approval.get('accepted') is True,'Root acceptance missing; drafts cannot promote')
    require(approval.get('historical',False)==historical,'Historical acceptance must be explicitly labeled')
    if not historical:require(approval.get('plan_id')==plan_value['plan_id'],'Acceptance belongs to an obsolete plan')
    export_dir=Path(approval['export_dir']);m,b,source,pack=verify_export(export_dir,None if historical else end)
    require(sha(export_dir/'manifest.json')==approval['export_manifest_sha256'] and sha(export_dir/'build.json')==approval['export_build_sha256'],'Accepted export receipt changed')
    require(approval['build_sha256']==pack and approval['source_fingerprint']==m['source_fingerprint'],'Accepted root identity mismatch')
    seen=set();result=[]; page_ids={x['id'] for x in base['pages']}
    changed_since=impacts(difference(source['files'],scoped_files(end['files'],source['scope'])),base['pages'],dep)[0] if historical else {}
    for capture in approval['captures']:
        key=(capture['id'],capture['orientation']);require(key not in seen,'Duplicate accepted capture');seen.add(key)
        state,_=inspect_capture(capture,export_dir,config(directory)['root'],page_ids,verified_export=(m,b,source,pack))
        result.append((capture,state,key[0] in changed_since))
    return result
def build(directory, acceptance=None, historical=None):
    directory=Path(directory);c,base,dep,p,end=current_end(directory);out=directory/'gallery';out.mkdir(exist_ok=True)
    # Validate every incoming frame before touching any retained gallery file.
    approved=[(is_historical,path,acceptance_rows(path,directory,end,base,dep,p,is_historical))
              for is_historical,path in [(True,x) for x in historical or []]+([(False,acceptance)] if acceptance else [])]
    rows={(r['id'],r['orientation']):retain_row(r,Path(c['base_manifest']).parent,out) for r in base['entries']}
    affected=set(p['affected_routes']);fresh=set();history=[]; accepted_paths=[]
    for key,row in rows.items():
        row['refreshed_this_iteration']=False
        row['changed_this_iteration']=key[0] in affected
        row['current_capture_status']='pending' if key[0] in affected else row.get('current_capture_status','accepted')
        row['availability']='previous_pending' if row['current_capture_status']=='pending' and row.get('actual') else row.get('availability','pending')
    for is_historical,path,candidates in approved:
        accepted_paths.append({'path':str(Path(path).resolve()),'sha256':sha(path),'historical':is_historical})
        for capture,state,stale in candidates:
            key=(capture['id'],capture['orientation']);row=rows[key]
            old=row.get('capture_provenance') or {}
            require(not old.get('captured_at') or dt.datetime.fromisoformat(capture['captured_at'].replace('Z','+00:00'))>dt.datetime.fromisoformat(old['captured_at'].replace('Z','+00:00')),'Replacement is not newer than retained capture')
            history.append({'id':key[0],'orientation':key[1],'prior':copy.deepcopy(row)})
            rel=f'captures/{key[1]}-{key[0]}.jpg';copy_verified(path_at(capture['path'],c['root']),out/rel,capture['sha256'])
            side=f'provenance/{key[1]}-{key[0]}.json';write(out/side,safe(state))
            row.update(actual=rel,capture_sha256=capture['sha256'],dimensions=capture['dimensions'],capture_format='JPEG',sidecar=side,
                       sidecar_public_sha256=sha(out/side),capture_provenance=safe(copy.deepcopy(capture)),
                       source_iteration=capture.get('source_iteration','prior accepted pass') if is_historical else c['label'],
                       availability='previous_pending' if stale else 'accepted',current_capture_status='pending' if stale else 'accepted',
                       refreshed_this_iteration=not is_historical,input_mode=capture['input_mode'])
            row.pop('source_manifest_capture_sha256',None)
            comparisons(row,out)
            if not is_historical:fresh.add(key)
    pending=[{'id':r['id'],'orientation':r['orientation']} for r in rows.values() if r['current_capture_status']=='pending']
    result={'schema':2,'iteration':c['label'],'generated_utc':now(),'status':'pending_refresh' if pending else 'accepted',
            'scope':'Full catalogue; only source-affected views need new captures. Retained captures keep original dates/builds. Phone viewport or touch emulation is labeled per frame.',
            'pages':copy.deepcopy(base['pages']),'entries':list(rows.values()),'page_count':len(base['pages']),
            'accepted_views':len(rows)-len(pending),'pending_current_views':len(pending),'fresh_views':len(fresh),
            'affected_routes':p['affected_routes'],'plan_id':p['plan_id'],'source_fingerprint':end['fingerprint'],
            'prior_collections':base.get('prior_collections',[]),'overviews':[],
            'sources':{'base_manifest_sha256':c['base_manifest_sha256'],'source_start_sha256':c['start_sha256'],'source_end_sha256':p['source_end_sha256']}}
    result['overviews']=changed_overviews(result['entries'],out)
    # Clear obsolete coverage labels copied from old page definitions.
    for page in result['pages']:
        page['current_capture_status']='pending' if any(x['id']==page['id'] for x in pending) else 'accepted'
    write(out/'manifest.json',safe(result))
    template=(HERE/'gallery_assets/template.html').read_text()
    (out/'index.html').write_text(template.replace('__DATA__',json.dumps(safe(result),ensure_ascii=False).replace('</','<\\/')))
    shutil.copyfile(HERE/'gallery_assets/gallery.js',out/'gallery.js')
    write(directory/'build-receipt.json',{'built_at':now(),'plan_id':p['plan_id'],'manifest_sha256':sha(out/'manifest.json'),
          'accepted_inputs':accepted_paths,'fresh_views':len(fresh),'pending':pending,'prior_views_replaced':history})
    return {'gallery':str(out.resolve()),'pages':len(base['pages']),'views':len(rows),'fresh_views':len(fresh),'pending_views':len(pending)}
def delivery(directory):
    directory=Path(directory);c,base,dep,p,end=current_end(directory);receipt=read(directory/'build-receipt.json');out=directory/'gallery';m=read(out/'manifest.json')
    require(receipt['plan_id']==p['plan_id'] and sha(out/'manifest.json')==receipt['manifest_sha256'],'Gallery is stale; rebuild')
    require(not receipt['pending'],'Affected views still pending; publication blocked')
    for entry in receipt['accepted_inputs']:
        require(sha(entry['path'])==entry['sha256'],'Accepted input changed since gallery build')
        acceptance_rows(entry['path'],directory,end,base,dep,p,entry['historical'])
    prior_hashes={}
    for row in base['entries']:
        for f,h in [('reference','reference_sha256'),('actual','capture_sha256'),('pair','pair_sha256'),('phone','phone_sha256'),('sidecar','sidecar_public_sha256')]:
            if row.get(f):prior_hashes.setdefault(row.get(h) or sha(Path(c['base_manifest']).parent/row[f]),str(Path(c['base_manifest']).parent/row[f]))
    jobs=[]; seen=set()
    for row in m['entries']:
        for field,h in [('reference','reference_sha256'),('actual','capture_sha256'),('pair','pair_sha256'),('phone','phone_sha256'),('sidecar','sidecar_public_sha256')]:
            if not row.get(field):continue
            path=out/row[field];value=sha(path);require(value==row[h],'Gallery asset changed')
            if value in seen:continue
            seen.add(value);jobs.append({'path':str(path.resolve()),'sha256':value,'bytes':path.stat().st_size,'action':'reuse' if value in prior_hashes else 'upload','prior_path':prior_hashes.get(value),'kind':field})
    for name in ('index.html','gallery.js','manifest.json'):
        path=out/name;jobs.append({'path':str(path.resolve()),'sha256':sha(path),'bytes':path.stat().st_size,'action':'upload','kind':'document'})
    for sheet in m['overviews']:
        path=out/sheet['path'];require(sha(path)==sheet['sha256'],'Changed overview bytes changed')
        jobs.append({'path':str(path.resolve()),'sha256':sha(path),'bytes':path.stat().st_size,'action':'upload','kind':'changed_overview'})
    result={'schema':1,'generated_at':now(),'plan_id':p['plan_id'],'status':'ready_for_incremental_upload_no_remote_writes_performed',
            'jobs':jobs,'new_files':sum(x['action']=='upload' for x in jobs),'reused_files':sum(x['action']=='reuse' for x in jobs),
            'new_bytes':sum(x['bytes'] for x in jobs if x['action']=='upload'),'publish_current_last':True}
    write(directory/'delivery-delta.json',result)
    return {k:v for k,v in result.items() if k!='jobs'}
def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    s=sub.add_parser('start');s.add_argument('--dir',required=True,type=Path);s.add_argument('--base',required=True,type=Path);s.add_argument('--label',required=True);s.add_argument('--root',type=Path,default=ROOT);s.add_argument('--base-source',type=Path);s.add_argument('--dependencies',type=Path)
    s=sub.add_parser('plan');s.add_argument('--dir',required=True,type=Path);s.add_argument('--routes',nargs='*',default=[])
    s=sub.add_parser('review');s.add_argument('--dir',required=True,type=Path);s.add_argument('--export',dest='export_dir',required=True,type=Path);s.add_argument('--captures',type=Path);s.add_argument('--output',type=Path);s.add_argument('--historical-map',type=Path)
    s=sub.add_parser('build');s.add_argument('--dir',required=True,type=Path);s.add_argument('--acceptance',type=Path);s.add_argument('--historical',action='append',type=Path)
    s=sub.add_parser('delivery-delta');s.add_argument('--dir',required=True,type=Path)
    args=vars(parser.parse_args());command=args.pop('command');args['directory']=args.pop('dir')
    try: result={'start':start,'plan':plan,'review':review,'build':build,'delivery-delta':delivery}[command](**args)
    except (ValueError,KeyError,OSError) as error: parser.exit(1,f'ERROR: {error}\n')
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
