#!/usr/bin/env python3
"""Package existing gallery and penguin reviews into one portable static site.

No screenshot generation, engine, browser, acceptance changes, or publication.
Media and raw evidence are copied byte-for-byte; only presentation links change.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASE = Path('/Users/ninja/Fun/waddle-wars/qa_shots/menu-reference-review-20261009-iteration14/gallery')
DEFAULT_TASK = ROOT/'qa_shots/penguin-motion-corrections-20261012'
DEFAULT_OUTPUT = ROOT/'qa_shots/waddle-wars-studio-20261012/site'
HISTORY = {
    60261:'penguin-shape-gate-20261011',
    60263:'penguin-rear-refinement-20261011',
    60265:'penguin-silhouette-overlay-20261011',
    60269:'penguin-feet-finish-20261011',
    60271:'penguin-right-foot-20261012',
    60275:'penguin-tail-fan-flipper-match-20261012',
    60277:'penguin-motion-v1-20261012',
    60284:'penguin-motion-corrections-20261012',
}
MEDIA = {'.png','.jpg','.jpeg','.webp','.gif','.mp4','.svg','.webm','.avif'}
ALLOWED = MEDIA|{'.html','.json','.txt','.md','.js','.css','.ffconcat'}
LINK_KEYS = {'url','href','src','path','actual','mask','scene','source','native_feet','reference','reference_mask','desktop','mobile','detail','evidence','source_art','source_prompt'}
ATTR = re.compile(r'\b(href|src)=("|\')(.*?)\2', re.I)
LITERAL = re.compile(r'(["\'])([^"\'\n<>]+\.(?:png|jpe?g|webp|gif|mp4|svg|webm|html|json|js|css|md|txt)(?:[?#][^"\'\n<>]*)?)\1',re.I)


def sha(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')


def copy_bytes(source,dest):
    dest.parent.mkdir(parents=True,exist_ok=True)
    if sys.platform=='darwin':
        result=subprocess.run(['cp','-c',str(source),str(dest)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if result.returncode==0:return
    shutil.copyfile(source,dest)


class Links(HTMLParser):
    def __init__(self):
        super().__init__();self.urls=[]
    def handle_starttag(self,tag,attrs):
        self.urls.extend(v for k,v in attrs if k in ('href','src') and v)


class Packager:
    def __init__(self,root,base,task,output,history=None):
        self.root=Path(root).resolve();self.base=Path(base).resolve();self.task=Path(task).resolve();self.out=Path(output).resolve()
        self.history={port:name for port,name in (HISTORY if history is None else history).items()
                      if self.root/'qa_shots'/name != self.task}
        self.maps=[(self.base,Path('.')),(self.task,Path('penguin'))]
        self.maps += [(self.root/'qa_shots'/name,Path('penguin/history')/name) for name in self.history.values()]
        self.sources={};self.destinations={};self.queue=[];self.records={};self.link_edges=[];self.unavailable=[]

    def destination(self,source):
        source=source.resolve()
        for base,dest in sorted(self.maps,key=lambda pair:len(str(pair[0])),reverse=True):
            if source.is_relative_to(base):return self.out/dest/source.relative_to(base)
        return self.out/'penguin/shared'/sha(source)[:16]/source.name

    def add(self,source,dest=None):
        source=Path(source).resolve()
        if not source.is_file():raise ValueError(f'Missing source dependency: {source}')
        if source.suffix.lower() not in ALLOWED:raise ValueError(f'Not a static review asset: {source}')
        dest=(Path(dest) if dest else self.destination(source)).resolve()
        if not dest.is_relative_to(self.out):raise ValueError('Destination escapes site')
        if dest in self.destinations and self.destinations[dest]!=source:raise ValueError(f'Destination collision: {dest}')
        if source in self.sources:return self.sources[source]
        self.sources[source]=dest;self.destinations[dest]=source;self.queue.append(source)
        return dest

    def add_tree(self,source,dest=None):
        source=Path(source)
        for p in sorted(source.rglob('*')):
            if p.is_file() and p.suffix.lower() in ALLOWED:
                self.add(p,Path(dest)/p.relative_to(source) if dest else None)

    def local_url(self,source,dest,value,required=False):
        value=html.unescape(value);url=urlsplit(value)
        if not value or value.startswith(('data:','mailto:','javascript:','#')):return value
        if value.startswith('${') or '${' in value:return value
        target=None
        if url.scheme or url.netloc:
            if url.hostname not in ('localhost','127.0.0.1','::1'):return value
            if url.port in self.history:
                target=self.root/'qa_shots'/self.history[url.port]/unquote(url.path.lstrip('/'))
            else:
                # Historical engine links cannot be replayed by an offline site.
                notice=self.out/'penguin/history/runtime-unavailable.html'
                self.unavailable.append({'source':str(source),'original_url_without_query':f'{url.scheme}://{url.netloc}{url.path}'})
                return os.path.relpath(notice,dest.parent)
        else:
            target=(source.parent/unquote(url.path)).resolve()
        # Every gallery return joins the ONE primary site, not a copied child gallery.
        if target.name=='index.html' and target.parent.name=='gallery':
            return os.path.relpath(self.out/'index.html',dest.parent)
        # Studio-only links return through the root collection selection.
        if target==self.task/'studio/index.html':
            return os.path.relpath(self.out/'index.html',dest.parent)+'#collection=penguin'
        if not target.is_file():
            if required:raise ValueError(f'Broken presentation link: {source}: {value}')
            return value
        if target.suffix.lower() not in ALLOWED:
            if required:raise ValueError(f'Non-static presentation dependency: {target}')
            return value
        mapped=self.add(target)
        self.link_edges.append({'from':str(dest.relative_to(self.out)),'to':str(mapped.relative_to(self.out))})
        suffix=('?'+url.query if url.query else '')+('#'+url.fragment if url.fragment else '')
        return os.path.relpath(mapped,dest.parent)+suffix

    def rewrite_json(self,value,source,dest,key=''):
        if isinstance(value,dict):return {k:self.rewrite_json(v,source,dest,k) for k,v in value.items()}
        if isinstance(value,list):return [self.rewrite_json(v,source,dest,key) for v in value]
        if isinstance(value,str) and (key in LINK_KEYS or key.endswith('_url')):
            return self.local_url(source,dest,value)
        return value

    def rewrite_html(self,text,source,dest):
        text=ATTR.sub(lambda m:f'{m[1]}={m[2]}{html.escape(self.local_url(source,dest,m[3],True),quote=True)}{m[2]}',text)
        # Fetch calls, image literals, and embedded review JSON URL strings.
        text=LITERAL.sub(lambda m:m[1]+self.local_url(source,dest,m[2])+m[1],text)
        if source==self.task/'studio/index.html':
            text=text.replace('<title>Penguin Studio · Waddle Wars</title>','<title>Penguin · Waddle Wars Studio</title>')
            text=text.replace('Penguin Studio','Penguin')
            text=text.replace('all in one place.','alongside the full game gallery.')
            text=text.replace('Historical reviews open local review servers. They may be unavailable when those servers are stopped. The full game gallery retains its page list and older dated evidence.','Historical reviews are included in this site. Their original dates, source images and rejection notes remain preserved. The full game gallery keeps its complete page list.')
            text=text.replace('Local working collection','Waddle Wars Studio · Penguin collection')
        if source==self.task/'review/index.html':
            text=text.replace('← Penguin Studio','← Penguin collection')
        # Explicit top-level navigation avoids nesting the unified gallery in itself.
        root_url=os.path.relpath(self.out/'index.html',dest.parent)
        text=re.sub(r'<a\b([^>]*href=["\']'+re.escape(root_url)+r'(?:#[^"\']*)?["\'][^>]*)>',lambda m:'<a'+re.sub(r'\s+target=["\'][^"\']*["\']','',m[1])+' target="_top">',text)
        if '/penguin/history/' in str(dest):
            banner=f'<aside style="padding:12px 18px;background:#fff1c9;color:#3b3220;font:14px system-ui">Historical review · {html.escape(source.parent.parent.name)} · Preserved earlier evidence, not the current candidate. <a href="{root_url}#collection=penguin" target="_top">Return to Penguin collection</a></aside>'
            if '<body>' in text:text=text.replace('<body>','<body>'+banner,1)
            else:text=text.replace('<main>','<main>'+banner,1)
        return text

    def process(self):
        while self.queue:
            source=self.queue.pop(0);dest=self.sources[source];source_hash=sha(source)
            if source.suffix=='.html' and not source.is_relative_to(self.base):
                dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(self.rewrite_html(source.read_text(),source,dest))
            elif source.name=='comparison-data.json':
                write(dest,self.rewrite_json(read(source),source,dest))
            else:copy_bytes(source,dest)
            output_hash=sha(dest)
            self.records[str(dest.relative_to(self.out))]={'source':str(source),'source_sha256':source_hash,'output_sha256':output_hash,'bytes':dest.stat().st_size,'byte_identical':source_hash==output_hash}
            if source.suffix.lower() in MEDIA and source_hash!=output_hash:raise ValueError(f'Media changed: {source}')


def validate_site(output):
    output=Path(output).resolve();checked=0;external=[];missing=[];localhost=[]
    for file in output.rglob('*.html'):
        text=file.read_text();parser=Links();parser.feed(text)
        # Main manifest embeds historical source URLs as evidence, not dependencies.
        code=re.sub(r'<script\b[^>]*id=["\']catalogue-data["\'][^>]*>.*?</script>','',text,flags=re.S)
        urls=parser.urls+[m[2] for m in LITERAL.finditer(code)]
        for value in urls:
            value=html.unescape(value)
            if not value or value.startswith(('#','data:','mailto:','javascript:')) or '${' in value:continue
            url=urlsplit(value)
            if url.hostname in ('localhost','127.0.0.1','::1'):localhost.append((str(file.relative_to(output)),value));continue
            if url.scheme or url.netloc:external.append(value);continue
            path=(file.parent/unquote(url.path)).resolve()
            # Skip regex hits in explanatory prose/code instead of asset strings.
            if ' ' in url.path and not path.exists():continue
            checked+=1
            if not path.is_relative_to(output) or not path.is_file():missing.append((str(file.relative_to(output)),value))
    for file in output.rglob('comparison-data.json'):
        def walk(v,key=''):
            if isinstance(v,dict):
                for k,x in v.items():walk(x,k)
            elif isinstance(v,list):
                for x in v:walk(x,key)
            elif isinstance(v,str) and (key in LINK_KEYS or key.endswith('_url')):
                u=urlsplit(v)
                if Path(u.path).suffix.lower() not in ALLOWED:return
                if u.hostname in ('localhost','127.0.0.1','::1'):localhost.append((str(file),v))
                elif not u.scheme and not (file.parent/unquote(u.path)).is_file():missing.append((str(file),v))
        walk(read(file))
    manifest_file=output/'manifest.json'
    if manifest_file.exists():
        manifest=read(manifest_file);paths=[]
        external.extend(item['url'] for item in manifest.get('prior_collections',[]) if urlsplit(item.get('url','')).scheme in ('https','http'))
        for row in manifest.get('entries',[]):paths.extend(row.get(k) for k in ('reference','actual','pair','phone','sidecar') if row.get(k))
        paths.extend(s['path'] for s in manifest.get('overviews',[]));paths.extend(s['path'] for s in manifest.get('studio_collections',[]))
        for value in paths:
            checked+=1;target=(output/value).resolve()
            if not target.is_relative_to(output) or not target.is_file():missing.append(('manifest.json',value))
    if missing or localhost:raise ValueError(json.dumps({'missing':missing,'localhost_dependencies':localhost},indent=2))
    inventory_file=output/'provenance/package-inventory.json';hashes=0
    if inventory_file.exists():
        for rel,r in read(inventory_file)['files'].items():
            if sha(output/rel)!=r['output_sha256']:raise ValueError(f'Packaged asset changed: {rel}')
            if r.get('preserved_original') and sha(output/r['preserved_original'])!=r['source_sha256']:raise ValueError(f'Preserved source changed: {rel}')
            hashes+=1
    return {'local_links_checked':checked,'output_hashes_checked':hashes,'missing':[],'localhost_dependencies':[],'external_historical_links':sorted(set(external))}


def build(root=ROOT,base=DEFAULT_BASE,task=DEFAULT_TASK,output=DEFAULT_OUTPUT,history=None,
          preserve_gallery_iteration=False):
    root,base,task,output=map(lambda p:Path(p).resolve(),(root,base,task,output))
    if output.exists() and any(output.iterdir()):raise ValueError('Output must be empty; preserve existing packaged evidence or choose a new output')
    original=read(base/'manifest.json');manifest=copy.deepcopy(original)
    pack=Packager(root,base,task,output,history)
    pack.add_tree(base)
    for part in ('studio','review','candidate-originals'):pack.add_tree(task/part)
    for name in pack.history.values():
        prior=root/'qa_shots'/name
        if not (prior/'review/index.html').is_file():raise ValueError(f'Missing dated review: {prior}')
        pack.add_tree(prior/'review');pack.add_tree(prior/'candidate-originals')
    # Small receipts linked from the current collection; source packages excluded.
    for name in ('final-capture-validation.json','comparison-framing-disclosures.json','source-freeze.json','isolated-color-review.json','analysis-reference/actual-visual-audit.json','analysis-reference/actual-c0444-visual-audit.json'):
        if (task/name).exists():pack.add(task/name)
    pack.process()
    notice=output/'penguin/history/runtime-unavailable.html';notice.parent.mkdir(parents=True,exist_ok=True)
    notice.write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>Historical runtime</title><main><h1>Historical runtime is archived</h1><p>This old engine session is no longer part of the static review. Original captures and dated evidence remain available in the historical review.</p><a href="../../index.html#collection=penguin" target="_top">Return to Penguin collection</a></main></html>')
    capture_dates=sorted({e.get('capture_provenance',{}).get('captured_at','')[:10]
                          for e in original['entries']} - {''})
    date_label=', '.join(capture_dates) or 'dates unavailable; inspect original capture evidence'
    manifest['studio_collections']=[{'id':'penguin','title':'Penguin model & motion','path':'penguin/studio/index.html','note':'Preserved model and motion studies · human review pending'}]
    if preserve_gallery_iteration:
        pending=original.get('pending_current_views',original.get('pending_views',0))
        gallery_note=(f'Game gallery iteration {original["iteration"]}: '
                      f'{original.get("fresh_views",0)} fresh of {len(original["entries"])} views, '
                      f'{pending} pending. Capture dates: {date_label}. '
                      'This turn and each view’s acceptance/provenance are preserved from the supplied gallery. ')
    else:
        gallery_note=f'Game page captures: {date_label} (preserved historical evidence). '
        manifest['affected_routes']=[];manifest['fresh_views']=0
        for row in manifest['entries']:
            row['refreshed_this_iteration']=False;row['changed_this_iteration']=False
    manifest['studio_note']=(gallery_note+'Penguin studies remain separately dated evidence; human review pending. '
                             'Packaging creates no captures, approvals, or production promotion.')
    manifest['studio_packaging']={'brand':'Waddle Wars Studio','source_gallery_manifest_sha256':sha(base/'manifest.json'),'source_gallery_iteration':original['iteration'],'capture_regeneration':False,'human_approval':False,'preserve_gallery_iteration':preserve_gallery_iteration,'base_affected_routes':original.get('affected_routes',[]),'base_fresh_views':original.get('fresh_views',0)}
    write(output/'manifest.json',manifest)
    assets=root/'tools/qa/gallery_assets'
    template=(assets/'template.html').read_text();(output/'index.html').write_text(template.replace('__DATA__',json.dumps(manifest,ensure_ascii=False).replace('</','<\\/')))
    copy_bytes(assets/'gallery.js',output/'gallery.js')
    copy_bytes(base/'manifest.json',output/'provenance/base-gallery-manifest.json')
    # Original page and acceptance evidence remain identical; only package-turn flags differ.
    assert manifest['pages']==original['pages']
    if preserve_gallery_iteration:
        # This turn is the supplied iteration, not a new packaging iteration.
        # Preserve pending evidence as pending; do not invent an acceptance.
        assert manifest['entries']==original['entries']
    for before,after in zip(original['entries'],manifest['entries']):
        assert {k:v for k,v in before.items() if k not in ('refreshed_this_iteration','changed_this_iteration')}=={k:v for k,v in after.items() if k not in ('refreshed_this_iteration','changed_this_iteration')}
    for rel,record in pack.records.items():
        record['output_sha256']=sha(output/rel);record['byte_identical']=record['source_sha256']==record['output_sha256']
        if not record['byte_identical']:
            preserved=Path('provenance/source-documents')/(rel+'.original')
            copy_bytes(Path(record['source']),output/preserved)
            record['preserved_original']=str(preserved)
    validation=validate_site(output)
    source_unchanged=all(sha(Path(r['source']))==r['source_sha256'] for r in pack.records.values())
    if not source_unchanged:raise ValueError('Source changed during packaging')
    inventory={'schema':1,'brand':'Waddle Wars Studio','source_files_unchanged':source_unchanged,'files':pack.records}
    write(output/'provenance/package-inventory.json',inventory)
    validation=validate_site(output)
    receipt={'builder_sha256':sha(Path(__file__)),'gallery_template_sha256':sha(assets/'template.html'),'gallery_script_sha256':sha(assets/'gallery.js'),'base_gallery':str(base),'base_manifest_sha256':sha(base/'manifest.json'),'packaged_manifest_sha256':sha(output/'manifest.json'),'page_count':len(manifest['pages']),'accepted_views':manifest['accepted_views'],'game_page_capture_dates':capture_dates,'new_game_page_captures':0,'preserved_gallery_fresh_views':manifest.get('fresh_views',0),'preserve_gallery_iteration':preserve_gallery_iteration,'this_turn_routes':manifest.get('affected_routes',[]),'penguin_current_candidate':read(task/'final-capture-validation.json')['candidate_sha256'],'human_approval':False,'source_files_unchanged':source_unchanged,'media_byte_identical':all(r['byte_identical'] for f,r in pack.records.items() if Path(f).suffix.lower() in MEDIA),'source_file_count':len(pack.records),'packaged_bytes':sum(f.stat().st_size for f in output.rglob('*') if f.is_file()),'inventory_sha256':sha(output/'provenance/package-inventory.json'),'retired_engine_links':pack.unavailable,'validation':validation}
    write(output/'provenance/build-receipt.json',receipt)
    return receipt


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=ROOT);p.add_argument('--base-gallery',type=Path,default=DEFAULT_BASE);p.add_argument('--penguin-task',type=Path,default=DEFAULT_TASK);p.add_argument('--output',type=Path,default=DEFAULT_OUTPUT);p.add_argument('--validate-only',action='store_true')
    p.add_argument('--preserve-gallery-iteration',action='store_true',help='Keep the supplied gallery’s This turn routes, fresh/pending views, and per-frame provenance; does not capture or approve anything')
    a=p.parse_args()
    result=validate_site(a.output) if a.validate_only else build(a.root,a.base_gallery,a.penguin_task,a.output,preserve_gallery_iteration=a.preserve_gallery_iteration)
    print(json.dumps({k:v for k,v in result.items() if k not in ('retired_engine_links',)},indent=2))


if __name__=='__main__':main()
