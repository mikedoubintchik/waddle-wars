"""Actual isolated filesystem preparation; no engine, browser or image changes."""
import contextlib
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


color = load('runner_color_candidate', ROOT/'tools/qa/runner_color_candidate.py')
export_tests = load('chrome_export_fixtures', ROOT/'tests/test_chrome_reference_export.py')
qa = export_tests.qa


class ColorRecipeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.source = self.home/'source'
        self.project = self.home/'prepared'
        for base in (self.source, self.project):
            base.mkdir()
            for relative in color.SOURCE_SHA256:
                target = base/relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT/'tests/fixtures/runner_day_before_water_v6'/relative, target)
        (self.project/'_qa_local').mkdir()
        (self.project/'project.godot').write_text(
            '[application]\nconfig/use_custom_user_dir=true\n'
            'config/custom_user_dir_name="waddle-chrome-reference-fixture"\n'
            '[autoload]\nChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"\n')
        texture = self.project/'assets/foot.png'
        texture.parent.mkdir(exist_ok=True)
        texture.write_bytes(b'exact protected foot texture')

    def test_only_declared_copy_changes_and_receipt_binds_actual_bytes(self):
        before = qa.inventory(self.source)
        copied = qa.inventory(self.project)
        result = color.install(self.source, self.project)
        self.assertEqual(qa.inventory(self.source), before)
        after = qa.inventory(self.project)
        self.assertEqual({p for p in copied if copied[p] != after[p]}, set(color.SOURCE_SHA256))
        self.assertEqual(after['assets/foot.png'], copied['assets/foot.png'])
        self.assertEqual(result['settings']['sun_energy'], .25)
        self.assertEqual(result['id'], 'runner-day-water-v6')
        self.assertEqual(result['settings']['water_haze'], [110.0, 600.0])
        self.assertEqual(result['settings']['water_crest_tint'], [.08, .75, 1.0])
        self.assertEqual(result['settings']['water_detail'], color.WATER_DETAIL)
        self.assertEqual(result['settings']['water_texture_samples_max'], 2)
        self.assertFalse(result['gallery_eligible'])
        self.assertFalse(result['human_approval'])
        for relative, hashes in result['files'].items():
            self.assertEqual(hashes['source_sha256'], before[relative])
            self.assertEqual(hashes['prepared_sha256'], after[relative])
            self.assertEqual(hashes['replacements'], len(color.replacements()[relative]))
        self.assertEqual(result['binding_sha256'], after[color.BINDING_PATH])
        receipt = json.loads((self.project/color.BINDING_PATH).read_text())
        self.assertEqual(receipt, {k:v for k,v in result.items() if k != 'binding_sha256'})
        # DAY introduces the only explicit water value. All other environments
        # still use the original mapping and the existing lerp transition.
        game = (self.project/'scripts/runner/runner_game.gd').read_text()
        day = game.split('match biome:\n')[-1].split('RunnerTrack.Biome.DUSK:')[0]
        self.assertIn('"water_tint": Color(0.008, 0.44, 0.75)', day)
        self.assertIn('"water_haze": Vector2(110.0, 600.0)', day)
        self.assertIn('"water_crest_tint": Vector3(0.08, 0.75, 1.0)', day)
        self.assertIn('"water_detail_weight": 1.0', day)
        self.assertEqual(game.count('"water_crest_tint":'), 1)
        self.assertEqual(game.count('"water_detail_weight":'), 1)
        sea = (self.project/'scripts/runner/runner_painted_sea.gd').read_text()
        self.assertIn('environment.get("water_tint", reference_water_tint(horizon, bottom))', sea)
        self.assertIn('_water_tint.lerp(water, amount)', sea)
        self.assertIn('environment.get("water_haze", Vector2(110.0, 600.0))', sea)
        self.assertIn('_haze_distances.lerp(haze, amount)', sea)
        self.assertIn('environment.get("water_crest_tint", Vector3(0.70, 0.91, 1.0))', sea)
        self.assertIn('_crest_tint.lerp(crest, amount)', sea)
        self.assertIn('set_shader_parameter("crest_tint", _crest_tint)', sea)
        self.assertIn('environment.get("water_detail_weight", 0.0)', sea)
        self.assertIn('lerpf(_detail_weight, detail, amount)', sea)
        self.assertIn('set_shader_parameter("day_detail_weight", _detail_weight)', sea)
        for name, value in color.WATER_DETAIL.items():
            if name == 'day_detail_weight':
                continue
            if isinstance(value, (int, float)):
                self.assertIn(f'set_shader_parameter("{name}", {value})', sea)
                continue
            constructor = 'Vector2' if len(value) == 2 else 'Color'
            arguments = ', '.join(str(component) for component in value)
            self.assertIn(f'set_shader_parameter("{name}", {constructor}({arguments}))', sea)
        shader = (self.project/'assets/art/runner/materials/runner_painted_sea_v1.gdshader').read_text()
        self.assertIn('uniform vec2 haze_distances = vec2(110.0, 600.0);', shader)
        self.assertIn('smoothstep(haze_distances.x, haze_distances.y, distance_to_camera)', shader)
        # A raw vec3 retains the original numeric color-space behavior for
        # other biomes. DAY's separate palette uses source_color correctly.
        self.assertIn('uniform vec3 crest_tint = vec3(0.70, 0.91, 1.0);', shader)
        self.assertNotIn('uniform vec3 crest_tint : source_color', shader)
        self.assertIn('mix(near_water, crest_tint, crest * 0.48)', shader)
        self.assertEqual(shader.count('texture('), 2)

    def test_day_detail_keeps_legacy_surface_and_uses_filtered_scalar_palette(self):
        color.install(self.source, self.project)
        relative = 'assets/art/runner/materials/runner_painted_sea_v1.gdshader'
        original = (self.source/relative).read_text()
        shader = (self.project/relative).read_text()
        # The legacy sample and surface equations stay byte-exact. Zero DAY
        # weight skips the extra sample and restores the original final mix.
        legacy = original.split('void fragment() {', 1)[1].split('\tALBEDO = ', 1)[0]
        legacy = legacy.replace('smoothstep(110.0, 600.0, distance_to_camera)',
                                'smoothstep(haze_distances.x, haze_distances.y, distance_to_camera)')
        legacy = legacy.replace('vec3(0.70, 0.91, 1.0), crest * 0.48', 'crest_tint, crest * 0.48')
        self.assertIn(legacy, shader)
        self.assertIn('uniform float day_detail_weight = 0.0;', shader)
        self.assertIn('if (painted_enabled && detail_weight > 0.0)', shader)
        self.assertIn('float day_haze = haze * haze;', shader)
        self.assertIn('day_haze *= day_haze;', shader)
        self.assertIn('mix(haze, day_haze, detail_weight)', shader)
        self.assertIn('filter_linear_mipmap_anisotropic, repeat_disable', shader)
        for forbidden in ('textureLod(', 'textureGrad(', 'SCREEN_TEXTURE', 'DEPTH_TEXTURE', 'TIME', 'EMISSION'):
            self.assertNotIn(forbidden, shader)
        self.assertIn('if (OUTPUT_IS_SRGB)', shader)
        self.assertIn('paint_srgb_scalar(texture(painted_albedo, detail_uv).g)', shader)
        self.assertIn('VERTEX.x / view_depth * day_lateral_reference_metres / day_tile_metres.x', shader)
        self.assertIn('world_pos.z / day_tile_metres.y', shader)
        for name in ('day_trough_tint', 'day_body_tint', 'day_face_tint', 'day_crest_tint'):
            self.assertIn(f'uniform vec4 {name} : source_color', shader)
        self.assertIn('smoothstep(0.60, 0.73, signal)', shader)

    def test_calibrated_palette_stays_positive_through_aces(self):
        # Godot a13da4feb scene.glsl / tonemap_inc.glsl: negative post-ACES
        # values reach fractional pow(), whose result is undefined. Test the
        # continuous authored palette, not just its three safe endpoints.
        rrt = ((.59719, .35458, .04823), (.076, .90834, .01566), (.0284, .13383, .83777))
        odt = ((1.60475, -.53108, -.07367), (-.10208, 1.10813, -.00605), (-.00327, -.07276, 1.07602))
        def curve(value):
            return (value * (value + .0245786) - .000090537) / (value * (.983729 * value + .432951) + .238081)
        white = curve(6.0 * 1.8)
        def tonemap(rgb):
            linear = [v * (v * (v * .305306011 + .682171111) + .012522878) * .86 for v in rgb]
            film = [curve(sum(a * b for a, b in zip(row, linear)) * 1.8) for row in rrt]
            return [sum(a * b for a, b in zip(row, film)) / white for row in odt]
        def mix(a, b, amount):
            return [x * (1 - amount) + y * amount for x, y in zip(a, b)]
        def smooth(low, high, value):
            amount = max(0.0, min(1.0, (value - low) / (high - low)))
            return amount * amount * (3 - 2 * amount)
        palette = [color.WATER_DETAIL[f'day_{part}_tint'][:3] for part in ('trough', 'body', 'face', 'crest')]
        for value in (i / 4096 for i in range(4097)):
            rgb = mix(palette[0], palette[1], smooth(.35, .43, value))
            rgb = mix(rgb, palette[2], smooth(.43, .58, value))
            rgb = mix(rgb, palette[3], smooth(.60, .73, value))
            self.assertGreater(min(tonemap(rgb)), 0.0, f'Undefined gamma input at paint scalar {value}')
        for rgb, target in zip(palette, ((8, 85, 175), (8, 105, 195), (8, 125, 215))):
            actual = [max(1.055 * math.pow(v, 1 / 2.4) - .055, 0) * 255 for v in tonemap(rgb)]
            for a, b in zip(actual, target):
                self.assertAlmostEqual(a, b, places=5)

    def test_only_day_environment_gains_water_detail(self):
        color.install(self.source, self.project)
        relative = 'scripts/runner/runner_game.gd'
        original = (self.source/relative).read_text()
        prepared = (self.project/relative).read_text()
        marker = 'RunnerTrack.Biome.DUSK:'
        # Every later environment, including transition inputs, stays exact.
        self.assertEqual(original.split(marker, 1)[1], prepared.split(marker, 1)[1])

    def test_source_or_copy_divergence_refused_before_any_write(self):
        last = next(reversed(color.SOURCE_SHA256))
        for base in (self.source, self.project):
            with self.subTest(base=base.name):
                path = base/last
                original = path.read_bytes()
                path.write_bytes(original+b'\n# unexpected edit\n')
                before = qa.inventory(self.project)
                with self.assertRaisesRegex(ValueError, 'source changed|source differs'):
                    color.install(self.source, self.project)
                self.assertEqual(qa.inventory(self.project), before)
                path.write_bytes(original)

    def test_reinstall_and_same_root_refused(self):
        with self.assertRaisesRegex(ValueError, 'separate isolated'):
            color.install(self.source, self.source)
        color.install(self.source, self.project)
        before = qa.inventory(self.project)
        with self.assertRaisesRegex(ValueError, 'already installed'):
            color.install(self.source, self.project)
        self.assertEqual(qa.inventory(self.project), before)

    def test_shared_source_inode_and_missing_identity_refused(self):
        relative = next(iter(color.SOURCE_SHA256))
        path = self.project/relative
        path.unlink()
        path.hardlink_to(self.source/relative)
        before = qa.inventory(self.project)
        with self.assertRaisesRegex(ValueError, 'Unsafe color destination'):
            color.install(self.source, self.project)
        self.assertEqual(qa.inventory(self.project), before)
        path.unlink()
        shutil.copy2(self.source/relative, path)
        (self.project/'project.godot').write_text('[application]\nconfig/name="Shipping"\n')
        before = qa.inventory(self.project)
        with self.assertRaisesRegex(ValueError, 'isolated Chrome QA identity'):
            color.install(self.source, self.project)
        self.assertEqual(qa.inventory(self.project), before)

    def test_missing_or_duplicate_replacement_refused(self):
        relative = 'data/art/course_profiles/runner_day.tres'
        for text in ('sun_energy = 9\n', 'sun_energy = 1.24\nsun_energy = 1.24\n'):
            with self.assertRaisesRegex(ValueError, 'exactly one replacement'):
                color.patched(relative, text.encode())

    def prepare_fixture(self):
        for directory in ('assets','scenes','tools/qa'):
            (self.source/directory).mkdir(parents=True, exist_ok=True)
        for name in ('project.godot','export_presets.cfg'):
            shutil.copy2(ROOT/name, self.source/name)
        for name in ('chrome_reference_bridge.gd','chrome_reference_bridge.js','runner_color_candidate.py'):
            shutil.copy2(ROOT/'tools/qa'/name, self.source/'tools/qa'/name)
        # The independently tested motion installer is outside this recipe's
        # scope. This double only records ordering and supplies its controls.
        (self.source/'tools/qa/motion_candidate_export.py').write_text(
            'def validate_package(package): return {}\n'
            'def install(source, project, package):\n'
            '    assert (project/"_qa_local/runner_color_binding.json").exists()\n'
            '    return {"gallery_eligible":False}\n'
            'def review_controls(): return "<section>Motion candidate</section>"\n')
        export_tests.add_import_profile_fixture(self.source)

    def test_export_default_off_and_opt_in_isolated_source_receipt(self):
        self.prepare_fixture()
        before = qa.inventory(self.source)
        with patch.object(qa, 'ROOT', self.source), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, 'requires --hero-motion-package'):
                qa.prepare(self.home/'forbidden', runner_color_review=True)
            self.assertFalse((self.home/'forbidden').exists())
            ordinary = self.home/'ordinary'
            qa.prepare(ordinary)
            candidate = self.home/'candidate'
            qa.prepare(candidate, hero_motion_package=self.home/'model', runner_color_review=True)
        regular = json.loads((ordinary/'manifest.json').read_text())
        changed = json.loads((candidate/'manifest.json').read_text())
        self.assertNotIn('runner_color_review', regular)
        self.assertFalse((ordinary/'project'/color.BINDING_PATH).exists())
        for relative in color.SOURCE_SHA256:
            self.assertEqual((ordinary/'project'/relative).read_bytes(), (self.source/relative).read_bytes())
            self.assertEqual(changed['source_sha256'][relative], before[relative])
            self.assertEqual(changed['export_input_sha256'][relative], changed['runner_color_review']['files'][relative]['prepared_sha256'])
        self.assertEqual(qa.inventory(candidate/'project'), changed['export_input_sha256'])
        self.assertEqual({p:h for p,h in qa.inventory(self.source).items() if '__pycache__' not in Path(p).parts}, before)

    def test_build_publishes_exact_color_receipt_and_rejects_mismatch_before_engine(self):
        out = self.home/'build'
        out.mkdir()
        project = out/'project'
        self.project.rename(project)
        color_receipt = color.install(self.source, project)
        web = out/'web'
        web.mkdir()
        head = '<script>/* production head */</script>'
        (out/'production-head.html').write_text(head)
        standard = head+'\n<script>const GODOT_CONFIG = {}; const engine = new Engine(GODOT_CONFIG);</script></body>'
        for relative in ('qa_motion/candidate.glb.import','qa_motion/candidate_binding.json',
                         '_qa_local/motion_candidate_browser.gd'):
            path = project/relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('independently tested motion fixture')
        (out/'motion-review-controls.html').write_text('<section>Motion</section>')
        motion = {'binding': {'importer_sha256':qa.sha(project/'qa_motion/candidate.glb.import')},
                  'binding_sha256':qa.sha(project/'qa_motion/candidate_binding.json'),
                  'helper_sha256':qa.sha(project/'_qa_local/motion_candidate_browser.gd'),
                  'controls_sha256':qa.sha(out/'motion-review-controls.html')}
        import_receipt = {'profile':'fixture'}
        manifest = {'export_input_sha256':qa.inventory(project), 'source_sha256':color.SOURCE_SHA256,
                    'source_fingerprint':'source', 'production_head_sha256':qa.sha(out/'production-head.html'),
                    'web_import_profile':import_receipt, 'runner_color_review':color_receipt,
                    'hero_motion':motion}
        qa.write(out/'manifest.json', manifest)
        calls = []
        def engine_stub(command, **_kwargs):
            calls.append(command)
            if '--export-release' in command:
                (web/'index.html').write_text(standard)
                for name in ('index.pck','index.wasm','index.js'):
                    (web/name).write_text('fixture '+name)
            return SimpleNamespace(returncode=0)
        with patch.object(qa.subprocess, 'run', side_effect=engine_stub), \
                patch.object(qa.import_profile, 'apply_to_project', return_value=import_receipt), \
                patch.object(qa.import_profile, 'verify_pack', return_value={'verified':True}), \
                patch.object(qa.pack_memory, 'apply', return_value={'verified':True}), \
                patch.object(qa.offline, 'install', side_effect=lambda html:(html,{'mode':'offline_visual_qa'})), \
                contextlib.redirect_stdout(io.StringIO()):
            changed = json.loads(json.dumps(manifest))
            changed['runner_color_review']['settings']['sun_energy'] = 1.24
            qa.write(out/'manifest.json', changed)
            with self.assertRaisesRegex(AssertionError, 'receipt differs from manifest'):
                qa.build(out, 'unused-godot', silent=True)
            self.assertEqual(calls, [])
            qa.write(out/'manifest.json', manifest)
            qa.build(out, 'unused-godot', silent=True)
        html = (web/'index.html').read_text()
        payload = html.split('window.__wwQABuild = ', 1)[1].split(';\n', 1)[0]
        self.assertEqual(json.loads(payload)['runner_color_review'], color_receipt)
        self.assertEqual(len(calls), 2)


if __name__ == '__main__':
    unittest.main()
