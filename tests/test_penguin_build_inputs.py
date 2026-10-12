"""Clean checkouts must contain immutable inputs needed by surface rebuilds."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PenguinBuildInputTests(unittest.TestCase):
    def test_preserved_normals_input_is_durable_and_exact(self):
        directory = ROOT / 'art_src/characters/penguin_rear_surface_v3/build_inputs'
        receipt = json.loads((directory / 'provenance.json').read_text())
        source = directory / receipt['file']
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), receipt['sha256'])
        self.assertEqual(source.stat().st_size, receipt['bytes'])
        self.assertFalse(receipt['human_approval'])
        tree = ast.parse((ROOT / 'tools/art/build_penguin_rear_surface_v3.py').read_text())
        paths = [node.value for node in ast.walk(tree)
                 if isinstance(node, ast.Constant) and isinstance(node.value, str)]
        self.assertIn('build_inputs/' + receipt['file'], paths)
        self.assertNotIn(receipt['original_path'], paths)
        self.assertIn(receipt['sha256'], paths)

    def validator(self):
        spec = importlib.util.spec_from_file_location('penguin_art_validator', ROOT / 'tools/art/validate_art.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        validator = module.ArtValidator(include_review_fragments=True)
        validator.source = json.loads((ROOT / 'art_src/runner/source_manifest.json').read_text())
        return module, validator

    def test_runner_package_and_source_studies_validate_without_full_character_claims(self):
        module, validator = self.validator()
        validator._validate_study_sources({'project_original'})
        validator._validate_authored_packages({'project_original'})
        self.assertEqual(validator.errors, [])
        schema = json.loads((ROOT / 'art_src/runner/source_manifest.schema.json').read_text())
        self.assertEqual(schema['properties']['authored_packages']['items']['properties']['expected']['const'],
                         module.RUNNER_PACKAGE_CONTRACT)
        self.assertEqual(module.ASSET_CLASS_BUDGETS['character']['lod0_triangles_min'], 18000)
        self.assertEqual(len(module.CHARACTER_REQUIRED_ANIMATIONS), 23)

    def test_runner_package_rejects_stale_binding_or_front_approval(self):
        for key, value, message in [('binding_sha256', '0' * 64, 'binding is missing or has a stale hash'),
                                    ('front_ready', True, 'cannot claim full-character approval')]:
            _, validator = self.validator()
            validator.source['authored_packages'][0][key] = value
            validator._validate_authored_packages({'project_original'})
            self.assertTrue(any(message in error for error in validator.errors), validator.errors)

    def test_historical_study_cannot_be_promoted_through_source_inventory(self):
        _, validator = self.validator()
        validator.source['study_sources'][0]['production_ready'] = True
        validator._validate_study_sources({'project_original'})
        self.assertTrue(any('must remain explicitly source-only' in error for error in validator.errors))


if __name__ == '__main__':
    unittest.main()
