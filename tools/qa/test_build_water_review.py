import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('water_review', Path(__file__).with_name('build_water_review.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class WaterReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.base = self.root / 'previous'
        self.out = self.root / 'current'
        self.config = self.root / 'review-config.json'
        self.manifest = {'pages': [{'id': f'page-{i}', 'title': str(i)} for i in range(67)],
                         'entries': [{'id': 'page-0', 'view': 'desktop', 'actual': 'previous.jpg',
                                      'pending': True, 'source_iteration': 14}],
                         'accepted_views': 0, 'pending_views': 134, 'affected_routes': [], 'fresh_views': 0,
                         'studio_collections': [{'id': 'penguin', 'title': 'Penguin', 'path': 'penguin/studio/index.html'}]}
        self.put(self.base / 'index.html', '<html><body><script id="catalogue-data" type="application/json">' + json.dumps(self.manifest) + '</script><script src="gallery.js"></script></body></html>')
        self.put(self.base / 'gallery.js', 'const label="Character studies";')
        self.put(self.base / 'manifest.json', json.dumps(self.manifest))
        self.put(self.base / 'previous.jpg', b'Previous image unchanged')
        self.put(self.base / 'reference.png', b'Reference image unchanged')
        for part in ('studio', 'review'):
            self.put(self.base / 'penguin' / part / 'index.html', '<html><body><p>Previous water gap</p><img src="../../reference.png"></body></html>')
        records = {str(p.relative_to(self.base)): {'source': str(p), 'source_sha256': m.sha(p),
                   'output_sha256': m.sha(p), 'bytes': p.stat().st_size, 'byte_identical': True}
                   for p in self.base.rglob('*') if p.is_file()}
        m.write(self.base / 'provenance/package-inventory.json', {'files': records})
        m.write(self.base / 'provenance/build-receipt.json', {'human_approval': False})
        self.data = {'review_date': '2026-10-12', 'title': 'Scene & water', 'summary': 'Richer water with readable crests.',
                     'verdict': 'Ready for human review.', 'comparison_limits': 'Scene arrangement varies.',
                     'visual_status': 'ready_for_review', 'human_approval': False, 'frames': []}
        for device in ('desktop', 'mobile'):
            current = self.put(self.root / f'{device}.jpg', f'New image {device}')
            sidecar = self.put(self.root / f'{device}.json', json.dumps({'image': {'sha256': m.sha(current)},
                'qa': {'source_url': f'http://127.0.0.1:60000/game?scene=day&qa_token=new-private-{device}&mode=water',
                       'qa_token': f'nested-private-{device}', 'nested': [{'qa_token': 'list-private-value'}]},
                'motion': {'status': 'ready', 'motion': {'playing': False, 'action': 'waddle', 'phase': 0}}}))
            self.data['frames'].append({'id': f'{device}-waddle', 'label': 'Waddle', 'device': device,
                'action': 'waddle', 'phase': 0, 'current': str(current), 'sidecar': str(sidecar),
                'previous': str(self.base / 'previous.jpg'), 'reference': str(self.base / 'reference.png')})
        self.save()

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode())
        return path

    def save(self):
        m.write(self.config, self.data)

    def build(self):
        return m.add_review(self.base, self.out, self.config)

    def production(self):
        self.data.update(capture_contract='production_runner', title='Gameplay integration')
        for frame in self.data['frames']:
            sidecar = m.read(frame['sidecar'])
            sidecar.pop('motion', None)
            sidecar['qa'].update(status='ready', error='', tree_paused=True,
                build={'source_fingerprint': 'a' * 64, 'pack_sha256': 'b' * 64},
                reviewed_penguin={'active': True, 'visible': True, 'procedural_visible_meshes': 0,
                    'renderer': {'model_path': 'res://assets/art/characters/runner_penguin_v1.glb',
                        'visible': True, 'visible_in_tree': True, 'action': frame['action'],
                        'clip': frame['action'], 'clip_time': .432, 'clip_length': 1.2, 'phase': .36,
                        'surfaces': [{'visible': True, 'imported_material': True, 'override': False,
                            'overlay': False, 'material_class': 'StandardMaterial3D'}]}})
            m.write(Path(frame['sidecar']), sidecar)
        self.save()

    def mutate_production(self, change):
        path = Path(self.data['frames'][0]['sidecar'])
        sidecar = m.read(path)
        change(sidecar['qa'])
        m.write(path, sidecar)

    def test_additive_build_preserves_gallery_and_parent(self):
        before = {str(p.relative_to(self.base)): m.sha(p) for p in self.base.rglob('*') if p.is_file()}
        receipt = self.build()
        manifest = m.read(self.out / 'manifest.json')
        for field in ('pages', 'entries', 'accepted_views', 'pending_views', 'affected_routes', 'fresh_views'):
            self.assertEqual(manifest[field], self.manifest[field])
        self.assertEqual([c['id'] for c in manifest['studio_collections']], ['water', 'penguin'])
        self.assertEqual(receipt['page_count'], 67)
        self.assertEqual(receipt['pending_views'], 134)
        self.assertFalse(receipt['human_approval'])
        self.assertEqual(before, {str(p.relative_to(self.base)): m.sha(p) for p in self.base.rglob('*') if p.is_file()})

    def test_media_reused_byte_exact_and_presentation_uncropped(self):
        self.build()
        data = m.read(self.out / 'water/comparison-data.json')
        self.assertEqual(data['frames'][0]['reference']['url'], '../reference.png')
        self.assertEqual(data['frames'][0]['previous']['url'], '../previous.jpg')
        for frame in data['frames']:
            for role in ('reference', 'previous', 'current', 'sidecar'):
                self.assertEqual(m.sha(self.out / 'water' / frame[role]['url']), frame[role]['sha256'])
        text = (self.out / 'water/index.html').read_text()
        self.assertIn('height:auto', text)
        self.assertNotIn('object-fit:cover', text)
        self.assertNotIn('canvas', text)
        self.assertIn('Previous color revision', (self.out / 'penguin/review/index.html').read_text())

    def test_legacy_review_with_implicit_body_gets_history_notice(self):
        page = self.put(self.base / 'penguin/review/index.html', '<!doctype html><style>main{color:white}</style><main><h1>Legacy review</h1></main>')
        inventory = m.read(self.base / 'provenance/package-inventory.json')
        inventory['files']['penguin/review/index.html'].update(source_sha256=m.sha(page), output_sha256=m.sha(page))
        m.write(self.base / 'provenance/package-inventory.json', inventory)
        self.build()
        self.assertIn('<main><aside', (self.out / 'penguin/review/index.html').read_text())

    def test_hash_mismatch_rejected_before_clone(self):
        Path(self.data['frames'][0]['current']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'image hash'):
            self.build()
        self.assertFalse(self.out.exists())

    def test_missing_orientation_rejected(self):
        self.data['frames'].pop(); self.save()
        with self.assertRaisesRegex(ValueError, 'Both desktop and phone'):
            self.build()

    def test_review_date_and_relative_paths_are_portable(self):
        self.data['review_date'] = '2027-01-03'
        for frame in self.data['frames']:
            for role in ('current', 'sidecar', 'previous', 'reference'):
                frame[role] = str(Path(frame[role]).relative_to(self.config.parent))
        self.save()
        self.build()
        self.assertIn('2027-01-03', (self.out / 'water/index.html').read_text())
        self.assertIn('2027-01-03', m.read(self.out / 'manifest.json')['studio_note'])
        self.assertNotIn('October 12, 2026', (self.out / 'water/index.html').read_text())

    def test_wrong_action_and_phase_rejected(self):
        for field, value in (('action', 'slide'), ('phase', .5)):
            original = copy.deepcopy(self.data)
            self.data['frames'][0][field] = value; self.save()
            with self.assertRaisesRegex(ValueError, f'{field} mismatch'):
                self.build()
            self.data = original

    def test_unapproved_only(self):
        self.data['human_approval'] = True; self.save()
        with self.assertRaisesRegex(ValueError, 'Human approval'):
            self.build()

    def test_nonempty_output_preserved(self):
        existing = self.put(self.out / 'keep.txt', 'keep')
        with self.assertRaisesRegex(ValueError, 'empty'):
            self.build()
        self.assertEqual(existing.read_text(), 'keep')

    def test_overlapping_destination_rejected(self):
        with self.assertRaisesRegex(ValueError, 'overlap'):
            m.add_review(self.base, self.base / 'nested', self.config)

    def test_final_inventory_detects_mutated_capture(self):
        self.build()
        data = m.read(self.out / 'water/comparison-data.json')
        (self.out / 'water' / data['frames'][0]['current']['url']).write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'Packaged asset changed'):
            m.studio.validate_site(self.out)

    def test_public_sidecar_sanitized_with_raw_and_public_hashes(self):
        raw_hash = m.sha(self.data['frames'][0]['sidecar'])
        receipt = self.build()
        data = m.read(self.out / 'water/comparison-data.json')
        evidence = data['frames'][0]['sidecar']
        public_path = self.out / 'water' / evidence['url']
        public = m.read(public_path)
        self.assertEqual(evidence['raw_sha256'], raw_hash)
        self.assertEqual(evidence['sanitized_sha256'], m.sha(public_path))
        self.assertNotEqual(evidence['raw_sha256'], evidence['sanitized_sha256'])
        self.assertEqual(public['qa']['source_url'], 'http://127.0.0.1:60000/game?scene=day&mode=water')
        self.assertEqual(public['qa']['nested'], [{}])
        self.assertEqual(m.sha(self.data['frames'][0]['sidecar']), raw_hash)
        self.assertFalse(receipt['private_raw_sidecars_packaged'])
        for path in self.out.rglob('*'):
            if path.is_file() and path.suffix in {'.json', '.html', '.original'}:
                self.assertNotIn('qa_token', path.read_text())
                self.assertNotIn('new-private-', path.read_text())
                self.assertNotIn('nested-private-', path.read_text())

    def test_inherited_raw_sidecars_and_original_pages_sanitized(self):
        raw = self.put(self.base / 'history/raw.json', json.dumps({'qa_token': 'old-dict-private',
            'qa': {'source_url': 'http://127.0.0.1/game?qa_token=old-url-private&view=phone'}}))
        original = self.put(self.base / 'provenance/original.html.original',
            '<a href="http://127.0.0.1/game?qa_token=old-page-private&view=desktop">Old game</a>')
        page = self.put(self.base / 'history/old.html', '<html><body>Old review</body></html>')
        inventory = m.read(self.base / 'provenance/package-inventory.json')
        for path in (raw, original, page):
            inventory['files'][str(path.relative_to(self.base))] = {'source': str(path), 'source_sha256': m.sha(path),
                'output_sha256': m.sha(path), 'byte_identical': True}
        record = inventory['files']['history/old.html']
        record.update(source_sha256=m.sha(original), preserved_original='provenance/original.html.original')
        m.write(self.base / 'provenance/package-inventory.json', inventory)
        raw_before = raw.read_bytes(); original_before = original.read_bytes()
        receipt = self.build()
        self.assertEqual(receipt['inherited_public_files_sanitized'], 2)
        self.assertEqual(raw.read_bytes(), raw_before)
        self.assertEqual(original.read_bytes(), original_before)
        self.assertNotIn('qa_token', (self.out / 'history/raw.json').read_text())
        self.assertNotIn('old-page-private', (self.out / 'provenance/original.html.original').read_text())
        final_record = m.read(self.out / 'provenance/package-inventory.json')['files']['history/old.html']
        self.assertNotIn('preserved_original', final_record)
        self.assertEqual(final_record['raw_original_sha256'], m.sha(original))
        self.assertEqual(final_record['sanitized_original_sha256'], m.sha(self.out / 'provenance/original.html.original'))
        self.assertGreater(m.studio.validate_site(self.out)['output_hashes_checked'], 0)

    def test_production_contract_preserves_physics_phase_and_gallery_counts(self):
        self.production()
        # Fresh production gallery status must survive additive presentation.
        manifest = m.read(self.base / 'manifest.json')
        manifest.update(accepted_views=134, pending_views=0, fresh_views=134)
        m.write(self.base / 'manifest.json', manifest)
        inventory = m.read(self.base / 'provenance/package-inventory.json')
        digest = m.sha(self.base / 'manifest.json')
        inventory['files']['manifest.json'].update(source_sha256=digest, output_sha256=digest)
        m.write(self.base / 'provenance/package-inventory.json', inventory)
        receipt = self.build()
        result = m.read(self.out / 'manifest.json')
        comparison = m.read(self.out / 'water/comparison-data.json')
        self.assertEqual(comparison['frames'][0]['phase'], .36)
        self.assertEqual(receipt['accepted_views'], 134)
        self.assertEqual(receipt['pending_views'], 0)
        self.assertTrue(receipt['production_gameplay_captures'])
        self.assertEqual(result['fresh_views'], 134)
        self.assertEqual(result['studio_collections'][0]['title'], 'Gameplay integration')
        self.assertIn('normal gameplay comparison', result['studio_note'])
        self.assertNotIn('candidate comparison', result['studio_note'])
        self.assertIn('CURRENT GAME · INTEGRATED GAMEPLAY', (self.out / 'water/index.html').read_text())
        self.assertIn('Previously reviewed candidate', (self.out / 'water/index.html').read_text())

    def test_production_rejects_candidate_flags_even_false(self):
        for key in ('hero_candidate', 'hero_motion', 'hero_shape', 'runner_color_review'):
            with self.subTest(key=key):
                self.production()
                self.mutate_production(lambda qa: qa['build'].update({key: False}))
                with self.assertRaisesRegex(ValueError, 'candidate build flags'):
                    self.build()
                self.assertFalse(self.out.exists())

    def test_production_rejects_duplicate_or_inactive_penguin(self):
        for key, value in (('procedural_visible_meshes', 1), ('procedural_visible_meshes', False),
                           ('active', False), ('visible', False)):
            with self.subTest(key=key, value=value):
                self.production()
                self.mutate_production(lambda qa: qa['reviewed_penguin'].update({key: value}))
                with self.assertRaisesRegex(ValueError, 'without duplicate'):
                    self.build()

    def test_production_rejects_unpaused_unready_or_missing_build(self):
        for key, value in (('tree_paused', False), ('status', 'pending'), ('error', 'renderer failed'), ('build', None)):
            with self.subTest(key=key):
                self.production()
                self.mutate_production(lambda qa: qa.update({key: value}))
                with self.assertRaisesRegex(ValueError, 'tree-paused|build evidence'):
                    self.build()

    def test_production_rejects_missing_or_hidden_runtime_renderer(self):
        for mutation in (lambda p: p.pop('renderer'),
                         lambda p: p['renderer'].update(visible_in_tree=False),
                         lambda p: p['renderer'].update(model_path='res://qa_motion/candidate.glb')):
            self.production()
            self.mutate_production(lambda qa: mutation(qa['reviewed_penguin']))
            with self.assertRaisesRegex(ValueError, 'runtime renderer evidence'):
                self.build()

    def test_production_rejects_missing_wrong_or_invalid_actual_clip(self):
        for key, value in (('clip', None), ('clip', 'slide'), ('clip_time', None),
                           ('clip_length', 0), ('phase', float('nan'))):
            with self.subTest(key=key, value=value):
                self.production()
                self.mutate_production(lambda qa: qa['reviewed_penguin']['renderer'].update({key: value}))
                with self.assertRaisesRegex(ValueError, 'clip'):
                    self.build()

    def test_production_rejects_overridden_or_missing_material_evidence(self):
        for field, value in (('override', True), ('overlay', True), ('imported_material', False),
                             ('material_class', None), ('visible', False)):
            with self.subTest(field=field):
                self.production()
                self.mutate_production(lambda qa: qa['reviewed_penguin']['renderer']['surfaces'][0].update({field: value}))
                with self.assertRaisesRegex(ValueError, 'imported material evidence'):
                    self.build()
        self.production()
        self.mutate_production(lambda qa: qa['reviewed_penguin']['renderer'].pop('surfaces'))
        with self.assertRaisesRegex(ValueError, 'single imported surface'):
            self.build()

    def test_production_contract_never_implicitly_relabels_candidate(self):
        self.data['capture_contract'] = 'production_runner'
        self.save()
        with self.assertRaisesRegex(ValueError, 'Production capture'):
            self.build()
        self.data.pop('capture_contract')
        self.save()
        self.build()
        self.assertIn('CURRENT GAME · WATER UPDATE', (self.out / 'water/index.html').read_text())
        self.assertFalse(m.read(self.out / 'provenance/build-receipt.json')['production_gameplay_captures'])

    def test_repeated_review_retains_prior_frames_and_provenance(self):
        self.build()
        prior_media = {str(p.relative_to(self.out)): m.sha(p) for p in self.out.rglob('*')
                       if p.is_file() and p.suffix in m.studio.MEDIA}
        prior_receipt = m.sha(self.out / 'provenance/water-parent/build-receipt.json')
        self.production()
        frame = self.data['frames'][0]
        Path(frame['current']).write_bytes(b'New actual integrated production pixels')
        sidecar = m.read(frame['sidecar'])
        sidecar['image']['sha256'] = m.sha(frame['current'])
        m.write(Path(frame['sidecar']), sidecar)
        next_out = self.root / 'next'
        m.add_review(self.out, next_out, self.config)
        for relative, digest in prior_media.items():
            self.assertEqual(m.sha(next_out / relative), digest)
        self.assertEqual(m.sha(next_out / 'provenance/water-parent/build-receipt.json'), prior_receipt)
        self.assertEqual(len(list((next_out / 'provenance').glob('water-parent-*'))), 1)
        m.studio.validate_site(next_out)


if __name__ == '__main__':
    unittest.main()
