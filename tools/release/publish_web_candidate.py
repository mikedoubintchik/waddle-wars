#!/usr/bin/env python3
"""Stage a verified immutable Web build; promote only with browser/gallery receipts."""
from pathlib import Path
import argparse, concurrent.futures, datetime, hashlib, json, mimetypes, subprocess
ROOT=Path(__file__).resolve().parents[2]
WRANGLER=ROOT/'leaderboard/node_modules/.bin/wrangler'
CONFIG=ROOT/'web-host/wrangler.toml'

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def run(args, log):
    p=subprocess.run([str(x) for x in args],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    log.write_bytes(p.stdout)
    if p.returncode:raise RuntimeError(f'Command failed; inspect {log}')

def publish(candidate, mode, browser_receipt=None, gallery=None, expected_root=None):
    manifest=json.loads((candidate/'candidate-artifacts.json').read_text())
    build=candidate/'build'; logs=candidate/'deployment'; logs.mkdir(exist_ok=True)
    assert manifest['normal_audio'] and not manifest['qa_bridge'] and manifest['pack_reassembly_verified']
    for name,row in manifest['files'].items():assert sha(build/name)==row['sha256'],name
    r2=[WRANGLER,'r2','object']
    if mode=='stage':
        def upload(name):
            row=manifest['files'][name]
            mime=({'wasm':'application/wasm','js':'application/javascript','pck':'application/octet-stream'}.get(name.rsplit('.',1)[-1]) or mimetypes.guess_type(name)[0] or 'application/octet-stream')
            run(r2+['put','waddle-wars-web/'+row['key'],'--remote','--config',CONFIG,'--file',build/name,'--content-type',mime],logs/(name+'.upload.log'))
            path=logs/(name+'.download')
            run(['curl','--fail','--silent','--show-error','https://play.waddlewars.io/'+row['key'],'-o',path],logs/(name+'.verify.log'))
            assert sha(path)==row['sha256'],f'Remote mismatch: {name}'
            path.unlink()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(upload,manifest['upload_names']))
        pack=logs/'verified.pck'
        run(['curl','--fail','--silent','--show-error','https://play.waddlewars.io/'+manifest['prefix']+'index.pck','-o',pack],logs/'pack-verify.log')
        assert sha(pack)==manifest['files']['index.pck']['sha256']
        receipt={'build_id':manifest['build_id'],'pack_sha256':sha(pack),'all_assets_verified':True,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
        (logs/'verified.json').write_text(json.dumps(receipt,indent=2)+'\n'); pack.unlink()
        print('Staged and verified: https://play.waddlewars.io/'+manifest['prefix']+'index.html?sound=off')
    else:
        assert browser_receipt and gallery and expected_root,'Promotion requires browser, gallery, and expected root receipts'
        verification=json.loads((logs/'verified.json').read_text())
        assert verification['build_id']==manifest['build_id'] and verification['all_assets_verified']
        assert verification['pack_sha256']==manifest['files']['index.pck']['sha256']
        browser=json.loads(browser_receipt.read_text())
        assert browser['build_id']==manifest['build_id'] and browser['accepted']
        request=json.loads((gallery/'capture-request.json').read_text())
        assert request['end_fingerprint']==manifest['source_fingerprint'],'Candidate and gallery sources differ'
        # Revalidate gallery sources/captures immediately before live promotion.
        run(['/Users/ninja/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3','tools/qa/gallery_iteration.py','delivery-delta','--dir',gallery],logs/'gallery-revalidation.log')
        before=logs/'root-before-switch.html'; after=logs/'root-after-switch.html'
        run(r2+['get','waddle-wars-web/index.html','--remote','--config',CONFIG,'--file',before],logs/'root-precheck.log')
        assert sha(before)==expected_root,'Production changed since precheck; inspect before replacing'
        run(r2+['put','waddle-wars-web/index.html','--remote','--config',CONFIG,'--file',build/'index.html','--content-type','text/html; charset=utf-8'],logs/'root-promote.log')
        run(r2+['get','waddle-wars-web/index.html','--remote','--config',CONFIG,'--file',after],logs/'root-readback.log')
        assert sha(after)==manifest['files']['index.html']['sha256']
        (logs/'promoted.json').write_text(json.dumps({'build_id':manifest['build_id'],'root_sha256':sha(after),'rollback_sha256':sha(before),'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')
        print('Production root switched and verified: '+manifest['build_id'])

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['stage','promote']);p.add_argument('candidate',type=Path);p.add_argument('--browser-receipt',type=Path);p.add_argument('--gallery',type=Path);p.add_argument('--expected-root');a=p.parse_args();publish(a.candidate.resolve(),a.mode,a.browser_receipt,a.gallery,a.expected_root)
