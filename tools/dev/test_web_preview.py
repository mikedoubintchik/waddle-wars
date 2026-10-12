import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('preview', Path(__file__).with_name('web_preview.py'))
dev = importlib.util.module_from_spec(spec); spec.loader.exec_module(dev)


class PreviewTests(unittest.TestCase):
    def test_hold_serves_current_until_coordinated_edits_are_released(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            app = dev.Preview(p, p, '/unused/godot')
            marker = p / 'hold-builds'; marker.touch()
            waits = 0
            def wait(_seconds):
                nonlocal waits
                waits += 1
                if waits == 1:
                    self.assertTrue(app.status['held'])
                    marker.unlink()
            def build(_signature):
                self.assertFalse(app.status['held'])
                app.stop.set()
            with patch.object(app.stop, 'wait', side_effect=wait), \
                    patch.object(dev, 'inventory', return_value='changed') as scan, \
                    patch.object(dev.time, 'monotonic', side_effect=[0, 2]), \
                    patch.object(app, 'build', side_effect=build) as rebuild:
                app.watch()
            self.assertEqual(scan.call_count, 2)
            rebuild.assert_called_once_with('changed')

    def test_debounce_and_failed_signature_do_not_build_forever(self):
        d = dev.Debounce(1)
        self.assertFalse(d.observe('a', 0))
        self.assertFalse(d.observe('b', .8))
        self.assertFalse(d.observe('b', 1.3))
        self.assertTrue(d.observe('b', 1.81))
        self.assertEqual(d.start(), 'b')
        self.assertFalse(d.observe('b', 20))
        self.assertFalse(d.observe('c', 21))
        self.assertTrue(d.observe('c', 23))

    def test_watch_real_changes_ignores_generated_exports_and_qa(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp); (p/'scripts').mkdir(); (p/'scripts/a.gd').write_text('first')
            first = dev.inventory(p)
            (p/'qa_shots').mkdir(); (p/'qa_shots/shot.png').write_text('ignored')
            (p/'build').mkdir(); (p/'build/export.pck').write_text('ignored')
            self.assertEqual(first, dev.inventory(p))
            (p/'scripts/a.gd').write_text('second')
            self.assertNotEqual(first, dev.inventory(p))
            second = dev.inventory(p); (p/'scripts/a.gd').unlink()
            self.assertNotEqual(second, dev.inventory(p))

    def test_publish_only_complete_current_success_and_discard_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp); builds = p/'builds'; builds.mkdir(); current = p/'current.json'
            dev.atomic_json(current, {'id':'good'})
            stale = builds/'.staging-stale'; stale.mkdir(); (stale/'index.pck').write_text('partial')
            self.assertFalse(dev.publish(stale, builds, current, {'id':'stale'}, 'a','b'))
            self.assertEqual(json.loads(current.read_text()), {'id':'good'})
            self.assertFalse(stale.exists())
            valid = builds/'.staging-next'; valid.mkdir(); (valid/'index.pck').write_text('complete')
            self.assertTrue(dev.publish(valid, builds, current, {'id':'next'}, 'b','b'))
            self.assertEqual(json.loads(current.read_text()), {'id':'next'})
            self.assertEqual((builds/'next/index.pck').read_text(), 'complete')

    def test_import_profile_and_helpers_are_content_bound_even_with_same_mtime(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('tools/release/web_import_profile.py', 'tools/release/web_pack_memory.py', 'data/web/ui_import_profile.json'):
                path = root/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('AAAA')
                before = dev.inventory(root); stamp = path.stat()
                path.write_text('BBBB'); os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
                self.assertNotEqual(before, dev.inventory(root))

    def test_over_budget_pack_is_never_published_or_shell_patched(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); dev.atomic_json(root/'current.json', {'id':'good','source_fingerprint':'old'})
            app = dev.Preview(root, root, '/unused/godot')
            def export(command, **_kwargs):
                if '--export-release' in command:
                    destination = Path(command[-1]).parent
                    for name in ('index.html','index.js','index.pck','index.wasm'):
                        (destination/name).write_text('fake-export')
            with patch.object(app, 'sync'), patch.object(dev.subprocess, 'run', side_effect=export), \
                    patch.object(dev.import_profile, 'verify_pack', side_effect=ValueError('Web pack exceeds audited budget')), \
                    patch.object(dev.pack_memory, 'apply') as memory:
                app.build('new')
            memory.assert_not_called()
            self.assertEqual(json.loads((root/'current.json').read_text())['id'], 'good')
            self.assertIn('exceeds audited budget', app.status['error'])
            self.assertEqual(list((root/'builds').iterdir()), [])

    def test_export_failure_keeps_good_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp); dev.atomic_json(p/'current.json', {'id':'good','source_fingerprint':'old'})
            app = dev.Preview(p, p, '/missing/godot')
            with patch.object(app, 'sync'), patch.object(dev.subprocess, 'run', side_effect=RuntimeError('compile failed')):
                app.build('new')
            self.assertEqual(json.loads((p/'current.json').read_text())['id'], 'good')
            self.assertFalse(app.status['building'])
            self.assertIn('compile failed', app.status['error'])
            self.assertEqual(list((p/'builds').iterdir()), [])

    def test_shell_injection_fails_closed_if_export_template_changes(self):
        with self.assertRaises(RuntimeError): dev.inject_runtime('<html/>', 'bridge')
        with self.assertRaises(RuntimeError): dev.inject_runtime('const engine = new Engine(GODOT_CONFIG);'*2, 'bridge')
        self.assertIn('bridge', dev.inject_runtime('const engine = new Engine(GODOT_CONFIG);', 'bridge'))

if __name__ == '__main__': unittest.main()
