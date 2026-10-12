"""Portable capture provenance must reject changed sources and old receipts."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('validate_water_capture.py')
spec = importlib.util.spec_from_file_location('water_capture', SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class WaterCaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.root = self.directory / 'checkout'
        self.task = self.directory / 'evidence'
        for name in (m.CANDIDATE_PATH, 'art_src/characters/penguin_motion_v1/metadata.json',
                     'tools/qa/runner_color_candidate.py', 'tools/release/web_import_profile.py',
                     'tools/release/web_pack_memory.py'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic input: ' + name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_cli_freeze_uses_explicit_root_and_external_evidence_directory(self):
        result = subprocess.run([sys.executable, str(SCRIPT), '--root', str(self.root),
                                 'freeze', '--task', str(self.task)], cwd=self.directory,
                                capture_output=True, text=True, check=True)
        value = json.loads((self.task / 'source-freeze.json').read_text())
        self.assertEqual(value['fingerprint'], result.stdout.strip())
        self.assertEqual(value['files'][m.CANDIDATE_PATH], m.sha(self.root / m.CANDIDATE_PATH))
        self.assertTrue(all(not Path(path).is_absolute() for path in value['files']))
        self.assertFalse(value['human_approval'])

    def test_existing_freeze_preserved(self):
        m.freeze(self.task, self.root)
        path = self.task / 'source-freeze.json'
        original = path.read_bytes()
        with self.assertRaisesRegex(AssertionError, 'Freeze already exists'):
            m.freeze(self.task, self.root)
        self.assertEqual(path.read_bytes(), original)

    def test_changed_candidate_fails_before_reading_export_or_writing_receipt(self):
        m.freeze(self.task, self.root)
        (self.root / m.CANDIDATE_PATH).write_bytes(b'changed candidate')
        with self.assertRaisesRegex(AssertionError, 'Frozen QA inputs changed'):
            m.validate(self.task, self.directory / 'missing-export',
                       self.directory / 'missing-previous', self.root)
        self.assertFalse((self.task / 'final-capture-validation.json').exists())

    def test_old_validator_receipt_is_not_silently_reused(self):
        value = m.freeze(self.task, self.root)
        value['validator_sha256'] = '0' * 64
        m.write(self.task / 'source-freeze.json', value)
        with self.assertRaisesRegex(AssertionError, 'Capture validator changed'):
            m.validate(self.task, self.directory / 'missing-export',
                       self.directory / 'missing-previous', self.root)


if __name__ == '__main__':
    unittest.main()
