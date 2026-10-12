#!/usr/bin/env python3
"""Add an uncropped water review to a cloned, validated Waddle Wars Studio.

No engine, screenshots, image processing, publication, or art acceptance.
Existing media retain their bytes; APFS clones avoid duplicating the old library.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import html
import importlib.util
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('studio_packager', ROOT / 'tools/qa/build_waddle_studio.py')
studio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(studio)
gallery_spec = importlib.util.spec_from_file_location('gallery_iteration', ROOT / 'tools/qa/gallery_iteration.py')
gallery = importlib.util.module_from_spec(gallery_spec)
gallery_spec.loader.exec_module(gallery)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def resolve_input(value, config_path):
    path = Path(value)
    return (path if path.is_absolute() else config_path.parent / path).resolve()


def sanitize_public_file(path):
    """Use the gallery's sanitizer; raw private evidence stays outside output."""
    if path.suffix not in {'.json', '.html', '.original', '.js', '.txt', '.md'}:
        return False
    text = path.read_text()
    if 'qa_token' not in text:
        return False
    try:
        clean = json.dumps(gallery.safe(json.loads(text)), indent=2, ensure_ascii=False) + '\n'
    except json.JSONDecodeError:
        clean = gallery.safe(text)
    if 'qa_token' in clean:
        raise ValueError(f'Unresolved private token field in public file: {path.name}')
    path.write_text(clean)
    return clean != text


def validate_production_capture(sidecar, frame):
    """Require an observed live-game renderer, never candidate-helper evidence."""
    qa = sidecar.get('qa')
    if not isinstance(qa, dict) or qa.get('status') != 'ready' or qa.get('error') != '' \
            or qa.get('tree_paused') is not True:
        raise ValueError('Production capture must be ready, error-free and tree-paused')
    build = qa.get('build')
    if not isinstance(build, dict):
        raise ValueError('Production capture requires actual build evidence')
    if any(key in build for key in ('hero_candidate', 'hero_motion', 'hero_shape', 'runner_color_review')):
        raise ValueError('Production capture forbids candidate build flags')
    penguin = qa.get('reviewed_penguin')
    if not isinstance(penguin, dict) or penguin.get('active') is not True \
            or penguin.get('visible') is not True \
            or type(penguin.get('procedural_visible_meshes')) is not int \
            or penguin['procedural_visible_meshes'] != 0:
        raise ValueError('Production capture requires one active reviewed penguin without duplicate procedural meshes')
    renderer = penguin.get('renderer')
    if not isinstance(renderer, dict) \
            or renderer.get('model_path') != 'res://assets/art/characters/runner_penguin_v1.glb' \
            or renderer.get('visible') is not True or renderer.get('visible_in_tree') is not True:
        raise ValueError('Production capture requires actual visible runtime renderer evidence')
    action = frame.get('action')
    if action not in ('waddle', 'jump', 'slide') or renderer.get('clip') != action \
            or renderer.get('action') != action:
        raise ValueError('Production capture actual clip/action mismatch')
    for key in ('clip_time', 'clip_length', 'phase'):
        value = renderer.get(key)
        if type(value) not in (int, float) or not math.isfinite(value):
            raise ValueError('Production capture requires finite actual clip timing')
    if renderer['clip_length'] <= 0 or not 0 <= renderer['clip_time'] <= renderer['clip_length'] + 0.001 \
            or not 0 <= renderer['phase'] <= 1:
        raise ValueError('Production capture actual clip timing outside bounds')
    surfaces = renderer.get('surfaces')
    if not isinstance(surfaces, list) or len(surfaces) != 1:
        raise ValueError('Production capture requires actual single imported surface evidence')
    surface = surfaces[0]
    if not isinstance(surface, dict) or surface.get('visible') is not True \
            or surface.get('imported_material') is not True or surface.get('override') is not False \
            or surface.get('overlay') is not False or surface.get('material_class') != 'StandardMaterial3D':
        raise ValueError('Production capture forbids overridden or missing imported material evidence')
    # Gameplay determines the captured instant. Preserve observed phase instead
    # of enforcing a hand-seeked candidate pose or retaining a stale config value.
    frame['phase'] = renderer['phase']


def validate_config(config_path):
    config_path = Path(config_path).resolve()
    config = read(config_path)
    if config.get('draft') is True:
        raise ValueError('Draft review cannot be packaged before final visual inspection')
    if config.get('human_approval') is not False:
        raise ValueError('Human approval must remain false')
    for field in ('title', 'summary', 'verdict', 'comparison_limits', 'review_date'):
        if not isinstance(config.get(field), str) or not config[field].strip():
            raise ValueError(f'Missing review field: {field}')
    if config.get('visual_status') not in ('ready_for_review', 'residual_gap'):
        raise ValueError('Explicit visual status required')
    contract = config.get('capture_contract', 'motion_candidate')
    if contract not in ('motion_candidate', 'production_runner'):
        raise ValueError('Unknown capture contract')
    frames = config.get('frames', [])
    if not frames:
        raise ValueError('Actual final frames required')
    ids = set()
    for frame in frames:
        if not re.fullmatch(r'[a-z0-9][a-z0-9_-]*', frame.get('id', '')) or frame['id'] in ids:
            raise ValueError('Unique safe frame IDs required')
        ids.add(frame['id'])
        if frame.get('device') not in ('desktop', 'mobile'):
            raise ValueError('Frame device must be desktop or mobile')
        if not isinstance(frame.get('label'), str) or not frame['label'].strip():
            raise ValueError('Frame label required')
        for key in ('current', 'sidecar', 'previous', 'reference'):
            path = resolve_input(frame[key], config_path)
            if not path.is_file():
                raise ValueError(f'Missing {key}: {path}')
            frame[key] = str(path)
        sidecar = read(frame['sidecar'])
        if sidecar.get('image', {}).get('sha256') != sha(frame['current']):
            raise ValueError('Current image hash does not match capture sidecar')
        if contract == 'production_runner':
            validate_production_capture(sidecar, frame)
        else:
            motion = sidecar.get('motion', {})
            state = motion.get('motion', {})
            if motion.get('status') != 'ready' or state.get('playing') is not False:
                raise ValueError('Current capture must be ready and paused')
            if 'action' in frame and state.get('action') != frame['action']:
                raise ValueError('Current capture action mismatch')
            if 'phase' in frame and abs(float(state.get('phase', -1)) - float(frame['phase'])) > 0.001:
                raise ValueError('Current capture phase mismatch')
        # The capture verifier, not this presentation builder, verifies source/PCK,
        # viewport, shader parameters and reference framing before final delivery.
    if {frame['device'] for frame in frames} != {'desktop', 'mobile'}:
        raise ValueError('Both desktop and phone full-scene views required')
    return config


def clone_site(base, output):
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be empty; preserve previous evidence')
    if output == base or output.is_relative_to(base) or base.is_relative_to(output):
        raise ValueError('Output must not overlap the previous Studio')
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.rmdir()
    if sys.platform == 'darwin':
        # cp -c uses copy-on-write clones. A failure stops here, never falls back
        # to a large physical copy on the disk-constrained review workstation.
        subprocess.run(['cp', '-cR', str(base), str(output)], check=True)
    else:
        shutil.copytree(base, output)


def add_review(base, output, config_path):
    base, output, config_path = map(lambda p: Path(p).resolve(), (base, output, config_path))
    config = validate_config(config_path)
    parent_validation = studio.validate_site(base)
    before = {str(p.relative_to(base)): sha(p) for p in base.rglob('*') if p.is_file()}
    manifest = read(base / 'manifest.json')
    parent_manifest = copy.deepcopy(manifest)
    production = config.get('capture_contract') == 'production_runner'
    clone_site(base, output)
    # Historical packages also contained raw sidecars. Scrub only public copies;
    # the old package and raw task evidence remain unchanged outside this site.
    inherited_sanitized = set()
    for path in output.rglob('*'):
        if path.is_file() and sanitize_public_file(path):
            inherited_sanitized.add(str(path.relative_to(output)))
    parent_proof = output / 'provenance/water-parent'
    if parent_proof.exists():
        parent_proof = output / ('provenance/water-parent-' + before['provenance/package-inventory.json'][:12])
    parent_proof.mkdir(parents=True)
    for name in ('package-inventory.json', 'build-receipt.json'):
        studio.copy_bytes(base / 'provenance' / name, parent_proof / name)
    studio.copy_bytes(base / 'manifest.json', parent_proof / 'manifest.json')
    records = read(base / 'provenance/package-inventory.json')['files']
    for rel, digest in before.items():
        if rel in ('provenance/package-inventory.json', 'provenance/build-receipt.json'):
            continue
        if rel not in records:
            records[rel] = {'source': str(base / rel), 'source_sha256': digest,
                            'output_sha256': digest, 'byte_identical': True,
                            'bytes': (base / rel).stat().st_size}
    available = {}
    for rel, digest in before.items():
        if Path(rel).suffix.lower() in studio.MEDIA:
            available.setdefault(digest, rel)
    comparisons = []
    added_media = []
    public_sidecars = []
    for frame in config['frames']:
        entry = {k: v for k, v in frame.items() if k not in ('current', 'sidecar', 'previous', 'reference')}
        for key in ('current', 'sidecar', 'previous', 'reference'):
            source = Path(frame[key]); digest = sha(source)
            if key == 'sidecar':
                rel = f'water/evidence/{frame["id"]}.json'
                destination = output / rel
                write(destination, gallery.safe(read(source)))
                public_digest = sha(destination)
                binding = {'raw_sha256': digest, 'sanitized_sha256': public_digest,
                           'sanitized': True, 'raw_retained_outside_public_site': True}
                records[rel] = {'source': str(source), 'source_sha256': digest,
                                'output_sha256': public_digest, 'byte_identical': digest == public_digest,
                                'bytes': destination.stat().st_size, **binding}
                entry[key] = {'url': '../' + rel, 'sha256': public_digest, **binding}
                public_sidecars.append({'path': rel, **binding})
                continue
            existing = available.get(digest) if key != 'sidecar' else None
            if existing:
                rel = existing
            else:
                # Repeated additive reviews must never overwrite an earlier
                # frame with the same device/action ID but different pixels.
                rel = f'water/originals/{frame["id"]}-{key}-{digest[:12]}{source.suffix.lower()}'
                destination = output / rel
                if destination.exists() and sha(destination) != digest:
                    raise ValueError('New evidence path collides with preserved original media')
                studio.copy_bytes(source, destination)
                if sha(destination) != digest:
                    raise ValueError('Original evidence bytes changed')
                if source.suffix.lower() in studio.MEDIA:
                    available[digest] = rel
                    added_media.append(rel)
                records[rel] = {'source': str(source), 'source_sha256': digest,
                                'output_sha256': digest, 'byte_identical': True,
                                'bytes': source.stat().st_size}
            entry[key] = {'url': '../' + rel, 'sha256': digest}
        comparisons.append(entry)
    review = {k: v for k, v in config.items() if k != 'frames'}
    review['frames'] = comparisons
    write(output / 'water/comparison-data.json', review)
    (output / 'water/index.html').write_text(render_review(review))
    manifest['studio_collections'] = [
        {'id': 'water', 'title': config['title'] if production else 'Scene & water', 'path': 'water/index.html',
         'note': f'{config["review_date"]} · {"Normal gameplay" if production else "Full scene comparison"} · Human review pending'},
        *[c for c in manifest.get('studio_collections', []) if c['id'] != 'water']]
    manifest['studio_note'] = (f'{config["title"] if production else "Scene & water"}: {config["review_date"]} '
                               f'{"normal gameplay" if production else "candidate"} comparison. Penguin motion and reference history remain available. '
                               f'The {len(manifest["pages"])} game pages preserve their original dated evidence and review status. Human review pending.')
    manifest['water_review'] = {'human_approval': False, 'capture_count': len(comparisons),
                                'capture_contract': config.get('capture_contract', 'motion_candidate'),
                                'visual_status': config['visual_status'], 'verdict': config['verdict']}
    write(output / 'manifest.json', manifest)
    index = (base / 'index.html').read_text()
    index, substitutions = re.subn(r'(<script\b[^>]*id=["\']catalogue-data["\'][^>]*>).*?(</script>)',
                                  lambda m: m[1] + json.dumps(manifest, ensure_ascii=False).replace('</', '<\\/') + m[2],
                                  index, flags=re.S)
    if substitutions != 1:
        raise ValueError('Cannot locate embedded Studio catalogue')
    (output / 'index.html').write_text(index.replace('aria-label="Character studies"', 'aria-label="Scene and character studies"'))
    script = output / 'gallery.js'
    script.write_text(script.read_text().replace('Character studies', 'Scene & character studies'))
    # Earlier color caveats remain true for those preserved captures. Put their
    # revision/date relationship in view instead of quietly erasing history.
    for rel in ('penguin/studio/index.html', 'penguin/review/index.html'):
        page = output / rel
        if page.is_file():
            text = page.read_text()
            banner = ('<aside style="padding:12px 20px;background:#183f53;color:#e4f8ff;font:14px/1.5 system-ui">'
                      f'{"Previous candidate review" if production else "Previous color revision"} · Penguin model, motions and references remain available here. '
                      '<a href="../../index.html#collection=water" target="_top" style="color:#b9f5ff">'
                      f'Open the new {"gameplay integration" if production else "full-scene water"} comparison</a>.</aside>')
            text, count = re.subn(r'(<body\b[^>]*>)', lambda m: m[1] + banner, text, count=1)
            if count == 0:
                text, count = re.subn(r'(<main\b[^>]*>)', lambda m: m[1] + banner, text, count=1)
            if count != 1:
                raise ValueError('Cannot annotate previous collection')
            page.write_text(text)
    for field in ('pages', 'entries', 'accepted_views', 'pending_views', 'pending_current_views', 'affected_routes', 'fresh_views'):
        if manifest.get(field) != parent_manifest.get(field):
            raise ValueError(f'Historical gallery evidence changed: {field}')
    for rel, old_digest in before.items():
        if sha(base / rel) != old_digest:
            raise ValueError('Parent Studio changed during additive build')
    exclusions = {'provenance/package-inventory.json', 'provenance/build-receipt.json'}
    for path in output.rglob('*'):
        if not path.is_file():
            continue
        rel = str(path.relative_to(output))
        if rel in exclusions:
            continue
        digest = sha(path)
        if rel in before and digest != before[rel]:
            if rel in inherited_sanitized:
                records[rel] = {'source': str(base / rel), 'source_sha256': before[rel],
                                'output_sha256': digest, 'byte_identical': False,
                                'bytes': path.stat().st_size, 'sanitized': True,
                                'raw_sha256': before[rel], 'sanitized_sha256': digest,
                                'raw_retained_outside_public_site': True}
                continue
            preserved = parent_proof / 'source-documents' / (rel + '.original')
            studio.copy_bytes(base / rel, preserved)
            # This new record binds to the exact immediate parent revision.
            records[rel] = {'source': str(base / rel), 'source_sha256': before[rel],
                            'output_sha256': digest, 'byte_identical': False,
                            'bytes': path.stat().st_size,
                            'preserved_original': str(preserved.relative_to(output))}
        elif rel not in records:
            records[rel] = {'source': str(config_path), 'source_sha256': sha(config_path),
                            'output_sha256': digest, 'byte_identical': False,
                            'bytes': path.stat().st_size, 'generated_presentation': True}
    # Some old HTML records referenced their verbatim source with a private URL.
    # Keep only that source's sanitized public derivative and its two hashes.
    for record in records.values():
        preserved = record.get('preserved_original')
        if preserved in inherited_sanitized:
            record.pop('preserved_original')
            record['sanitized_preserved_original'] = preserved
            record['raw_original_sha256'] = before[preserved]
            record['sanitized_original_sha256'] = sha(output / preserved)
            record['raw_retained_outside_public_site'] = True
    inventory = {'schema': 1, 'brand': 'Waddle Wars Studio', 'source_files_unchanged': True,
                 'parent_inventory_sha256': before['provenance/package-inventory.json'], 'files': records}
    write(output / 'provenance/package-inventory.json', inventory)
    validation = studio.validate_site(output)
    receipt = {'builder_sha256': sha(__file__), 'config_sha256': sha(config_path),
               'base_site': str(base), 'output_site': str(output),
               'parent_inventory_sha256': before['provenance/package-inventory.json'],
               'inventory_sha256': sha(output / 'provenance/package-inventory.json'),
               'packaged_manifest_sha256': sha(output / 'manifest.json'),
               'parent_files_unchanged': True, 'media_byte_identical': True,
               'public_sidecars': public_sidecars,
               'inherited_public_files_sanitized': len(inherited_sanitized),
               'private_raw_sidecars_packaged': False,
               'new_media_files': added_media, 'full_scene_capture_count': len(comparisons),
               'page_count': len(manifest['pages']), 'accepted_views': manifest.get('accepted_views'),
               'pending_views': manifest.get('pending_current_views', manifest.get('pending_views')), 'new_shipping_game_page_captures': 0,
               'human_approval': False, 'production_promotion': False,
               'capture_contract': config.get('capture_contract', 'motion_candidate'),
               'production_gameplay_captures': production,
               'visual_status': config['visual_status'], 'verdict': config['verdict'],
               'parent_validation': parent_validation, 'validation': validation}
    write(output / 'provenance/build-receipt.json', receipt)
    return receipt


def render_review(review):
    production = review.get('capture_contract') == 'production_runner'
    encoded = json.dumps(review, ensure_ascii=False).replace('</', '<\\/')
    return (PAGE.replace('__TITLE__', html.escape(review['title']))
            .replace('__REVIEW_DATE__', html.escape(review['review_date']))
            .replace('__CURRENT_HEADING__', 'CURRENT GAME · INTEGRATED GAMEPLAY' if production else 'CURRENT GAME · WATER UPDATE')
            .replace('__PREVIOUS_HEADING__', 'PREVIOUS CANDIDATE · WATER REVIEW' if production else 'PREVIOUS GAME · COLOR REVISION')
            .replace('__PREVIOUS_DESCRIPTION__', 'Previously reviewed candidate, before normal gameplay integration.' if production else 'Previous candidate, before this water change.')
            .replace('__DATA__', encoded))


PAGE = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>__TITLE__ · Waddle Wars Studio</title><style>
:root{color-scheme:dark;font:16px/1.5 system-ui,sans-serif;background:#0b1b27;color:#e7f4fc}*{box-sizing:border-box}body{margin:0}main{max-width:2000px;padding:24px;margin:auto}a{color:#aeeaff;text-underline-offset:3px}header{max-width:1080px}h1{font-size:clamp(29px,4vw,44px);line-height:1.1;letter-spacing:-.035em;margin:14px 0}p{color:#b6cfde;margin:10px 0}.eyebrow{font-size:12px;text-transform:uppercase;letter-spacing:.1em;color:#94cdd9}.controls{display:flex;gap:12px;flex-wrap:wrap;align-items:end;margin:22px 0}label{display:grid;gap:4px;font-size:12px;color:#b6cfde}select,button{font:inherit;color:#e7f4fc;background:#183447;border:1px solid #4a7188;border-radius:7px;padding:9px 12px;min-height:44px}button{cursor:pointer}button[aria-pressed=true]{color:#102939;background:#c5f3ee}select{max-width:100%}.verdict{border-left:3px solid #65d4d6;padding:10px 16px;background:#123145}.comparison{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;align-items:start}.comparison.two{grid-template-columns:repeat(2,minmax(0,1fr))}.comparison.stacked{grid-template-columns:1fr;max-width:1050px;margin:auto}figure{margin:0;min-width:0}figcaption{font-size:13px;font-weight:750;margin-bottom:8px}figure a{display:block}img{width:100%;height:auto;display:block;background:#07131e;border:1px solid #446276;border-radius:6px}figure p{font-size:12px;margin:8px 0 0}.raw{font-size:12px;padding:5px 0}.limits{margin-top:24px;max-width:1200px;font-size:13px}details{border-top:1px solid #345063;padding-top:12px;margin-top:16px}summary{cursor:pointer}.links{display:flex;flex-wrap:wrap;gap:16px;margin-top:12px}.evidence{font-size:12px;overflow-wrap:anywhere}.phone .comparison:not(.stacked){max-width:1250px;margin:auto}[hidden]{display:none!important}:focus-visible{outline:3px solid #ffc66c;outline-offset:3px}@media(max-width:900px){.comparison,.comparison.two{grid-template-columns:1fr}.controls{align-items:stretch}main{padding:18px}.controls label{width:100%}}
</style></head><body><main><header><div class="eyebrow">Waddle Wars Studio · __REVIEW_DATE__ · Human review pending</div><h1>__TITLE__</h1><p id="summary"></p><p id="verdict" class="verdict"></p></header>
<div class="controls"><label>Screen<select id="device" aria-label="Screen"><option value="desktop">Desktop</option><option value="mobile">Phone</option></select></label><label>Scene<select id="scene" aria-label="Scene"></select></label><button id="previous-toggle" aria-pressed="false">Show previous version</button><button id="stack" aria-pressed="false">Stack images</button></div>
<section class="comparison two" id="comparison" aria-label="Uncropped full scene comparison"><figure><figcaption>REFERENCE · SCENE DESIGN</figcaption><a id="reference-open" target="_blank" rel="noopener"><img id="reference" alt="Full scene reference"></a><p>Original scene design. Color and water detail target.</p><a class="raw" id="reference-download" download>Original reference</a></figure><figure id="previous-figure" hidden><figcaption>__PREVIOUS_HEADING__</figcaption><a id="previous-open" target="_blank" rel="noopener"><img id="previous" alt="Previous full in-game scene"></a><p>__PREVIOUS_DESCRIPTION__</p><a class="raw" id="previous-download" download>Original previous frame</a></figure><figure><figcaption>__CURRENT_HEADING__</figcaption><a id="current-open" target="_blank" rel="noopener"><img id="current" alt="Current full in-game scene"></a><p>Actual game capture. Complete frame, unchanged pixels.</p><a class="raw" id="current-download" download>Original current frame</a></figure></section>
<div class="limits"><p id="limits"></p><p>Images fit their columns with their original proportions. No cropping, recoloring, sharpening, or alignment edits.</p><details><summary>Original images and capture evidence</summary><p id="evidence" class="evidence"></p><div class="links"><a id="sidecar" target="_blank" rel="noopener">Current capture evidence</a><a href="comparison-data.json" target="_blank" rel="noopener">Comparison inventory</a></div></details><div class="links"><a href="../index.html#collection=penguin" target="_top">Penguin motions & reference library</a><a href="../index.html" target="_top">All game pages</a></div></div></main>
<script id="review-data" type="application/json">__DATA__</script><script>
'use strict';const data=JSON.parse(document.getElementById('review-data').textContent),el=id=>document.getElementById(id);let showPrevious=false,stacked=false;el('summary').textContent=data.summary;el('verdict').textContent=data.verdict;el('limits').textContent=data.comparison_limits;
function fillScenes(){const old=el('scene').value;el('scene').replaceChildren();for(const frame of data.frames.filter(f=>f.device===el('device').value)){const o=document.createElement('option');o.value=frame.id;o.textContent=frame.label;el('scene').append(o)}if([...el('scene').options].some(o=>o.value===old))el('scene').value=old;render()}
function render(){const frame=data.frames.find(f=>f.id===el('scene').value);for(const role of ['reference','previous','current']){el(role).src=frame[role].url;el(role).alt=`${el('device').selectedOptions[0].textContent} ${frame.label} · ${role} full scene`;el(role+'-open').href=frame[role].url;el(role+'-download').href=frame[role].url}el('sidecar').href=frame.sidecar.url;el('evidence').textContent=`${frame.label} · Current image SHA-256: ${frame.current.sha256}. Human approval pending.`;document.body.classList.toggle('phone',frame.device==='mobile');el('previous-figure').hidden=!showPrevious;el('comparison').classList.toggle('two',!showPrevious);el('comparison').classList.toggle('stacked',stacked);el('previous-toggle').setAttribute('aria-pressed',String(showPrevious));el('previous-toggle').textContent=showPrevious?'Hide previous version':'Show previous version';el('stack').setAttribute('aria-pressed',String(stacked))}
el('device').addEventListener('change',fillScenes);el('scene').addEventListener('change',render);el('previous-toggle').addEventListener('click',()=>{showPrevious=!showPrevious;render()});el('stack').addEventListener('click',()=>{stacked=!stacked;render()});fillScenes();
</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-site', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(add_review(args.base_site, args.output, args.config), indent=2))


if __name__ == '__main__':
    main()
