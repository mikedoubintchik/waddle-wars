#!/usr/bin/env python3
"""Prepare/build/serve a fresh localhost-only production-wrapper QA export.

Never opens a browser. Never edits production project/presets or old exports.
prepare must be called only after the coordinator freezes runtime sources.
"""
from __future__ import annotations
import argparse
import datetime as dt
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
GODOT = '/Applications/Godot.app/Contents/MacOS/Godot'
offline_spec = importlib.util.spec_from_file_location('qa_offline', ROOT/'tools/qa/chrome_reference_offline.py')
offline = importlib.util.module_from_spec(offline_spec)
offline_spec.loader.exec_module(offline)
spec = importlib.util.spec_from_file_location('web_perf_helpers', ROOT/'tools/qa/runner_web_perf.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
import_profile_spec = importlib.util.spec_from_file_location('web_import_profile', ROOT/'tools/release/web_import_profile.py')
import_profile = importlib.util.module_from_spec(import_profile_spec)
import_profile_spec.loader.exec_module(import_profile)
memory_spec = importlib.util.spec_from_file_location('web_pack_memory', ROOT/'tools/release/web_pack_memory.py')
pack_memory = importlib.util.module_from_spec(memory_spec)
memory_spec.loader.exec_module(pack_memory)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def write(path, value): path.write_text(json.dumps(value, indent=2)+'\n')
def now(): return dt.datetime.now(dt.timezone.utc).isoformat()
def inventory(project):
    return {str(p.relative_to(project)):sha(p) for p in sorted(project.rglob('*'))
            if p.is_file() and '.godot' not in p.parts and not p.name.endswith('.import')}

def prepare(out, hero_candidate_runtime=False, hero_shape_package=None, hero_motion_package=None, runner_color_review=False):
    if sum([bool(hero_candidate_runtime), hero_shape_package is not None, hero_motion_package is not None]) > 1:
        raise ValueError('Choose one isolated candidate contract: runtime, shape/surface or motion')
    color_module = None
    if runner_color_review:
        if hero_motion_package is None:
            raise ValueError('--runner-color-review requires --hero-motion-package; never shipping gallery evidence')
        color_spec = importlib.util.spec_from_file_location('runner_color_candidate', ROOT/'tools/qa/runner_color_candidate.py')
        color_module = importlib.util.module_from_spec(color_spec)
        color_spec.loader.exec_module(color_module)
        color_module.validate_source(ROOT)
    shape_module = None
    if hero_shape_package is not None:
        shape_spec = importlib.util.spec_from_file_location('shape_candidate_export', ROOT/'tools/qa/shape_candidate_export.py')
        shape_module = importlib.util.module_from_spec(shape_spec)
        shape_spec.loader.exec_module(shape_module)
        shape_module.validate_package(hero_shape_package)
    motion_module = None
    if hero_motion_package is not None:
        motion_spec = importlib.util.spec_from_file_location('motion_candidate_export', ROOT/'tools/qa/motion_candidate_export.py')
        motion_module = importlib.util.module_from_spec(motion_spec)
        motion_spec.loader.exec_module(motion_module)
        motion_module.validate_package(hero_motion_package)
    out.mkdir(parents=True, exist_ok=False)
    project = out/'project'; project.mkdir()
    for name in ('assets','data','scenes','scripts'):
        # macOS copy-on-write keeps independent mutable snapshot bytes.
        subprocess.run(['cp','-cR',str(ROOT/name),str(project/name)], check=True)
    shutil.copy2(ROOT/'project.godot', project/'project.godot')
    import_receipt = import_profile.apply_to_project(project, project/'data/web/ui_import_profile.json')
    source = inventory(project)
    preset_source = (ROOT/'export_presets.cfg').read_text()
    sections = helpers._preset_sections(preset_source)
    preset = '[preset.0]\n'+sections['preset.4']+'\n[preset.0.options]\n'+sections['preset.4.options']
    assert 'name="Web"' in preset and 'script_export_mode=2' in preset
    assert 'tests/*,qa_shots/*,art_src/*' in preset
    assert 'html/custom_html_shell=""' in preset
    preset = preset.replace('include_filter="data/wardrobe/*.json,data/commerce/*.json"',
        'include_filter="data/wardrobe/*.json,data/commerce/*.json,_qa_local/*.js"',1)
    (out/'source-export-presets.cfg').write_text(preset_source)
    (project/'export_presets.cfg').write_text(preset)
    token = uuid.uuid4().hex
    identity = 'waddle-chrome-reference-'+uuid.uuid4().hex
    text = (project/'project.godot').read_text()
    text = re.sub(r'^config/name="[^"]*"$', 'config/name="'+identity+'"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+identity+'"', text, flags=re.M)
    text = text.replace('[display]', 'ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"\n\n[qa]\nroute_token="'+token+'"\n\n[display]', 1)
    (project/'project.godot').write_text(text)
    local = project/'_qa_local'; local.mkdir()
    for suffix in ('gd','js'):
        shutil.copy2(ROOT/f'tools/qa/chrome_reference_bridge.{suffix}', local/f'chrome_reference_bridge.{suffix}')
    (out/'web').mkdir()
    head = helpers._quoted_multiline_option(sections['preset.4.options'], 'html/head_include')
    (out/'production-head.html').write_text(head)
    manifest = {'prepared_utc':now(), 'source_sha256':source,
        'source_fingerprint':hashlib.sha256(json.dumps(source,sort_keys=True).encode()).hexdigest(),
        'source_preset_sha256':sha(ROOT/'export_presets.cfg'),
        'production_head_sha256':sha(out/'production-head.html'),
        'web_import_profile':import_receipt,
        'export_input_sha256':inventory(project), 'qa_token':token,'user_identity':identity,
        'production_exclusions_and_script_mode_preserved':True, 'production_audio':'WebAudio; mute Chrome site in UI',
        'differences':['Fresh isolated localhost origin and user data; no real save copied.',
            'QA-only autoload and explicit _qa_local/*.js include in copied project, activated only by localhost and exact query token.',
            'On-demand scalar diagnostics and named real UI routing/still staging; synthetic states labeled.',
            'No quality, resolution, touch or governor override. Root sets browser viewport before navigation.',
            'Optional qa_device=iphone15promax emulates measured safe-area geometry only; capture sidecars explicitly label it. This is not physical iPhone evidence.',
            'Current production head retained as immutable input; served visual-QA HTML replaces auth/API bridges with offline stubs and adds a same-origin connection fence.',
            'Clerk/session restoration, all remote API calls and remote frames disabled for synthetic visual QA; production scripts/PCK unchanged. Auth/commerce/feedback network behavior is not accepted by these captures.',
            'No deployed CDN/HTTPS environment; release exclusions/script mode retained.']}
    if color_module is not None:
        manifest['runner_color_review'] = color_module.install(ROOT, project)
        manifest['differences'].append('Unpromoted DAY color candidate '+manifest['runner_color_review']['id']+': '+manifest['runner_color_review']['scope']+' Exact settings and source/prepared hashes are recorded in runner_color_review. Excluded from shipping gallery evidence.')
        manifest['export_input_sha256'] = inventory(project)
    if hero_candidate_runtime:
        candidate_spec = importlib.util.spec_from_file_location('hero_candidate_export', ROOT/'tools/qa/hero_candidate_export.py')
        candidate_module = importlib.util.module_from_spec(candidate_spec)
        candidate_spec.loader.exec_module(candidate_module)
        manifest['hero_candidate'] = candidate_module.install(ROOT, project)
        (out/'hero-review-controls.html').write_text(candidate_module.review_controls())
        manifest['differences'].append('Canonical authored integration fixture replaces only copied wrapper/model; QA opt-in active only in isolated browser. Camera-only front/side previews inspect same actual runner instance. This export is not shipping-gallery evidence.')
        manifest['export_input_sha256'] = inventory(project)
    if shape_module is not None:
        manifest['hero_shape'] = shape_module.install(ROOT, project, hero_shape_package)
        (out/'shape-review-controls.html').write_text(shape_module.review_controls())
        manifest['differences'].append(('Unrigged tail/flipper review: localized geometry and map changes; body and feet protected against b21. Actual imported PBR maps and lossless mip storage; animation/front review pending.' if manifest['hero_shape']['binding']['gate'] == 'rear-surface-v2' else 'Unrigged rear surface review: unchanged V9 geometry uses its actual imported PBR maps; source-preserving import mipmaps. Animation/front review pending.' if manifest['hero_shape']['binding']['gate'] == 'rear-surface-v1' else 'Gate 1 only: new unrigged plain-color geometry; animation/material detail pending.') + ' Replaces the hidden player visual after the real runner freezes. Normal rear camera/course/lighting preserved; optional rear detail changes only camera. Excluded from shipping gallery evidence.')
        manifest['export_input_sha256'] = inventory(project)
    if motion_module is not None:
        manifest['hero_motion'] = motion_module.install(ROOT, project, hero_motion_package)
        (out/'motion-review-controls.html').write_text(motion_module.review_controls())
        manifest['differences'].append('Rear motion candidate with accepted c895 rest geometry/material maps, a new skeleton and actual imported waddle/jump/slide clips. Normal gameplay camera/course retained; optional rear detail is labeled. Front/final integration pending; excluded from shipping gallery evidence.')
        manifest['export_input_sha256'] = inventory(project)
    write(out/'manifest.json',manifest)
    print(json.dumps({'prepared':str(out),'source_fingerprint':manifest['source_fingerprint']}))

def build(out, godot, silent=False):
    manifest=json.loads((out/'manifest.json').read_text()); project=out/'project'; web=out/'web'
    assert inventory(project)==manifest['export_input_sha256'], 'Prepared source changed'
    assert not (out/'build.json').exists(), 'Use fresh output; prior build must remain intact'
    assert import_profile.apply_to_project(project, project/'data/web/ui_import_profile.json') == manifest['web_import_profile'], 'Prepared Web import profile changed'
    if 'runner_color_review' in manifest:
        color = manifest['runner_color_review']
        assert 'hero_motion' in manifest and color.get('gallery_eligible') is False and color.get('human_approval') is False, 'Color review requires unpromoted motion candidate'
        assert color['binding_path'] == '_qa_local/runner_color_binding.json', 'Unexpected color binding path'
        binding = project/color['binding_path']
        assert sha(binding) == color['binding_sha256'], 'Prepared color binding changed'
        assert json.loads(binding.read_text()) == {k:v for k,v in color.items() if k != 'binding_sha256'}, 'Prepared color receipt differs from manifest'
        for relative, hashes in color['files'].items():
            assert relative in manifest['source_sha256'] and not Path(relative).is_absolute() and '..' not in Path(relative).parts, 'Unexpected color source path'
            assert manifest['source_sha256'][relative] == hashes['source_sha256'], 'Color source hash differs from original snapshot'
            assert sha(project/relative) == hashes['prepared_sha256'], 'Prepared color source changed: '+relative
    if 'hero_shape' in manifest:
        assert sha(project/'qa_shape/candidate.glb.import') == manifest['hero_shape']['binding']['importer_sha256'], 'Prepared shape importer changed'
        assert sha(out/'shape-review-controls.html') == manifest['hero_shape']['controls_sha256'], 'Prepared shape controls changed'
        assert sha(project/'_qa_local/shape_candidate_browser.gd') == manifest['hero_shape']['helper_sha256'], 'Prepared shape helper changed'
        assert sha(project/'qa_shape/candidate_binding.json') == manifest['hero_shape']['binding_sha256'], 'Prepared shape binding changed'
    if 'hero_motion' in manifest:
        motion = manifest['hero_motion']
        assert sha(project/'qa_motion/candidate.glb.import') == motion['binding']['importer_sha256'], 'Prepared motion importer changed'
        assert sha(out/'motion-review-controls.html') == motion['controls_sha256'], 'Prepared motion controls changed'
        assert sha(project/'_qa_local/motion_candidate_browser.gd') == motion['helper_sha256'], 'Prepared motion helper changed'
        assert sha(project/'qa_motion/candidate_binding.json') == motion['binding_sha256'], 'Prepared motion binding changed'
    # --import explicitly waits for the import queue before editor teardown.
    # --editor --quit can tear down the tree while font workers notify it.
    for label,args in [('import',['--import']),('export',['--export-release','Web',str(web/'index.html')])]:
        command=[godot,'--headless','--audio-driver','Dummy','--path',str(project),*args]
        with (out/f'{label}.log').open('x') as log:
            result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300)
        text=(out/f'{label}.log').read_text()
        if result.returncode or 'SCRIPT ERROR:' in text or '\nERROR:' in text:
            raise SystemExit(f'{label} failed; see preserved log')
    pack_profile = import_profile.verify_pack(web/'index.pck', project/'data/web/ui_import_profile.json')
    write(out/'web-import-profile-pack.json', pack_profile)
    memory_receipt = pack_memory.apply(web/'index.js')
    write(out/'web-pack-memory.json', memory_receipt)
    html=(web/'index.html').read_text(); (out/'standard-exported-index.html').write_text(html)
    assert (out/'production-head.html').read_text() in html
    needle='const engine = new Engine(GODOT_CONFIG);'; assert html.count(needle)==1
    if silent:
        html=html.replace(needle, 'GODOT_CONFIG.args = [...(GODOT_CONFIG.args || []), "--audio-driver", "Dummy"];\n'+needle, 1)
        manifest['runtime_audio_override']='Dummy requested for silent visual QA; no audio acceptance'
        write(out/'manifest.json', manifest)
    scalar=(ROOT/'tools/qa/memory_scalar_helper.js').read_text()
    # The watchdog is QA-only and never inspects a browser tab/process itself.
    watchdog='''
      (() => {
        const q = new URLSearchParams(location.search);
        if (!['127.0.0.1','localhost','[::1]'].includes(location.hostname) || !q.get('qa_token')) return;
        const until = performance.now() + 30 * 60 * 1000;
        async function check() {
          if (performance.now() > until) return;
          try {
            const r = await fetch(new URL('qa-stop?token=' + encodeURIComponent(q.get('qa_token')), location.href), {cache:'no-store'});
            const s = await r.json();
            if (s.stop) { engine.requestQuit(); window.__wwQAStopped = s; return; }
          } catch (_) {}
          setTimeout(check, 3000);
        }
        setTimeout(check, 3000);
      })();
'''
    build_metadata={'source_fingerprint':manifest['source_fingerprint'],
        'production_head_sha256':manifest['production_head_sha256'],
        'pack_sha256':sha(web/'index.pck'),'wasm_sha256':sha(web/'index.wasm'),
        'engine_js_sha256':sha(web/'index.js'), 'runtime_audio_driver':'Dummy' if silent else 'WebAudio',
        'qa_auth_isolation':'offline_visual_qa'}
    if 'hero_candidate' in manifest:
        build_metadata['hero_candidate'] = manifest['hero_candidate']
    if 'hero_shape' in manifest:
        build_metadata['hero_shape'] = manifest['hero_shape']
    if 'hero_motion' in manifest:
        build_metadata['hero_motion'] = manifest['hero_motion']
    if 'runner_color_review' in manifest:
        build_metadata['runner_color_review'] = manifest['runner_color_review']
    html=html.replace(needle,needle+'\nwindow.__wwQABuild = '+json.dumps(build_metadata)+';\n'+scalar+watchdog,1)
    html, isolation = offline.install(html)
    if 'hero_candidate' in manifest:
        controls = out/'hero-review-controls.html'
        assert sha(controls) == manifest['hero_candidate']['controls_sha256'], 'Prepared candidate controls changed'
        assert html.count('</body>') == 1
        html = html.replace('</body>', controls.read_text()+'\n</body>', 1)
    if 'hero_shape' in manifest:
        assert html.count('</body>') == 1
        html = html.replace('</body>', (out/'shape-review-controls.html').read_text()+'\n</body>', 1)
    if 'hero_motion' in manifest:
        assert html.count('</body>') == 1
        html = html.replace('</body>', (out/'motion-review-controls.html').read_text()+'\n</body>', 1)
    write(out/'qa-auth-isolation.json', isolation)
    manifest['qa_auth_isolation'] = isolation
    write(out/'manifest.json', manifest)
    (web/'index.html').write_text(html)
    (out/'qa-stop.json').write_text('{"stop": false}\n')
    (web/'qa-stop').symlink_to(out/'qa-stop.json')
    for pattern in ['share.png','manifest.webmanifest','icon-*.png','favicon-*','favicon.ico','apple-touch-icon.png','loader-*-v3.webp']:
        for p in (ROOT/'web').glob(pattern): shutil.copy2(p,web/p.name)
    (web/'control.html').write_text('<!doctype html><title>Waddle QA blank control</title><p>Blank control. No game runtime.</p>')
    write(out/'build.json',{'built_utc':now(),'source_fingerprint':manifest['source_fingerprint'],
        'production_head_unchanged':False,'production_head_input_preserved':True,
        'qa_auth_isolation':'offline_visual_qa',
        'production_exclusions_and_script_mode_preserved':True,
        'web_import_profile':pack_profile,
        'web_pack_memory':memory_receipt,
        'files':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(web.iterdir()) if p.is_file() and p.name!='qa-stop'},
        'no_final_browser_acceptance':True,'audio':'Dummy for silent visual QA' if silent else 'No Dummy runtime arguments; normal WebAudio, mute site through browser UI'})
    print(json.dumps({'built':str(out),'pack_bytes':(web/'index.pck').stat().st_size}))

def serve(out,port):
    manifest=json.loads((out/'manifest.json').read_text())
    class Handler(SimpleHTTPRequestHandler):
        def end_headers(self):
            self.send_header('Cross-Origin-Opener-Policy','same-origin')
            self.send_header('Cross-Origin-Embedder-Policy','require-corp')
            self.send_header('Cross-Origin-Resource-Policy','cross-origin')
            self.send_header('Cache-Control','no-store')
            super().end_headers()
        def do_GET(self):
            from urllib.parse import urlsplit,parse_qs
            u=urlsplit(self.path)
            if u.path=='/qa-stop':
                if parse_qs(u.query).get('token') != [manifest['qa_token']]:
                    self.send_error(403);return
                data=(out/'qa-stop.json').read_bytes() if (out/'qa-stop.json').exists() else b'{"stop":false}'
                self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data);return
            return super().do_GET()
        def log_message(self,fmt,*args): pass
    url=f'http://127.0.0.1:{port}/index.html?qa_token={manifest["qa_token"]}&qa_route=main_menu'
    write(out/'server.json',{'url':url,'blank':f'http://127.0.0.1:{port}/control.html','port':port})
    print(url,flush=True)
    ThreadingHTTPServer(('127.0.0.1',port),functools.partial(Handler,directory=str(out/'web'))).serve_forever()

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('mode',choices=['prepare','build','serve']);p.add_argument('out',type=Path);p.add_argument('--godot',default=GODOT);p.add_argument('--port',type=int,default=54616)
    p.add_argument('--silent', action='store_true', help='Use Dummy audio in visual-only QA export')
    p.add_argument('--hero-candidate-runtime', action='store_true', help='Prepare isolated canonical authored fixture with actual runtime material; not a shipping gallery export')
    p.add_argument('--hero-shape-package', type=Path, help='Prepare isolated unrigged rear-shape or rear-surface package; imported material retained, animation/front review pending')
    p.add_argument('--hero-motion-package', type=Path, help='Prepare isolated rear motion candidate with actual imported skeleton, waddle/jump/slide clips and accepted material maps')
    p.add_argument('--runner-color-review', action='store_true', help='Opt in to unpromoted DAY lighting/ice/water recipe; requires --hero-motion-package and never supplies shipping gallery evidence')
    a=p.parse_args();out=a.out.resolve()
    if a.mode=='prepare':prepare(out,a.hero_candidate_runtime,a.hero_shape_package,a.hero_motion_package,a.runner_color_review)
    elif a.mode=='build':build(out,a.godot,a.silent)
    else:serve(out,a.port)
