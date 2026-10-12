#!/usr/bin/env python3
"""Build a source-bound, memory-budgeted Web release without remote writes.

Usage: python3 tools/release/prepare_web_release.py OUTPUT_DIRECTORY
Run applicable local gates before publishing. Never modifies the working game,
its import sidecars, save files, or production. Keep OUTPUT as rollback evidence.
"""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
def module(name, path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def write(path, value):path.write_text(json.dumps(value,indent=2)+'\n')

def import_sidecars():
    return {str(p.relative_to(ROOT)):sha(p) for name in ('assets','data','scenes','scripts','addons')
            for p in sorted((ROOT/name).rglob('*.import')) if p.is_file()}

def prepare(out, godot):
    gallery=module('release_inventory',ROOT/'tools/qa/gallery_iteration.py')
    web=module('release_web_preset',ROOT/'tools/qa/runner_web_perf.py')
    profile=module('release_import_profile',ROOT/'tools/release/web_import_profile.py')
    memory=module('release_pack_memory',ROOT/'tools/release/web_pack_memory.py')
    source=gallery.snapshot(ROOT)
    imports=import_sidecars()
    tooling={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),ROOT/'tools/release/web_import_profile.py',ROOT/'tools/release/web_pack_memory.py']}
    identity=hashlib.sha256(json.dumps({'source':source['fingerprint'],'tooling':tooling,'import_sidecars':imports},sort_keys=True).encode()).hexdigest()
    build_id='web-'+dt.datetime.now(dt.timezone.utc).strftime('%Y%m%d')+'-'+identity[:12]
    out.mkdir(parents=True,exist_ok=False);project=out/'project';project.mkdir();build=out/'build';build.mkdir()
    for name in ('assets','data','scenes','scripts','addons'):
        if (ROOT/name).exists():
            if __import__('sys').platform=='darwin':subprocess.run(['cp','-cR',str(ROOT/name),str(project/name)],check=True)
            else:shutil.copytree(ROOT/name,project/name)
    shutil.copy2(ROOT/'project.godot',project/'project.godot')
    config=project/'scripts/utilities/game_config.gd';original=config.read_text()
    stamped,count=re.subn(r'^const BUILD_ID: String = "[^"]*"$',f'const BUILD_ID: String = "{build_id}"',original,flags=re.M);assert count==1;config.write_text(stamped)
    sections=web._preset_sections((ROOT/'export_presets.cfg').read_text())
    preset='[preset.0]\n'+sections['preset.4']+'\n[preset.0.options]\n'+sections['preset.4.options']
    assert 'name="Web"' in preset and 'script_export_mode=2' in preset and 'tests/*,qa_shots/*,art_src/*' in preset
    (project/'export_presets.cfg').write_text(preset)
    applied=profile.apply_to_project(project,project/'data/web/ui_import_profile.json',ROOT)
    write(out/'candidate-source.json',{'source':source,'tooling_sha256':tooling,'source_import_sidecars_sha256':imports,'release_identity':identity,'build_id':build_id,'created_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'derivations':['BUILD_ID stamped only in isolated copy.','Audited Web import profile applied only in isolated copy; images/dimensions/alpha preserved.','Reviewed Web PCK ownership handoff eliminates duplicate buffer.'],'game_config_original_sha256':hashlib.sha256(original.encode()).hexdigest(),'game_config_release_sha256':sha(config),'web_import_profile':applied,'web_preset_sha256':sha(project/'export_presets.cfg')})
    receipt=[]
    for phase,args in [('import',['--import']),('export',['--export-release','Web',str(build/'index.html')])]:
        began=time.monotonic();log=out/(phase+'.log')
        with log.open('w') as stream:r=subprocess.run([godot,'--headless','--audio-driver','Dummy','--path',str(project),*args],stdout=stream,stderr=subprocess.STDOUT,timeout=600)
        text=log.read_text();okay=r.returncode==0 and 'SCRIPT ERROR:' not in text and not re.search(r'^ERROR:',text,re.M)
        receipt.append({'phase':phase,'code':r.returncode,'seconds':round(time.monotonic()-began,2),'log_sha256':sha(log),'error':not okay});write(out/'export-receipt.json',receipt)
        if not okay:raise RuntimeError(f'{phase} failed; see {log}')
    packed=profile.verify_pack(build/'index.pck',project/'data/web/ui_import_profile.json');write(out/'web-import-pack-receipt.json',packed)
    write(out/'pack-memory-receipt.json',memory.apply(build/'index.js'))
    # Runtime source edits during a build invalidate this candidate.
    html=(build/'index.html').read_text();(out/'exported-index.html').write_text(html)
    assert '<base ' not in html and '__wwQA' not in html and 'audio-driver' not in html and 'Dummy' not in html
    prefix=f'releases/{build_id}/'
    html=html.replace('<head>',f'<head>\n<base href="/{prefix}">\n<meta name="waddle-build" content="{build_id}">',1);(build/'index.html').write_text(html)
    for pattern in ('share.png','manifest.webmanifest','icon-*.png','favicon*','apple-touch-icon.png','loader-*-v3.webp'):
        for path in (ROOT/'web').glob(pattern):shutil.copy2(path,build/path.name)
    for i,script in enumerate(re.findall(r'<script[^>]*>(.*?)</script>',html,re.S)):
        path=out/f'script-{i}.js';path.write_text(script);subprocess.run(['node','--check',str(path)],check=True,capture_output=True)
    pack=build/'index.pck';parts=[]
    with pack.open('rb') as stream:
        while chunk:=stream.read(100*1024*1024):
            path=build/f'index.pck.part{len(parts)}';path.write_bytes(chunk);parts.append({'key':prefix+path.name,'bytes':len(chunk),'sha256':sha(path)})
    spec={'version':1,'bytes':pack.stat().st_size,'sha256':sha(pack),'parts':parts};(build/'index.pck.parts.json').write_text(json.dumps(spec,separators=(',',':')))
    joined=hashlib.sha256()
    for row in parts:
        with (build/Path(row['key']).name).open('rb') as stream:
            while chunk:=stream.read(1024*1024):joined.update(chunk)
    assert joined.hexdigest()==spec['sha256']
    files={path.name:{'bytes':path.stat().st_size,'sha256':sha(path),'key':prefix+path.name} for path in sorted(build.iterdir()) if path.is_file()}
    assert gallery.snapshot(ROOT)['fingerprint']==source['fingerprint'],'Source changed during build'
    assert import_sidecars()==imports,'Import settings changed during build'
    assert all(sha(ROOT/path)==digest for path,digest in tooling.items()),'Release tooling changed during build'
    write(out/'candidate-artifacts.json',{'build_id':build_id,'prefix':prefix,'source_fingerprint':source['fingerprint'],'files':files,'upload_names':[name for name in files if name!='index.pck'],'normal_audio':True,'qa_bridge':False,'pack_reassembly_verified':True,'web_import_profile':packed})
    print(json.dumps({'build_id':build_id,'pack_bytes':spec['bytes'],'profiled_textures':packed['verified_textures'],'normal_audio':True,'qa_bridge':False}))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('out',type=Path);parser.add_argument('--godot',default='/Applications/Godot.app/Contents/MacOS/Godot');args=parser.parse_args();prepare(args.out.resolve(),args.godot)
