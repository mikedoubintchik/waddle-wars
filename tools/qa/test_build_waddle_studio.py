import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('studio',Path(__file__).with_name('build_waddle_studio.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class StudioTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.base=self.root/'base';self.task=self.root/'qa_shots/current';self.out=self.root/'site'
        self.base.mkdir();self.task.mkdir(parents=True)
        self.p=m.Packager(self.root,self.base,self.task,self.out,history={60277:'older'})

    def tearDown(self):self.temp.cleanup()

    def put(self,p,value):
        p.parent.mkdir(parents=True,exist_ok=True)
        p.write_bytes(value if isinstance(value,bytes) else value.encode());return p

    def test_media_is_unchanged(self):
        source=self.put(self.task/'studio/library/ref.png',b'original PNG bytes')
        self.p.add(source);self.p.process()
        self.assertEqual(source.read_bytes(),(self.out/'penguin/studio/library/ref.png').read_bytes())
        self.assertTrue(self.p.records['penguin/studio/library/ref.png']['byte_identical'])

    def test_rewrites_localhost_original_and_copies_raw(self):
        image=self.put(self.root/'qa_shots/older/candidate-originals/desktop/a.jpg',b'raw JPEG')
        page=self.put(self.task/'review/index.html','<a href="http://localhost:60277/candidate-originals/desktop/a.jpg">Raw</a>')
        self.p.add(page);self.p.process();text=(self.out/'penguin/review/index.html').read_text()
        self.assertNotIn('localhost',text);self.assertIn('../history/older/candidate-originals/desktop/a.jpg',text)
        self.assertEqual(image.read_bytes(),(self.out/'penguin/history/older/candidate-originals/desktop/a.jpg').read_bytes())

    def test_current_task_not_duplicated_in_history(self):
        pack=m.Packager(self.root,self.base,self.task,self.out,history={60284:'current',60277:'older'})
        self.assertEqual(pack.history,{60277:'older'})
        self.assertEqual(pack.destination(self.task/'review/index.html'),(self.out/'penguin/review/index.html').resolve())

    def test_c0444_history_resolves_portably(self):
        pack=m.Packager(self.root,self.base,self.task,self.out)
        self.assertEqual(pack.history[60284],'penguin-motion-corrections-20261012')
        image=self.put(self.root/'qa_shots/penguin-motion-corrections-20261012/candidate-originals/frame.jpg',b'c0444 unchanged JPEG')
        page=self.put(self.task/'review/index.html','<img src="http://localhost:60284/candidate-originals/frame.jpg">')
        pack.add(page);pack.process()
        text=(self.out/'penguin/review/index.html').read_text()
        self.assertNotIn('localhost',text)
        self.assertEqual(image.read_bytes(),(self.out/'penguin/history/penguin-motion-corrections-20261012/candidate-originals/frame.jpg').read_bytes())

    def test_gallery_return_top_level(self):
        page=self.put(self.task/'review/index.html','<a href="../gallery/index.html">Full gallery</a>')
        self.p.add(page);self.p.process();text=(self.out/'penguin/review/index.html').read_text()
        self.assertIn('href="../../index.html"',text);self.assertIn('target="_top"',text)

    def test_missing_dependency_fails(self):
        page=self.put(self.task/'review/index.html','<img src="missing.jpg">');self.p.add(page)
        with self.assertRaisesRegex(ValueError,'Broken presentation link'):self.p.process()

    def test_source_packages_not_allowed(self):
        source=self.put(self.task/'candidate.glb',b'glb')
        with self.assertRaisesRegex(ValueError,'Not a static review asset'):self.p.add(source)

    def test_output_cannot_escape(self):
        source=self.put(self.task/'a.png',b'image')
        with self.assertRaisesRegex(ValueError,'escapes'):self.p.add(source,self.root/'escape.png')

    def test_comparison_json_dependencies(self):
        image=self.put(self.task/'candidate-originals/a.jpg',b'jpg')
        data=self.put(self.task/'review/comparison-data.json',json.dumps({'after':{'actual':'../candidate-originals/a.jpg'}}))
        self.p.add(data);self.p.process()
        self.assertEqual(image.read_bytes(),(self.out/'penguin/candidate-originals/a.jpg').read_bytes())

    def test_validate_manifest_assets(self):
        self.put(self.out/'index.html','<p>Gallery</p>');self.put(self.out/'manifest.json',json.dumps({'entries':[{'actual':'missing.jpg'}]}))
        with self.assertRaisesRegex(ValueError,'missing.jpg'):m.validate_site(self.out)

    def test_validate_preserved_hashes(self):
        self.put(self.out/'index.html','<p>Gallery</p>');asset=self.put(self.out/'image.jpg',b'actual')
        self.put(self.out/'provenance/package-inventory.json',json.dumps({'files':{'image.jpg':{'output_sha256':m.sha(asset)}}}))
        self.assertEqual(m.validate_site(self.out)['output_hashes_checked'],1)
        asset.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError,'Packaged asset changed'):m.validate_site(self.out)

    def test_historical_source_url_not_live_dependency(self):
        self.put(self.out/'index.html','<script id="catalogue-data" type="application/json">{"source":"http://127.0.0.1:9999/index.html"}</script>')
        self.assertEqual(m.validate_site(self.out)['localhost_dependencies'],[])

    def gallery_fixture(self, page_count=2):
        for name in ('template.html','gallery.js'):
            self.put(self.root/'tools/qa/gallery_assets'/name,
                     (m.ROOT/'tools/qa/gallery_assets'/name).read_bytes())
        self.put(self.base/'index.html','<p>Original gallery</p>')
        self.put(self.base/'reference.png',b'unchanged reference')
        self.put(self.base/'actual.jpg',b'unchanged original capture')
        pages=[{'id':f'page-{i}','title':f'Page {i}','group':'Game'} for i in range(page_count)]
        entries=[{'id':p['id'],'orientation':orientation,'reference':'reference.png','actual':'actual.jpg',
                  'capture_sha256':m.sha(self.base/'actual.jpg'),
                  'capture_provenance':{'captured_at':'2027-01-03T12:00:00Z','accepted':True,
                                        'reviewed_by':'fixture reviewer'},
                  'current_capture_status':'accepted','availability':'accepted',
                  'refreshed_this_iteration':True,'changed_this_iteration':True}
                 for p in pages for orientation in ('desktop','mobile')]
        manifest={'schema':2,'iteration':'fresh-20270103','generated_utc':'2027-01-03T13:00:00Z',
                  'status':'accepted','pages':pages,'entries':entries,'page_count':page_count,
                  'accepted_views':len(entries),'pending_current_views':0,'fresh_views':len(entries),
                  'affected_routes':[p['id'] for p in pages],'plan_id':'frozen-plan',
                  'source_fingerprint':'frozen-sources','prior_collections':[],'overviews':[],
                  'sources':{'source_end_sha256':'source-end-hash'}}
        m.write(self.base/'manifest.json',manifest)
        self.put(self.task/'studio/index.html','<a href="../review/index.html">Study</a>')
        self.put(self.task/'review/index.html','<p>Preserved study</p>')
        m.write(self.task/'final-capture-validation.json',{'candidate_sha256':'old-study-hash'})
        return manifest

    def test_fresh_gallery_preserves_all_67_routes_and_134_views(self):
        original=self.gallery_fixture(67)
        original_bytes=(self.base/'manifest.json').read_bytes()
        receipt=m.build(self.root,self.base,self.task,self.out,history={},preserve_gallery_iteration=True)
        packaged=m.read(self.out/'manifest.json')
        for key,value in original.items():
            self.assertEqual(packaged[key],value,key)
        self.assertEqual(receipt['this_turn_routes'],original['affected_routes'])
        self.assertEqual(receipt['page_count'],67)
        self.assertEqual(receipt['preserved_gallery_fresh_views'],134)
        self.assertEqual(receipt['new_game_page_captures'],0)
        self.assertFalse(receipt['human_approval'])
        self.assertIn('2027-01-03',packaged['studio_note'])
        self.assertIn('134 fresh of 134 views, 0 pending',packaged['studio_note'])
        self.assertNotIn('October 9',packaged['studio_note'])
        self.assertIn('"affected_routes": ["page-0",', (self.out/'index.html').read_text())
        self.assertEqual((self.out/'provenance/base-gallery-manifest.json').read_bytes(),original_bytes)
        self.assertEqual((self.base/'manifest.json').read_bytes(),original_bytes)
        self.assertEqual((self.out/'actual.jpg').read_bytes(),(self.base/'actual.jpg').read_bytes())
        self.assertTrue(receipt['media_byte_identical'])
        self.assertEqual(m.validate_site(self.out)['missing'],[])

    def test_fresh_gallery_does_not_promote_pending_or_historical_views(self):
        original=self.gallery_fixture()
        retained=original['entries'][-1]
        retained.update(refreshed_this_iteration=False,current_capture_status='pending',availability='previous_pending')
        retained['capture_provenance']['captured_at']='2026-10-09T12:00:00Z'
        original.update(status='pending_refresh',accepted_views=3,pending_current_views=1,fresh_views=3)
        m.write(self.base/'manifest.json',original)
        receipt=m.build(self.root,self.base,self.task,self.out,history={},preserve_gallery_iteration=True)
        packaged=m.read(self.out/'manifest.json')
        for key,value in original.items():
            self.assertEqual(packaged[key],value,key)
        self.assertIn('3 fresh of 4 views, 1 pending',packaged['studio_note'])
        self.assertEqual(receipt['game_page_capture_dates'],['2026-10-09','2027-01-03'])
        self.assertFalse(receipt['human_approval'])

    def test_historical_packaging_still_clears_only_this_turn_flags(self):
        original=self.gallery_fixture()
        receipt=m.build(self.root,self.base,self.task,self.out,history={})
        packaged=m.read(self.out/'manifest.json')
        self.assertEqual(packaged['affected_routes'],[])
        self.assertEqual(packaged['fresh_views'],0)
        self.assertEqual(packaged['accepted_views'],original['accepted_views'])
        for before,after in zip(original['entries'],packaged['entries']):
            self.assertFalse(after['refreshed_this_iteration'])
            self.assertFalse(after['changed_this_iteration'])
            self.assertEqual(after['capture_provenance'],before['capture_provenance'])
            self.assertEqual(after['current_capture_status'],before['current_capture_status'])
        self.assertIn('preserved historical evidence',packaged['studio_note'])
        self.assertEqual(receipt['this_turn_routes'],[])
        self.assertEqual(receipt['new_game_page_captures'],0)
        self.assertEqual(receipt['preserved_gallery_fresh_views'],0)


if __name__=='__main__':unittest.main()
