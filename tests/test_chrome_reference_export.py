"""Small preparation contract; no Godot export or browser launch."""
import contextlib
import importlib.util
import io
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('qa_export',ROOT/'tools/qa/chrome_reference_export.py')
qa=importlib.util.module_from_spec(spec);spec.loader.exec_module(qa)


def add_import_profile_fixture(source):
    """One audited UI asset exercises the real isolated import transform."""
    image=source/'assets/art/ui/menu/fixture.webp'
    image.parent.mkdir(parents=True,exist_ok=True)
    image.write_bytes(b'host-only source image; no engine import')
    sidecar=image.with_name(image.name+'.import')
    sidecar.write_text('[params]\ncompress/mode=0\ncompress/lossy_quality=0.7\nmipmaps/generate=false\n')
    profile={
        'schema_version':1,
        'helper_sha256':qa.sha(Path(qa.import_profile.__file__)),
        'pack_memory_helper_sha256':qa.sha(ROOT/'tools/release/web_pack_memory.py'),
        'quality_gate':{'min_ssim':0.995,'min_psnr_db':35.0,'max_alpha_error':0},
        'max_pack_bytes':1_000_000,
        'assets':[{'path':image.relative_to(source).as_posix(),'quality':0.95,'mipmaps':False,
            'source_sha256':qa.sha(image),
            'sampler_settings_sha256':hashlib.sha256(qa.import_profile.non_quality_settings(sidecar.read_text()).encode()).hexdigest(),
            'imported_path':'.godot/imported/fixture.webp.ctex','imported_sha256':'a'*64}],
    }
    target=source/'data/web/ui_import_profile.json';target.parent.mkdir(parents=True,exist_ok=True)
    qa.write(target,profile)
    return image,sidecar

class ExportPreparationTest(unittest.TestCase):
    def test_production_contract_preserved_in_fresh_copy(self):
        with tempfile.TemporaryDirectory() as temp:
            source=Path(temp)/'source';source.mkdir()
            for name in ('assets','data','scenes','scripts'):
                (source/name).mkdir();(source/name/'fixture.txt').write_text('unchanged')
            (source/'tools/qa').mkdir(parents=True)
            for suffix in ('gd','js'):
                shutil.copy2(ROOT/f'tools/qa/chrome_reference_bridge.{suffix}',source/f'tools/qa/chrome_reference_bridge.{suffix}')
            for name in ('project.godot','export_presets.cfg'):shutil.copy2(ROOT/name,source/name)
            image,sidecar=add_import_profile_fixture(source)
            original_image=image.read_bytes();original_import=sidecar.read_bytes()
            original_project=(source/'project.godot').read_bytes()
            original_preset=(source/'export_presets.cfg').read_bytes()
            old_root=qa.ROOT;qa.ROOT=source
            try:
                out=Path(temp)/'result'
                with contextlib.redirect_stdout(io.StringIO()):qa.prepare(out)
            finally:qa.ROOT=old_root
            self.assertEqual((source/'project.godot').read_bytes(),original_project)
            self.assertEqual((source/'export_presets.cfg').read_bytes(),original_preset)
            self.assertEqual(image.read_bytes(),original_image)
            self.assertEqual(sidecar.read_bytes(),original_import)
            self.assertIn('compress/lossy_quality=0.95',(out/'project'/sidecar.relative_to(source)).read_text())
            before=qa.helpers._preset_sections(original_preset.decode())
            after=qa.helpers._preset_sections((out/'project/export_presets.cfg').read_text())
            self.assertEqual(after['preset.0.options'].strip(),before['preset.4.options'].strip())
            self.assertEqual(after['preset.0'].replace(',_qa_local/*.js','').strip(),before['preset.4'].strip())
            project=(out/'project/project.godot').read_text()
            self.assertEqual(project.count('ChromeReferenceQA='),1)
            self.assertIn('ChromeReferenceQA=',project.split('[autoload]')[1].split('[qa]')[0])
            self.assertIn('run/main_scene="res://scenes/ui/main.tscn"',project)
            self.assertNotIn('force_touch',project)
            manifest=json.loads((out/'manifest.json').read_text())
            self.assertEqual(len(manifest['qa_token']),32)
            self.assertEqual(manifest['web_import_profile']['profiled_textures'],1)
            self.assertEqual(qa.inventory(out/'project'),manifest['export_input_sha256'])
            self.assertFalse((out/'build.json').exists())
            with self.assertRaises(FileExistsError):qa.prepare(out)

class ExportAudioModeTest(unittest.TestCase):
    def test_silent_is_explicit_and_preserves_standard_export(self):
        # Exercise real build HTML/receipt logic; replace only engine subprocesses
        # and independently tested auth/import/PCK transforms. Assert each
        # contract is called and its receipt retained; never skip build gates.
        for silent in (False, True):
            with self.subTest(silent=silent), tempfile.TemporaryDirectory() as temp:
                root=Path(temp); out=root/'output'; project=out/'project'; web=out/'web'
                project.mkdir(parents=True); web.mkdir()
                scalar=root/'tools/qa/memory_scalar_helper.js'
                scalar.parent.mkdir(parents=True); scalar.write_text('// scalar fixture')
                head='<script>/* production head */</script>'
                standard=head+'\n<script>const GODOT_CONFIG = {args: ["existing"]}; const engine = new Engine(GODOT_CONFIG);</script>'
                (out/'production-head.html').write_text(head)
                import_receipt={'profile_sha256':'profile','profiled_textures':1}
                pack_receipt={'pack_sha256':'pack','verified_textures':1}
                memory_receipt={'input_sha256':'before','output_sha256':'after'}
                qa.write(out/'manifest.json', {'export_input_sha256':{}, 'source_fingerprint':'source', 'production_head_sha256':'head',
                    'web_import_profile':import_receipt})
                calls=[]
                def engine_stub(command, **kwargs):
                    calls.append(command)
                    if '--export-release' in command:
                        (web/'index.html').write_text(standard)
                        for name in ('index.pck','index.wasm','index.js'):
                            (web/name).write_text('fixture '+name)
                    return SimpleNamespace(returncode=0)
                with patch.object(qa,'ROOT',root), patch.object(qa.subprocess,'run',side_effect=engine_stub), \
                        patch.object(qa.import_profile,'apply_to_project',return_value=import_receipt) as apply_profile, \
                        patch.object(qa.import_profile,'verify_pack',return_value=pack_receipt) as verify_pack, \
                        patch.object(qa.pack_memory,'apply',return_value=memory_receipt) as pack_memory, \
                        patch.object(qa.offline,'install',side_effect=lambda html:(html,{'mode':'offline_visual_qa'})), contextlib.redirect_stdout(io.StringIO()):
                    qa.build(out,'unused-godot',silent=silent)
                apply_profile.assert_called_once_with(project,project/'data/web/ui_import_profile.json')
                verify_pack.assert_called_once_with(web/'index.pck',project/'data/web/ui_import_profile.json')
                pack_memory.assert_called_once_with(web/'index.js')
                actual=(web/'index.html').read_text()
                injection='GODOT_CONFIG.args = [...(GODOT_CONFIG.args || []), "--audio-driver", "Dummy"];'
                self.assertEqual(actual.count(injection),int(silent))
                if silent:
                    self.assertLess(actual.index(injection),actual.index('const engine = new Engine'))
                self.assertEqual((out/'standard-exported-index.html').read_text(),standard)
                self.assertIn('args: ["existing"]',actual)
                self.assertIn('"runtime_audio_driver": "'+('Dummy' if silent else 'WebAudio')+'"',actual)
                manifest=json.loads((out/'manifest.json').read_text())
                self.assertEqual('runtime_audio_override' in manifest,silent)
                build=json.loads((out/'build.json').read_text())
                self.assertEqual(build['audio'].startswith('Dummy'),silent)
                self.assertTrue(build['no_final_browser_acceptance'])
                self.assertEqual(build['web_import_profile'],pack_receipt)
                self.assertEqual(build['web_pack_memory'],memory_receipt)
                self.assertEqual(len(calls),2)
                self.assertTrue(all(c[c.index('--audio-driver')+1]=='Dummy' for c in calls))

    def test_changed_import_profile_stops_before_engine_dispatch(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp);project=out/'project';project.mkdir()
            qa.write(out/'manifest.json',{'export_input_sha256':{},'web_import_profile':{'profile_sha256':'prepared'}})
            with patch.object(qa.import_profile,'apply_to_project',return_value={'profile_sha256':'changed'}), \
                    patch.object(qa.subprocess,'run') as engine:
                with self.assertRaisesRegex(AssertionError,'Prepared Web import profile changed'):
                    qa.build(out,'unused-godot')
                engine.assert_not_called()

if __name__=='__main__':unittest.main()
