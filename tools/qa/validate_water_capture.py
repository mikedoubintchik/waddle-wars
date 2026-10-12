"""Bind full-scene water evidence to unchanged production and exact QA inputs."""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE_PATH = 'art_src/characters/penguin_motion_v1/candidate.glb'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')

def inputs(root=ROOT):
    paths = [root / 'art_src/characters/penguin_motion_v1' / name
             for name in ['candidate.glb', 'metadata.json']]
    paths += [p for p in (root / 'tools/qa').iterdir() if p.suffix in ['.py', '.gd', '.js']]
    paths += [root / 'tools/release' / name for name in ['web_import_profile.py', 'web_pack_memory.py']]
    return {str(p.relative_to(root)): sha(p) for p in sorted(paths)}

def freeze(task, root=ROOT):
    task, root = Path(task).resolve(), Path(root).resolve()
    task.mkdir(parents=True, exist_ok=True)
    value = {'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'files': inputs(root), 'validator_sha256': sha(__file__), 'human_approval': False}
    value['fingerprint'] = hashlib.sha256(json.dumps(value['files'], sort_keys=True).encode()).hexdigest()
    path = task / 'source-freeze.json'
    assert not path.exists(), 'Freeze already exists; preserve it'
    write(path, value)
    return value

def validate(task, export, previous_task, root=ROOT):
    task, export, previous_task, root = [Path(p).resolve() for p in (task, export, previous_task, root)]
    frozen = json.loads((task / 'source-freeze.json').read_text())
    assert frozen['files'] == inputs(root), 'Frozen QA inputs changed'
    assert frozen['validator_sha256'] == sha(__file__), 'Capture validator changed'
    start = json.loads((task / 'gallery-iteration/source-start.json').read_text())
    spec = importlib.util.spec_from_file_location('gallery', root / 'tools/qa/gallery_iteration.py')
    gallery = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gallery)
    assert gallery.snapshot(root, start['scope'])['files'] == start['files'], 'Production runtime changed'
    manifest = json.loads((export / 'manifest.json').read_text())
    color = manifest['runner_color_review']
    recipe_spec = importlib.util.spec_from_file_location('water_recipe', root / 'tools/qa/runner_color_candidate.py')
    recipe = importlib.util.module_from_spec(recipe_spec)
    recipe_spec.loader.exec_module(recipe)
    assert color['id'] == recipe.RECIPE_ID, 'Recipe version mismatch'
    assert color['recipe_sha256'] == sha(root / 'tools/qa/runner_color_candidate.py')
    assert not color['human_approval'] and not color['gallery_eligible']
    assert sha(export / 'project' / color['binding_path']) == color['binding_sha256']
    for relative, values in color['files'].items():
        assert sha(root / relative) == start['files'][relative] == values['source_sha256']
        assert sha(export / 'project' / relative) == values['prepared_sha256']
    candidate = sha(root / CANDIDATE_PATH)
    assert candidate == frozen['files'][CANDIDATE_PATH], 'Candidate changed after freeze'
    pack = sha(export / 'web/index.pck')
    samples = [('waddle', 0.0, 0), ('jump', 0.5, 2), ('slide', 0.25, 1)]
    rows = []
    signatures = set()
    for device, size, logical, touch in [('desktop', [1920, 1200], [1920, 1200], 0),
                                        ('mobile', [430, 932], [800, 1733], 1)]:
        for action, phase, prior_index in samples:
            path = task / 'originals' / device / (action + '.json')
            data = json.loads(path.read_text())
            qa, motion = data['qa'], data['motion']
            picture = path.with_suffix('.jpg')
            assert list(Image.open(picture).size) == size == qa['canvas_backing']
            assert qa['logical_viewport'] == logical and qa['touch_points'] == touch
            assert qa['status'] == motion['status'] == 'ready' and not qa['error'] and not motion['error']
            assert qa['build']['pack_sha256'] == pack and qa['build']['runner_color_review'] == color
            assert qa['build']['runtime_audio_driver'] == 'Dummy'
            assert qa['build']['qa_auth_isolation'] == 'offline_visual_qa'
            assert motion['bound_source']['glb_sha256'] == candidate
            assert motion['view'] == 'rear' and motion['motion']['action'] == action
            assert not motion['motion']['playing'] and abs(motion['motion']['phase'] - phase) < 1e-5
            assert not motion['active_renderer']['errors'] and motion['active_renderer']['original_hidden']
            assert sha(picture) == data['image']['sha256']
            actual = motion['rendering_environment']
            assert actual['available'] and not actual['errors']
            previous = json.loads((previous_task / 'candidate-originals' / device / 'rear' / action / f'frame-{prior_index:03d}.json').read_text())
            previous_env = previous['motion']['rendering_environment']
            for key in ['sun_energy', 'fill_energy', 'rim_energy', 'ambient_energy', 'ambient_sky_contribution',
                        'tonemap_mode', 'tonemap_exposure', 'tonemap_white', 'glow_enabled', 'fog_density',
                        'sky_top', 'sky_horizon']:
                assert actual[key] == previous_env[key], ('Nonwater environment changed', key)
            assert [x['rgba'] for x in actual['deck_tints']] == [x['rgba'] for x in previous_env['deck_tints']]
            assert abs(actual['water_day_detail_weight'] - 1.0) < 1e-5
            settings = color['settings']
            assert abs(actual['water_day_lateral_reference_metres'] - settings['water_day_lateral_reference_metres']) < 1e-5
            for suffix in ['tile_metres', 'trough_tint', 'body_tint', 'face_tint', 'crest_tint']:
                key = 'water_day_' + suffix
                expected = settings[key]
                if suffix.endswith('tint') and len(expected) == 3:
                    expected = expected + [1.0]
                assert len(actual[key]) == len(expected) and all(abs(a-b) < 1e-5 for a,b in zip(actual[key], expected)), key
            signatures.add(motion['active_renderer']['signature'])
            rows.append({'device': device, 'action': action, 'phase': phase,
                         'image': str(picture.relative_to(task)), 'sha256': sha(picture),
                         'sidecar_sha256': sha(path), 'water_parameters': {k:v for k,v in actual.items() if k.startswith('water_')}})
    assert len(signatures) == 1 and len(rows) == 6
    receipt = {'source_freeze': frozen['fingerprint'], 'candidate_sha256': candidate,
               'pack_sha256': pack, 'capture_count': len(rows), 'errors': [], 'human_approval': False,
               'production_runtime_unchanged': True, 'nonwater_environment_unchanged': True,
               'all_original_rgb_unchanged': True, 'captures': rows,
               'scope': 'Isolated DAY water candidate; full scene actual Chrome captures. Shipping gallery remains separate.'}
    write(task / 'final-capture-validation.json', receipt)
    return receipt

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT, help='Repository containing the candidate and QA source')
    subcommands = parser.add_subparsers(dest='command', required=True)
    freeze_parser = subcommands.add_parser('freeze', help='Record final source inputs before capture')
    freeze_parser.add_argument('--task', type=Path, required=True, help='Evidence directory; existing freeze is never replaced')
    validate_parser = subcommands.add_parser('validate', help='Verify six final captures against the frozen isolated export')
    validate_parser.add_argument('--task', type=Path, required=True)
    validate_parser.add_argument('--export', type=Path, required=True, help='Prepared browser export containing manifest, project and web')
    validate_parser.add_argument('--previous-task', type=Path, required=True, help='Prior color evidence containing candidate-originals')
    args = parser.parse_args()
    if args.command == 'freeze':
        value = freeze(args.task, args.root)
        print(value['fingerprint'])
    else:
        value = validate(args.task, args.export, args.previous_task, args.root)
        print(json.dumps({k: v for k, v in value.items() if k != 'captures'}))


if __name__ == '__main__':
    main()
